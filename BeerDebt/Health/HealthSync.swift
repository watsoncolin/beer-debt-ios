import Foundation
import Observation

/// Shown when a sync pays the tab off (spec §19).
struct DebtFreeCelebration: Identifiable, Equatable, Sendable {
    let id = UUID()
    let totalBeers: Int
    let milesRepaid: Double
    let creditBeers: Double
}

/// Drives HealthKit sync into the ledger: connect on onboarding, sync whenever
/// the app becomes active (spec §14). Runs that ended before the books opened
/// are dropped here so they never clutter the ledger.
@MainActor
@Observable
final class HealthSync {
    private let store: LedgerStore
    private let health: HealthKitService
    private let defaults: UserDefaults

    private static let connectedKey = "health.connected"
    private static let anchorKey = "health.anchor"

    private(set) var isConnected: Bool
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    var celebration: DebtFreeCelebration?

    init(store: LedgerStore, health: HealthKitService, defaults: UserDefaults = .standard) {
        self.store = store
        self.health = health
        self.defaults = defaults
        isConnected = defaults.bool(forKey: Self.connectedKey)
    }

    var isAvailable: Bool { health.isAvailable }

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
            await sync()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncIfConnected() async {
        guard isConnected else { return }
        await sync()
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await health.fetchRunningWorkouts(anchor: defaults.data(forKey: Self.anchorKey))
            let before = store.report().balance
            let eligible = result.runs.filter { $0.endedAt >= store.ledger.booksOpenedAt }
            let added = store.importRuns(eligible)
            defaults.set(result.anchor, forKey: Self.anchorKey)
            lastSyncAt = .now
            lastError = nil

            if added > 0, before.state == .debt {
                let after = store.report()
                if after.balance.state != .debt {
                    celebration = DebtFreeCelebration(
                        totalBeers: after.beers.count,
                        milesRepaid: after.runs.reduce(0) { $0 + $1.debtPaidMiles },
                        creditBeers: after.balance.creditBeers
                    )
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
