import SwiftUI

/// The Ledger (spec §12): every beer and every run, grouped the way the
/// concept art does it (screens 3 and 4) — Beers with active/paid sections,
/// Runs by day with a this-week total.
struct LedgerView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case beers = "Beers"
        case runs = "Runs"
        var id: String { rawValue }
    }

    @Environment(LedgerStore.self) private var store
    @State private var segment: Segment
    @State private var selectedBeer: BeerStatement?

    init(segment: Segment = .beers) {
        _segment = State(initialValue: segment)
    }

    var body: some View {
        let report = store.report()
        List {
            Section {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch segment {
            case .beers:
                BeerSections(report: report) { selectedBeer = $0 }
            case .runs:
                RunSections(report: report)
            }
        }
        .navigationTitle("The Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedBeer) { statement in
            BeerDetailSheet(beerID: statement.id)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            #if DEBUG
            if DebugLaunch.screen == "beerDetail" { selectedBeer = report.beers.last }
            #endif
        }
    }
}

// MARK: - Beers

private struct BeerSections: View {
    let report: Report
    let select: (BeerStatement) -> Void

    var body: some View {
        let active = Array(report.beers.filter { !$0.isPaid }.reversed())
        let paid = Array(report.beers.filter { $0.isPaid }.reversed())

        if report.beers.isEmpty {
            Section {
                ContentUnavailableView(
                    "No beers yet",
                    systemImage: "mug",
                    description: Text("Tap + Beer on the home screen. You know you want to.")
                )
            }
        }
        if !active.isEmpty {
            Section {
                ForEach(active) { statement in
                    Button { select(statement) } label: {
                        BeerRow(statement: statement, now: report.at)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Active (\(active.count))")
            } footer: {
                Label("Runs are applied to your oldest beers first.", systemImage: "info.circle")
            }
        }
        if !paid.isEmpty {
            Section("Paid (\(paid.count))") {
                ForEach(paid) { statement in
                    Button { select(statement) } label: {
                        BeerRow(statement: statement, now: report.at)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BeerRow: View {
    let statement: BeerStatement
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("🍺")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Beer #\(statement.number)")
                    .font(.headline)
                Text(Format.dateTime(statement.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if statement.isPaid {
                    Pill(text: "PAID")
                    Text(Format.miles(statement.costMiles, decimals: 2))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(paidCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Format.miles(statement.outstandingMiles, decimals: 2))
                        .font(.headline)
                        .foregroundStyle(Theme.debt)
                    Text(Format.miles(statement.principalMiles, decimals: 2))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Format.age(from: statement.createdAt, to: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var paidCaption: String {
        if statement.settledByCredit { return "from credit" }
        if let paidAt = statement.paidAt { return "paid \(Format.day(paidAt))" }
        return ""
    }
}

// MARK: - Runs

private struct RunSections: View {
    let report: Report

    private struct DayGroup: Identifiable {
        let day: Date
        let runs: [RunStatement]
        var id: Date { day }
    }

    var body: some View {
        if report.runs.isEmpty {
            Section {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "figure.run",
                    description: Text("Running workouts from Apple Health show up here and pay your tab automatically.")
                )
            }
        } else {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.miles(report.milesRun(inWeekOf: report.at)))
                        .font(.title.weight(.bold))
                    Text("this week")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            ForEach(groups) { group in
                Section(Format.dayHeader(group.day, now: report.at)) {
                    ForEach(group.runs) { statement in
                        RunRow(statement: statement)
                    }
                }
            }
        }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: report.runs) { calendar.startOfDay(for: $0.run.endedAt) }
        return byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, runs: byDay[day]!.sorted { $0.run.endedAt > $1.run.endedAt })
        }
    }
}

private struct RunRow: View {
    let statement: RunStatement

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(Theme.credit)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.miles(statement.run.distanceMiles))
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(breakdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if statement.ignored {
                Pill(text: "Ignored", color: .secondary)
            } else {
                Pill(text: "Applied")
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var text = Format.dateTime(statement.run.endedAt)
        if let source = statement.run.sourceName { text += " · \(source)" }
        return text
    }

    private var breakdown: String {
        if statement.ignored { return "Before the books opened" }
        var parts: [String] = []
        if statement.debtPaidMiles > BalanceEngine.epsilon {
            parts.append("\(Format.miles(statement.debtPaidMiles)) to debt")
        }
        if statement.creditEarnedMiles > BalanceEngine.epsilon {
            parts.append("\(Format.miles(statement.creditEarnedMiles)) banked")
        }
        if statement.discardedMiles > BalanceEngine.epsilon {
            parts.append("\(Format.miles(statement.discardedMiles)) over the cap")
        }
        return parts.isEmpty ? "Nothing to apply" : parts.joined(separator: " · ")
    }
}
