import SwiftUI

/// Single NavigationStack rooted at Home. Ledger and Settings are pushed;
/// beer feedback, beer detail, and the debt-free celebration are sheets
/// (spec §20: no tab bar).
struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(HealthSync.self) private var sync
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        @Bindable var sync = sync
        Group {
            if onboardingComplete {
                NavigationStack(path: $path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .debt: DebtView()
                            case .runs: RunsView()
                            case .settings: SettingsView()
                            case .widgetPreview: WidgetPreviewScreen()
                            }
                        }
                }
            } else {
                HealthOnboardingView { onboardingComplete = true }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task {
            sync.isAppActive = true
            await sync.syncIfConnected()
            sync.showPendingCelebration()
        }
        .onChange(of: scenePhase) { _, phase in
            sync.isAppActive = (phase == .active)
            if phase == .active {
                Task {
                    await sync.syncIfConnected()
                    sync.showPendingCelebration()
                }
            }
        }
        .sheet(item: $sync.celebration) { celebration in
            DebtFreeSheet(celebration: celebration)
        }
        .onChange(of: store.ledger) { _, _ in
            Task { await sync.rescheduleWeeklySummary() }
        }
        .onAppear(perform: applyDebugLaunch)
    }

    /// Screenshot / manual-test helper: `-debugScreen ledger|runs|settings|debtFree|beerDetail|beerAdded`
    /// as a launch argument opens that screen directly. No-op in release.
    private func applyDebugLaunch() {
        #if DEBUG
        switch DebugLaunch.screen {
        case "ledger", "beerDetail": path.append(Route.debt)
        case "runs": path.append(Route.runs)
        case "settings": path.append(Route.settings)
        case "widgets": path.append(Route.widgetPreview)
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
    case debt
    case runs
    case settings
    case widgetPreview
}

#if DEBUG
enum DebugLaunch {
    /// Launch arguments of the form `-key value` land in UserDefaults.
    static var screen: String? { UserDefaults.standard.string(forKey: "debugScreen") }
}
#endif
