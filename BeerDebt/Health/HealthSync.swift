import Foundation
import Observation

/// Shown when a sync pays the tab off (spec §19).
struct DebtFreeCelebration: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    let totalBeers: Int
    let milesRepaid: Double
    let creditBeers: Double
}

/// Shown when a sync turns a one-day streak into two: interest is now paused (spec §25).
struct StreakCelebration: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    let days: Int
}

/// Drives HealthKit into the ledger: connect on onboarding, sync whenever the
/// app becomes active, and, once connected, on HealthKit background delivery
/// so a run pays the tab (and notifies) while the app is closed (spec §14,
/// §22). Runs that ended before the books opened are dropped here so they
/// never clutter the ledger. Workouts deleted from Health come off the books.
@MainActor
@Observable
final class HealthSync {
    private let store: LedgerStore
    private let health: HealthKitService
    private let notifier: RunNotifier
    private let defaults: UserDefaults

    private static let connectedKey = "health.connected"
    private static let anchorKey = "health.anchor"
    /// Bump when the way workouts are read changes; the next sync starts
    /// from scratch so workouts an older build skipped are picked up. The
    /// store dedups on workout id, so a full re-read is harmless.
    private static let importVersionKey = "health.importVersion"
    private static let importVersion = 2
    private static let notificationsKey = "notifications.runs"
    private static let pendingCelebrationKey = "celebration.pending"
    private static let pendingStreakKey = "celebration.streak.pending"

    private(set) var isConnected: Bool
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    /// Whether to post a notification when a run lands while the app is closed.
    private(set) var runNotificationsEnabled: Bool
    /// Once-a-week recap, configured in Settings.
    let weekly = WeeklySummary()
    /// True while the app is in the foreground; syncs then update the UI
    /// directly instead of notifying.
    var isAppActive = false
    var celebration: DebtFreeCelebration?
    var streakCelebration: StreakCelebration?

    init(store: LedgerStore, health: HealthKitService, notifier: RunNotifier = RunNotifier(), defaults: UserDefaults = .standard) {
        self.store = store
        self.health = health
        self.notifier = notifier
        self.defaults = defaults
        isConnected = defaults.bool(forKey: Self.connectedKey)
        runNotificationsEnabled = defaults.bool(forKey: Self.notificationsKey)
    }

    var isAvailable: Bool { health.isAvailable }

    // MARK: Connecting

