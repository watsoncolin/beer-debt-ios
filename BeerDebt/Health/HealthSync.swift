import Foundation
import Observation

/// Shown when a sync pays the tab off (spec §19).
struct DebtFreeCelebration: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    let totalBeers: Int
    let milesRepaid: Double
    let creditBeers: Double
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
    private static let notificationsKey = "notifications.runs"
    private static let pendingCelebrationKey = "celebration.pending"

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
            lastError = error.localizedDescription
        }
    }

    /// Call at every launch. Registers for background delivery and starts the
    /// observer that triggers a sync whenever running workouts change.
    func startBackgroundObserving() {
        guard isConnected, isAvailable else { return }
        Task { [health] in
            try? await health.enableBackgroundDelivery()
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

    /// Reads what changed in Health since the last anchor and applies it.
    func sync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await health.fetchRunningWorkouts(anchor: defaults.data(forKey: Self.anchorKey))
            let before = store.report()
            let eligible = result.runs.filter { $0.endedAt >= store.ledger.booksOpenedAt }
            let added = store.importRuns(eligible)
            let removed = store.removeRuns(healthKitWorkoutIDs: Set(result.deletedWorkoutIDs))
            defaults.set(result.anchor, forKey: Self.anchorKey)
            lastSyncAt = .now
            lastError = nil

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

            if !isAppActive, runNotificationsEnabled {
                let paidBefore = before.beers.filter(\.isPaid).count
                let paidAfter = after.beers.filter(\.isPaid).count
                let change = RunNotifier.Change(
                    addedRuns: added, removedRuns: removed,
                    before: before.balance, after: after.balance,
                    beersPaidOff: max(0, paidAfter - paidBefore)
                )
                if let message = RunNotifier.message(for: change) {
                    await notifier.post(message)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Surfaces a celebration earned while the app was closed.
    func showPendingCelebration() {
        guard celebration == nil,
              let data = defaults.data(forKey: Self.pendingCelebrationKey),
              let party = try? JSONDecoder().decode(DebtFreeCelebration.self, from: data) else { return }
        defaults.removeObject(forKey: Self.pendingCelebrationKey)
        celebration = party
    }
}
