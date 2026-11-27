import SwiftUI

/// Tune the rules (spec §13). Every change is recorded as a forward-only
/// rules event; nothing historical is recalculated.
struct SettingsView: View {
    @Environment(\.units) private var units
    @Environment(LedgerStore.self) private var store
    @Environment(HealthSync.self) private var sync
    @State private var draft = Rules.default
    @State private var loaded = false
    @State private var notificationsDenied = false
    @State private var weeklyDenied = false
    @State private var reopeningBooks = false
    @State private var filing: BankruptcySheet.Filing?

    private static let milesPresets: [Double] = [0.5, 1, 1.5, 2, 3, 5]
    private static let caloriePresets: [Double] = [80, 100, 120, 150]
    private static let ratePresets: [Double] = [0, 0.05, 0.10, 0.15, 0.20, 0.25]
    private static let gracePresets: [TimeInterval] = [0, 12 * 3_600, 24 * 3_600, 48 * 3_600, 7 * 86_400]
    private static let decayPresets: [Double] = [0, 0.05, 0.10, 0.20, 0.25]

    var body: some View {
        Form {
            Section {
                Picker("Pay With", selection: Binding(
                    get: { store.ledger.paymentMode },
                    set: { mode in
                        var payment = store.ledger.payment
                        payment.mode = mode
                        Task { await sync.updatePayment(payment) }
                    }
                )) {
                    Text("Runs").tag(PaymentMode.runs)
                    Text("Calories").tag(PaymentMode.calories)
                }
                .pickerStyle(.segmented)
                if units.isCalories {
                    Picker("Calories per Mile", selection: Binding(
                        get: { store.ledger.caloriesPerMile },
                        set: { rate in
                            var payment = store.ledger.payment
                            payment.caloriesPerMile = rate
                            Task { await sync.updatePayment(payment) }
                        }
                    )) {
                        ForEach(options(Self.caloriePresets, including: store.ledger.caloriesPerMile), id: \.self) {
                            Text("\(Format.number($0, decimals: 0)) kcal").tag($0)
                        }
                    }
                }
            } header: {
                Text("Pay With")
            } footer: {
                Text(units.isCalories
                    ? "Every workout counts. A run pays its distance; anything else pays the active calories it burned, at \(Format.number(store.ledger.caloriesPerMile, decimals: 0)) kcal a mile. Changes apply from now on: what's already paid stays paid."
                    : "Only running workouts count, by distance. Switch to calories to let rides, swims and lifts pay from now on. What's already paid stays paid.")
            }
            .listRowBackground(Theme.card)

            Section {
                Picker(units.isCalories ? "Calories per Beer" : "Miles per Beer", selection: $draft.milesPerBeer) {
                    ForEach(options(Self.milesPresets, including: draft.milesPerBeer), id: \.self) {
                        Text(units.amount($0)).tag($0)
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
                    Toggle("Notify me when a \(units.workout) lands", isOn: Binding(
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
                Text(units.isCalories
                    ? "Every workout counts toward your balance, by calories burned. Workouts sync when you open the app and, once connected, in the background when one is saved. If calories aren't showing up, allow Workouts and Active Energy in Settings › Health › Data Access & Devices › Beer Debt."
                    : "Only running workouts count toward your balance. Runs sync when you open the app and, once connected, in the background when a workout is saved. If runs aren't showing up, check Settings › Health › Data Access & Devices › Beer Debt.")
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
                Text("A once-a-week recap: beers, \(units.word), and where your tab stands.")
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    reopeningBooks = true
                } label: {
                    LabeledContent("Books opened", value: Format.dateTime(store.ledger.booksOpenedAt))
                }
                .foregroundStyle(Theme.cream)
                LabeledContent("Version", value: Self.version)
            } header: {
                Text("About")
            } footer: {
                Text("\(units.workoutsTitle) that ended before the books opened don't count. Tap the date to open the books earlier and pull those \(units.workout)s in from Apple Health.")
            }
            .listRowBackground(Theme.card)

            Section {
                Button(role: .destructive) {
                    filing = BankruptcySheet.Filing(report: store.report())
                } label: {
                    Text("Declare Bankruptcy")
                        .foregroundStyle(Theme.debt)
                }
            } header: {
                Text("Fresh Start")
            } footer: {
                Text("Tab got away from you? Write the whole thing off and open clean books. Your rules carry over; the beers, \(units.workout)s, and streak don't.")
            }
            .listRowBackground(Theme.card)
        }
        .sheet(item: $filing) { filing in
            BankruptcySheet(filing: filing, startWrittenOff: Self.debugWrittenOff) {
                store.declareBankruptcy()
            }
        }
        .sheet(isPresented: $reopeningBooks) {
            ReopenBooksSheet(current: store.ledger.booksOpenedAt) { date in
                Task { await sync.reopenBooks(at: date) }
            }
            .presentationDetents([.medium])
        }
        .listRowBackground(Theme.card)
        .forestScreen()
        .navigationTitle("Settings")
        .onAppear {
            if !loaded {
                draft = store.currentRules
                loaded = true
            }
            #if DEBUG
            if DebugLaunch.screen?.hasPrefix("bankruptcy") == true {
                filing = BankruptcySheet.Filing(report: store.report())
            }
            #endif
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

    /// `-debugScreen bankruptcyWrittenOff` opens the sheet already stamped,
    /// the only way to screenshot that half. Always false in release.
    private static var debugWrittenOff: Bool {
        #if DEBUG
        DebugLaunch.screen == "bankruptcyWrittenOff"
        #else
        false
        #endif
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Pick an earlier opening for the books (Settings › About). Earlier only,
/// at most a year back; the sync re-reads Health afterwards.
private struct ReopenBooksSheet: View {
    @Environment(\.units) private var units
    @Environment(\.dismiss) private var dismiss
    let current: Date
    let onPick: (Date) -> Void
    @State private var date: Date

    init(current: Date, onPick: @escaping (Date) -> Void) {
        self.current = current
        self.onPick = onPick
        _date = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Books opened", selection: $date,
                               in: Date.now.addingTimeInterval(-LedgerStore.reopeningWindow)...current)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("\(units.workoutsTitle) from Apple Health that ended after this instant count. Beers already on the tab and interest already posted stay as they are.")
                }
                .listRowBackground(Theme.card)
            }
            .forestScreen()
            .navigationTitle("Open the books earlier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move back") { onPick(date); dismiss() }
                        .disabled(date >= current)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
