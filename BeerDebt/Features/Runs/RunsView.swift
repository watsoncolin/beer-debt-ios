import Charts
import SwiftUI

/// Runs (concept art screen 4): a range picker, the total for the range, a
/// bar chart, and the runs themselves as cards. Swipe a run to take it off
/// the books.
struct RunsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
        var id: String { rawValue }

        var caption: String {
            switch self {
            case .week: "this week"
            case .month: "this month"
            case .all: "all time"
            }
        }
    }

    @Environment(LedgerStore.self) private var store
    @State private var range: Range = .week
    @State private var runToDelete: RunStatement?

    var body: some View {
        let report = store.report()
        let runs = RunChart.runs(in: range, from: report, now: report.at)
        let buckets = RunChart.buckets(for: range, runs: runs, now: report.at)
        let total = runs.reduce(0) { $0 + $1.run.distanceMiles }

        List {
            Section {
                VStack(spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 2) {
                        Text(Format.miles(total))
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text(range.caption)
                            .font(.subheadline)
                            .foregroundStyle(Theme.cream.opacity(0.7))
                    }
                    .padding(.top, 8)

                    RunChartView(buckets: buckets)
                        .frame(height: 190)
                }
                .padding(.bottom, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }

            Section {
                if runs.isEmpty {
                    Text(range == .all ? "No runs yet. Apple Health will hand them over." : "No runs \(range.caption).")
                        .foregroundStyle(Theme.cream.opacity(0.7))
                        .cardRow()
                } else {
                    ForEach(runs) { statement in
                        RunCard(statement: statement)
                            .cardRow()
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { runToDelete = statement } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("Recent Runs")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .textCase(nil)
                    .padding(.leading, 4)
            }
        }
        .listStyle(.plain)
        .forestScreen()
        .navigationTitle("Runs")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Take this run off the books?",
            isPresented: Binding(get: { runToDelete != nil }, set: { if !$0 { runToDelete = nil } }),
            titleVisibility: .visible,
            presenting: runToDelete
        ) { statement in
            Button("Delete \(Format.miles(statement.run.distanceMiles)) run", role: .destructive) {
                store.deleteRun(id: statement.id)
            }
        } message: { _ in
            Text("Whatever it paid goes back on your tab. It stays in Apple Health but won't count here again.")
        }
    }
}

private struct RunCard: View {
    let statement: RunStatement

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(Theme.cream)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.miles(statement.run.distanceMiles))
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(Format.dateTime(statement.run.endedAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.65))
                if !statement.ignored, let detail = breakdown {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.cream.opacity(0.5))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if statement.ignored {
                    Pill(text: "Ignored", color: Theme.cream.opacity(0.6))
                } else {
                    Pill(text: "Applied", color: Theme.creditSoft)
                }
                if let day = statement.streakDayNumber {
                    Pill(text: "🔥 Day \(day)", color: Theme.gold)
                }
            }
        }
    }

    private var breakdown: String? {
        var parts: [String] = []
        if statement.debtPaidMiles > BalanceEngine.epsilon { parts.append("\(Format.miles(statement.debtPaidMiles)) to debt") }
        if statement.creditEarnedMiles > BalanceEngine.epsilon { parts.append("\(Format.miles(statement.creditEarnedMiles)) banked") }
        if statement.discardedMiles > BalanceEngine.epsilon { parts.append("\(Format.miles(statement.discardedMiles)) over the cap") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Miles per day / day-of-month / month, for the chart.
struct RunChart {
    struct Bucket: Identifiable {
        let id: Int
        let label: String
        let miles: Double
        let showsLabel: Bool
    }

    static func runs(in range: RunsView.Range, from report: Report, now: Date, calendar: Calendar = .current) -> [RunStatement] {
        let counted = report.runs.filter { !$0.ignored }
        let inRange: [RunStatement]
        switch range {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            inRange = counted.filter { interval?.contains($0.run.endedAt) ?? false }
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)
            inRange = counted.filter { interval?.contains($0.run.endedAt) ?? false }
        case .all:
            inRange = counted
        }
        return inRange.sorted { $0.run.endedAt > $1.run.endedAt }
    }

    static func buckets(for range: RunsView.Range, runs: [RunStatement], now: Date, calendar: Calendar = .current) -> [Bucket] {
        switch range {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: interval.start)!
                let miles = runs.filter { calendar.isDate($0.run.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.run.distanceMiles }
                let symbol = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
                return Bucket(id: offset, label: symbol, miles: miles, showsLabel: true)
            }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now),
                  let days = calendar.range(of: .day, in: .month, for: now) else { return [] }
            return days.map { dayNumber in
                let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: interval.start)!
                let miles = runs.filter { calendar.isDate($0.run.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.run.distanceMiles }
                return Bucket(id: dayNumber, label: "\(dayNumber)", miles: miles, showsLabel: dayNumber == 1 || dayNumber % 5 == 0)
            }
        case .all:
            let monthStart = calendar.dateInterval(of: .month, for: now)!.start
            return (0..<12).reversed().map { back in
                let start = calendar.date(byAdding: .month, value: -back, to: monthStart)!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                let miles = runs.filter { $0.run.endedAt >= start && $0.run.endedAt < end }.reduce(0) { $0 + $1.run.distanceMiles }
                let label = calendar.shortMonthSymbols[calendar.component(.month, from: start) - 1]
                return Bucket(id: 11 - back, label: label, miles: miles, showsLabel: back % 2 == 0)
            }
        }
    }
}

private struct RunChartView: View {
    let buckets: [RunChart.Bucket]

    private var yMax: Double { max(2, (buckets.map(\.miles).max() ?? 0) * 1.15) }

    var body: some View {
        Chart(buckets) { bucket in
            // Days with nothing get a stub, like the concept art, so the week reads as a row.
            let isStub = bucket.miles < BalanceEngine.epsilon
            BarMark(
                x: .value("Period", bucket.label),
                y: .value("Miles", isStub ? yMax * 0.015 : bucket.miles),
                width: .ratio(buckets.count > 12 ? 0.6 : 0.45)
            )
            .foregroundStyle(Theme.creditSoft.opacity(isStub ? 0.5 : 1))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: buckets.filter(\.showsLabel).map(\.label)) { _ in
                AxisValueLabel()
                    .font(.caption)
                    .foregroundStyle(Theme.cream.opacity(0.75))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Theme.cream.opacity(0.12))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Theme.cream.opacity(0.55))
            }
        }
        .chartYScale(domain: 0...yMax)
    }
}