    /// Ask for HealthKit access, then pull whatever is already there.
    func connect() async {
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return
        }
        do {
            try await health.requestAuthorization()
            isConnected = true
            defaults.set(true, forKey: Self.connectedKey)
            startBackgroundObserving()
            await sync()
        } catch {
            let failure = HealthFailure(error)
            lastError = failure.message(or: error.localizedDescription)
            if failure.isReportable {
                Telemetry.report(error, context: "health", ["op": "connect"])
            }
        }
    }

    /// Call at every launch. Registers for background delivery and starts the
    /// observer that triggers a sync whenever running workouts change.
    func startBackgroundObserving() {
        guard isConnected, isAvailable else { return }
        Task { [health] in
            do {
                try await health.enableBackgroundDelivery()
            } catch where HealthFailure(error).isReportable {
                Telemetry.report(error, context: "health", ["op": "backgroundDelivery"])
            } catch {
                // A locked phone or missing permission: nothing to fix here.
            }
        }
        health.startObservingWorkouts { [weak self] in
            await self?.sync()
        }
    }

    // MARK: Notifications

    /// Turns run notifications on, asking iOS for permission if needed.
    /// Returns false if permission was refused.
    @discardableResult
    func enableRunNotifications() async -> Bool {
        let granted = await notifier.requestAuthorization()
        setRunNotifications(granted)
        return granted
    }

    func setRunNotifications(_ enabled: Bool) {
        runNotificationsEnabled = enabled
        defaults.set(enabled, forKey: Self.notificationsKey)
    }

    func notificationPermissionDenied() async -> Bool {
        await notifier.authorizationStatus() == .denied
    }

    /// Turns the weekly summary on (asking for permission if needed) and
    /// schedules it. Returns false if permission was refused.
    @discardableResult
    func enableWeeklySummary() async -> Bool {
        let granted = await notifier.requestAuthorization()
        weekly.setEnabled(granted)
        await weekly.reschedule(ledger: store.ledger)
        return granted
    }

    func disableWeeklySummary() async {
        weekly.setEnabled(false)
        await weekly.reschedule(ledger: store.ledger)
    }

    /// Call whenever the ledger changes so the weekly copy stays exact.
    func rescheduleWeeklySummary() async {
        await weekly.reschedule(ledger: store.ledger)
    }

    // MARK: Syncing

    func syncIfConnected() async {
        guard isConnected else { return }
        await sync()
    }

    /// Moves the books-opened date back and re-reads Health from scratch so
    /// runs from the newly covered days come in (the store dedups on workout
    /// id, so nothing already imported doubles up).
    func reopenBooks(at date: Date) async {
        guard store.reopenBooks(at: date) else { return }
        defaults.removeObject(forKey: Self.anchorKey)
        await syncIfConnected()
    }

    /// Reads what changed in Health since the last anchor and applies it.
    func sync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            if defaults.integer(forKey: Self.importVersionKey) < Self.importVersion {
                defaults.removeObject(forKey: Self.anchorKey)
                defaults.set(Self.importVersion, forKey: Self.importVersionKey)
            }
            let result = try await health.fetchRunningWorkouts(anchor: defaults.data(forKey: Self.anchorKey))
            let before = store.report()
            let eligible = result.runs.filter { $0.endedAt >= store.ledger.booksOpenedAt }
            let added = store.importRuns(eligible)
            let removed = store.removeRuns(healthKitWorkoutIDs: Set(result.deletedWorkoutIDs))
            // The anchor is the only record of which workouts have been read,
            // so move it only once the runs it covers are on disk. If the
            // write failed, the in-memory books are ahead of the file: the
            // next launch would read a ledger without the run, and HealthKit,
            // asked from the advanced anchor, would never offer it again.
            // Leaving the anchor where it is costs a re-read and nothing else,
            // since the store dedups on workout id. This also makes every sync
            // a retry point for any earlier write that failed.
            guard store.persist() else {
                lastSyncAt = .now
                lastError = "Couldn't write the books to this phone. Your runs are safe in Health and will be read again next sync."
                return
            }
            defaults.set(result.anchor, forKey: Self.anchorKey)
            lastSyncAt = .now
            lastError = nil
            // Even when nothing changed. A reload asked for on a background
            // wake can be dropped, and the sync that would ask again imports
            // nothing the second time, so it never saves; this is what
            // repairs a face left showing yesterday's number.
            store.refreshWidgets()

            guard !added.isEmpty || removed > 0 else { return }
            let after = store.report()
            await weekly.reschedule(ledger: store.ledger)

            if !added.isEmpty, before.balance.state == .debt, after.balance.state != .debt {
                let party = DebtFreeCelebration(
                    totalBeers: after.beers.count,
                    milesRepaid: after.runs.reduce(0) { $0 + $1.debtPaidMiles },
                    creditBeers: after.balance.creditBeers
                )
                if isAppActive {
                    celebration = party
                } else {
                    // Show it next time the app opens; this process may not survive.
                    defaults.set(try? JSONEncoder().encode(party), forKey: Self.pendingCelebrationKey)
                }
            }

            let streakActivated = !added.isEmpty
                && !before.streak.interestProtectionActive && after.streak.interestProtectionActive
            if streakActivated {
                let party = StreakCelebration(days: after.streak.currentStreakDays)
                if isAppActive {
                    streakCelebration = party
                } else {
                    defaults.set(try? JSONEncoder().encode(party), forKey: Self.pendingStreakKey)
                }
            }

            if !isAppActive, runNotificationsEnabled {
                let paidBefore = before.beers.filter(\.isPaid).count
                let paidAfter = after.beers.filter(\.isPaid).count
                let change = RunNotifier.Change(
                    addedRuns: added, removedRuns: removed,
                    before: before.balance, after: after.balance,
                    beersPaidOff: max(0, paidAfter - paidBefore),
                    streakDays: after.streak.currentStreakDays,
                    streakDay: added.contains { after.streak.qualifies(on: $0.endedAt) },
                    streakActivated: streakActivated
                )
                if let message = RunNotifier.message(for: change) {
                    await notifier.post(message)
                }
            }
        } catch {
            let failure = HealthFailure(error)
            lastError = failure.message(or: error.localizedDescription)
            if failure.isReportable {
                Telemetry.report(error, context: "health", [
                    "op": "sync", "hadAnchor": defaults.data(forKey: Self.anchorKey) != nil,
                ])
            }
        }
    }

    /// Surfaces a celebration earned while the app was closed. Debt-free first;
    /// the streak sheet waits until that one is dismissed.
    func showPendingCelebration() {
        if celebration == nil,
           let data = defaults.data(forKey: Self.pendingCelebrationKey),
           let party = try? JSONDecoder().decode(DebtFreeCelebration.self, from: data) {
            defaults.removeObject(forKey: Self.pendingCelebrationKey)
            celebration = party
            return
        }
        if celebration == nil, streakCelebration == nil,
           let data = defaults.data(forKey: Self.pendingStreakKey),
           let party = try? JSONDecoder().decode(StreakCelebration.self, from: data) {
            defaults.removeObject(forKey: Self.pendingStreakKey)
            streakCelebration = party
        }
    }
}
