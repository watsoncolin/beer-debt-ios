import SwiftUI

/// Single NavigationStack rooted at Home. Ledger and Settings are pushed;
/// beer feedback, beer detail, and the debt-free celebration are sheets
/// (spec §20: no tab bar).
struct RootView: View {
    @State private var store: LedgerStore
    @State private var sync: HealthSync
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    init() {
        let store = LedgerStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: HealthSync(store: store, health: HealthKitService()))
    }

    var body: some View {
        @Bindable var sync = sync
        Group {
            if onboardingComplete {
                NavigationStack(path: $path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .ledger(let segment): LedgerView(segment: segment)
                            case .settings: SettingsView()
                            }
                        }
                }
            } else {
                HealthOnboardingView { onboardingComplete = true }
            }
        }
        .environment(store)
        .environment(sync)
        .tint(Theme.gold)
        .task { await sync.syncIfConnected() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await sync.syncIfConnected() }
            }
        }
        .sheet(item: $sync.celebration) { celebration in
            DebtFreeSheet(celebration: celebration)
        }
        .onAppear(perform: applyDebugLaunch)
    }

    /// Screenshot / manual-test helper: `-debugScreen ledger|runs|settings|debtFree|beerDetail|beerAdded`
    /// as a launch argument opens that screen directly. No-op in release.
    private func applyDebugLaunch() {
        #if DEBUG
        switch DebugLaunch.screen {
        case "ledger", "beerDetail": path.append(Route.ledger(.beers))
        case "runs": path.append(Route.ledger(.runs))
        case "settings": path.append(Route.settings)
        case "debtFree":
            let report = store.report()
            sync.celebration = DebtFreeCelebration(
                totalBeers: report.beers.count,
                milesRepaid: report.runs.reduce(0) { $0 + $1.debtPaidMiles },
                creditBeers: report.balance.creditBeers
            )
        default: break
        }
        #endif
    }
}

/// Pushed destinations. Sheets (beer added, beer detail, debt free) are local
/// state on the presenting view.
enum Route: Hashable {
    case ledger(LedgerView.Segment)
    case settings
}

#if DEBUG
enum DebugLaunch {
    /// Launch arguments of the form `-key value` land in UserDefaults.
    static var screen: String? { UserDefaults.standard.string(forKey: "debugScreen") }
}
#endif
