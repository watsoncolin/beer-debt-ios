import SwiftUI

/// Tune the rules (spec §13). Every change is recorded as a forward-only
/// rules event; nothing historical is recalculated.
struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(HealthSync.self) private var sync
    @State private var draft = Rules.default
    @State private var loaded = false
    @State private var notificationsDenied = false
    @State private var weeklyDenied = false

    private static let milesPresets: [Double] = [0.5, 1, 1.5, 2, 3, 5]
    private static let ratePresets: [Double] = [0, 0.05, 0.10, 0.15, 0.20, 0.25]
    private static let gracePresets: [TimeInterval] = [0, 12 * 3_600, 24 * 3_600, 48 * 3_600, 7 * 86_400]
    private static let decayPresets: [Double] = [0, 0.05, 0.10, 0.20, 0.25]

    var body: some View {
        Form {
            Section {
                Picker("Miles per Beer", selection: $draft.milesPerBeer) {
                    ForEach(options(Self.milesPresets, including: draft.milesPerBeer), id: \.self) {
                        Text(Format.miles($0)).tag($0)
                    }
                }
                Picker("Interest Rate", selection: $draft.interestRate) {
                    ForEach(options(Self.ratePresets, including: draft.interestRate), id: \.self) {
                        Text($0 == 0 ? "Off" : Format.percent($0)).tag($0)
                    }
                }
                Picker("Interest Frequency", selection: $draft.interestPeriod) {
                    ForEach(CompoundingPeriod.allCases) { Text($0.label).tag($0) }
                }
                Picker("Grace Period", selection: $draft.gracePeriod) {
                    ForEach(options(Self.gracePresets, including: draft.gracePeriod), id: \.self) {
                        Text(Format.gracePeriod($0)).tag($0)
                    }
                }
                Stepper(
                    "Maximum Credit: \(Format.beersLabel(draft.maximumCreditBeers))",
                    value: $draft.maximumCreditBeers,
                    in: 1...10,
                    step: 1
                )
                Picker("Credit Decay", selection: $draft.creditDecayRatePerWeek) {
                    ForEach(options(Self.decayPresets, including: draft.creditDecayRatePerWeek), id: \.self) {
                        Text($0 == 0 ? "Off" : "\(Format.percent($0)) / week").tag($0)
                    }
                }
            } header: {
                Text("The Rules")
            } footer: {
                Text("Changes apply from now on. Past interest and paid beers are never recalculated, so the economy doesn't shift under you.")
            }
            .listRowBackground(Theme.card)

            Section {
                if !sync.isAvailable {
                    Text("Apple Health isn't available on this device.")
                        .foregroundStyle(.secondary)
                } else if sync.isConnected {
                    LabeledContent("Apple Health", value: "Connected")
                    Button {
                        Task { await sync.sync() }
                    } label: {
                        HStack {
                            Text("Sync now")
                            Spacer()
                            if sync.isSyncing { ProgressView() }
                        }
                    }
                    if let last = sync.lastSyncAt {
                        LabeledContent("Last sync", value: Format.dateTime(last))
                    }
                    Toggle("Notify me when a run lands", isOn: Binding(
                        get: { sync.runNotificationsEnabled },
                        set: { on in
                            Task {
                                if on {
                                    let granted = await sync.enableRunNotifications()
                                    notificationsDenied = !granted
                                } else {
                                    sync.setRunNotifications(false)
                                }
                            }
                        }
                    ))
                    if notificationsDenied {
                        Text("Notifications are off for Beer Debt. Turn them on in Settings › Notifications › Beer Debt.")
                            .font(.footnote)
                            .foregroundStyle(Theme.debt)
                    }
                } else {
                    LabeledContent("Apple Health", value: "Not connected")
                    Button("Connect Apple Health") {
                        Task { await sync.connect() }
                    }
                }
                if let error = sync.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.debt)
                }
            } header: {
                Text("Health & Data")
            } footer: {
                Text("Only running workouts count toward your balance. Runs sync when you open the app and, once connected, in the background when a workout is saved. If runs aren't showing up, check Settings › Health › Data Access & Devices › Beer Debt.")
            }
            .listRowBackground(Theme.card)

            Section {
                Toggle("Weekly summary", isOn: Binding(
                    get: { sync.weekly.enabled },
                    set: { on in
                        Task {
                            if on {
                                weeklyDenied = !(await sync.enableWeeklySummary())
                            } else {
                                await sync.disableWeeklySummary()
                            }
                        }
                    }
                ))
                if sync.weekly.enabled {
                    Picker("Day", selection: Binding(
                        get: { sync.weekly.weekday },
                        set: { sync.weekly.weekday = $0; Task { await sync.rescheduleWeeklySummary() } }
                    )) {
                        ForEach(Array(zip(1...7, Calendar.current.weekdaySymbols)), id: \.0) { number, name in
                            Text(name).tag(number)
                        }
                    }
                    DatePicker("Time", selection: Binding(
                        get: { sync.weekly.timeOfDay },
                        set: { sync.weekly.timeOfDay = $0; Task { await sync.rescheduleWeeklySummary() } }
                    ), displayedComponents: .hourAndMinute)
                }
                if weeklyDenied {
                    Text("Notifications are off for Beer Debt. Turn them on in Settings › Notifications › Beer Debt.")
                        .font(.footnote)
                        .foregroundStyle(Theme.debt)
                }
            } header: {
                Text("Weekly Summary")
            } footer: {
                Text("A once-a-week recap: beers, miles, and where your tab stands.")
            }
            .listRowBackground(Theme.card)

            Section("About") {
                LabeledContent("Books opened", value: Format.dateTime(store.ledger.booksOpenedAt))
                LabeledContent("Version", value: Self.version)
            }
            .listRowBackground(Theme.card)
        }
        .listRowBackground(Theme.card)
        .forestScreen()
        .navigationTitle("Settings")
        .onAppear {
            if !loaded {
                draft = store.currentRules
                loaded = true
            }
        }
        .task {
            if !sync.runNotificationsEnabled {
                notificationsDenied = await sync.notificationPermissionDenied()
            }
        }
        .onChange(of: draft) { _, rules in
            if loaded { store.updateRules(rules) }
        }
    }

    private func options<T: Hashable & Comparable>(_ presets: [T], including current: T) -> [T] {
        Array(Set(presets + [current])).sorted()
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
