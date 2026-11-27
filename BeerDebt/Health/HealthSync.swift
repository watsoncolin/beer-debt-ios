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

/// Shown when a synced run is the fifth running day, earning a streak freeze
/// (spec §25.1). The freeze is never spent here; this only says it is in hand.
struct FreezeEarnedCelebration: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    let streakDays: Int
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
    /// One anchor per read scope, because each reads a different slice of
    /// Health: widening to every workout starts that scope's read from
    /// scratch without touching where the runs-only read stood, and a sync
    /// already in flight when the scope widens can only advance the anchor
    /// of the scope it started in. Runs keeps the original key, so an
    /// upgrade carries on where it was.
    private static func anchorKey(for scope: PaymentMode) -> String {
        switch scope {
        case .runs: "health.anchor"
        case .calories: "health.anchor.calories"
        }
    }

    /// What to read from Health: running workouts only until calorie mode has
    /// ever been in force, every workout from then on, whatever the mode now.
    /// A ride that ended in calorie mode but syncs after a switch back to runs
    /// still pays, and its deletion from Health is still seen. Rides that
    /// ended while runs were in force are read and dropped at import, so a
    /// runs-only user is never asked for, or read beyond, their runs.
    private var readScope: PaymentMode { store.ledger.hasCaloriePeriod ? .calories : .runs }
    /// Bump when the way workouts are read changes; the next sync starts
    /// from scratch so workouts an older build skipped are picked up. The
    /// store dedups on workout id, so a full re-read is harmless.
    private static let importVersionKey = "health.importVersion"
    private static let importVersion = 2
    private static let notificationsKey = "notifications.runs"
    private static let pendingCelebrationKey = "celebration.pending"
    private static let pendingStreakKey = "celebration.streak.pending"
    private static let pendingFreezeKey = "celebration.freeze.pending"

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
    /// A sync was asked for while one was running; run again when it ends.
    private var syncRequested = false
    var celebration: DebtFreeCelebration?
    var streakCelebration: StreakCelebration?
    var freezeEarned: FreezeEarnedCelebration?

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
            try await health.requestAuthorization(for: readScope)
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
    /// observer that triggers a sync whenever the workouts in the read scope
    /// change.
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
        health.startObservingWorkouts(for: readScope) { [weak self] in
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
        dropAnchors()
        await syncIfConnected()
    }

    /// Switches what pays the tab from now on (spec §28, decisions §B.10).
    ///
    /// Forward-only: nothing already on the books changes, so there is
    /// nothing to re-read for the past and nothing to celebrate. The first
    /// switch to calories asks for the wider Health permission and widens
    /// the read to every workout, which then stays wide (`readScope`).
    /// Declining the permission still switches the mode: workouts come in
    /// without calories and pay nothing, and the Apple Health row says why.
    /// A rate change alone touches nothing in Health.
    func updatePayment(_ payment: PaymentBasis) async {
        let switching = payment.mode != store.ledger.paymentMode
        let scope = readScope
        store.updatePayment(payment)
        guard switching, isConnected, isAvailable else { return }
        if payment.mode == .calories {
            do {
                try await health.requestAuthorization(for: .calories)
            } catch {
                let failure = HealthFailure(error)
                lastError = failure.message(or: error.localizedDescription)
                if failure.isReportable {
                    Telemetry.report(error, context: "health", ["op": "authorizeCalories"])
                }
            }
        }
        guard readScope != scope else { return }
        startBackgroundObserving()
        await sync()
    }

    private func dropAnchors() {
        for mode in PaymentMode.allCases {
            defaults.removeObject(forKey: Self.anchorKey(for: mode))
        }
    }

    /// Reads what changed in Health since the last anchor and applies it.
    /// Asked for while one is running, it runs again once that one ends, so a
    /// scope widened mid-sync still gets its read.
    func sync() async {
        guard isConnected else { return }
        guard !isSyncing else {
            syncRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncRequested = false
            await syncOnce()
        } while syncRequested
    }

    private func syncOnce() async {
        // Captured once: a scope widened mid-read can only move the anchor of
        // the scope the read started in.
        let scope = readScope
        let anchorKey = Self.anchorKey(for: scope)
        do {
            if defaults.integer(forKey: Self.importVersionKey) < Self.importVersion {
                dropAnchors()
                defaults.set(Self.importVersion, forKey: Self.importVersionKey)
            }
            let result = try await health.fetchWorkouts(for: scope, anchor: defaults.data(forKey: anchorKey))
            let before = store.report()
            // Forward-only (decisions §B.10): a workout that the basis in force
            // when it ended doesn't count will never count, so it never reaches
            // the books. That is a ride from a runs-mode stretch, read because
            // the scope went wide.
            let ledger = store.ledger
            let eligible = result.runs.filter {
                $0.endedAt >= ledger.booksOpenedAt && ledger.miles(paidBy: $0) != nil
            }
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
            defaults.set(result.anchor, forKey: anchorKey)
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

            // The fifth running day put a freeze in hand. Derived, so a run
            // that imports late still earns it -- and a deleted run that
            // un-earns it simply stops the sheet appearing next time.
            if !added.isEmpty, before.streak.freezesHeld == 0, after.streak.freezesHeld > 0 {
                let party = FreezeEarnedCelebration(streakDays: after.streak.currentStreakDays)
                if isAppActive {
                    freezeEarned = party
                } else {
                    defaults.set(try? JSONEncoder().encode(party), forKey: Self.pendingFreezeKey)
                }
            }

            if !isAppActive, runNotificationsEnabled {
                let paidBefore = before.beers.filter(\.isPaid).count
                let paidAfter = after.beers.filter(\.isPaid).count
                let addedIDs = Set(added.map(\.id))
                let change = RunNotifier.Change(
                    addedRuns: added, removedRuns: removed,
                    before: before.balance, after: after.balance,
                    debtPaidMiles: after.runs
                        .filter { addedIDs.contains($0.run.id) }
                        .reduce(0) { $0 + $1.debtPaidMiles },
                    paidMiles: after.runs
                        .filter { addedIDs.contains($0.run.id) }
                        .reduce(0) { $0 + $1.paidMiles },
                    beersPaidOff: max(0, paidAfter - paidBefore),
                    streakDays: after.streak.currentStreakDays,
                    streakDay: added.contains { after.streak.qualifies(on: $0.endedAt) },
                    streakActivated: streakActivated,
                    units: Units(payment: store.ledger.payment)
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
                    "op": "sync", "scope": scope.rawValue, "hadAnchor": defaults.data(forKey: anchorKey) != nil,
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
            return
        }
        // Last in the queue: earning a freeze is the quietest of the three.
        if celebration == nil, streakCelebration == nil, freezeEarned == nil,
           let data = defaults.data(forKey: Self.pendingFreezeKey),
           let party = try? JSONDecoder().decode(FreezeEarnedCelebration.self, from: data) {
            defaults.removeObject(forKey: Self.pendingFreezeKey)
            freezeEarned = party
        }
    }
}
