import SwiftUI

@main
struct BeerDebtApp: App {
    @State private var store: LedgerStore
    @State private var sync: HealthSync

    init() {
        // First, so a ledger that fails to load is reported.
        Telemetry.configure()
        let store = LedgerStore()
        let sync = HealthSync(store: store, health: HealthKitService())
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        // Runs on background launches too (HealthKit background delivery),
        // which is what keeps a closed app able to pay the tab and notify.
        sync.startBackgroundObserving()
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
        }
    }
}
