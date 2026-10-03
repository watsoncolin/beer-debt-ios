import SwiftUI

/// "Mile Markers": the whole history in one screen — where the tab has been,
/// what the interest cost, whether the running is keeping up, and the records
/// behind it.
///
/// Everything here is read-only and derived. The build is handed to a
/// background task because the balance curve costs one engine replay per
/// sampled point and the engine has no way to emit a series from one pass; see
/// `MileMarkersRange.samples`. The result is cached in `@State` and rebuilt
/// only when the range or the ledger changes, never in `body`.
struct MileMarkersView: View {
    @Environment(LedgerStore.self) private var store
    @State private var range: MileMarkersRange = .quarter
    @State private var report: MileMarkersReport?
    @State private var building = false

    var body: some View {
        // The picker sits above the List rather than being a section in it: as
        // a section it cost a sixth of the screen to List padding and scrolled
        // away just when you wanted to change range.
        VStack(spacing: 10) {
            Picker("Range", selection: $range) {
                ForEach(MileMarkersRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            list
        }
        .forestScreen()
        .navigationTitle("Mile Markers")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { await build() }
        .onChange(of: store.ledger) { _, _ in Task { await build() } }
    }

    private var list: some View {
        List {
            if let report, !report.isEmpty {
                position(report)
                headlines(report)
                outpacing(report)
                streak(report)
                superlatives(report)
            } else if building {
                placeholder("Reading the books…")
            } else if report != nil {
                placeholder("Nothing on the books over \(range.phrase). Log a beer or go for a run.")
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
    }

    private func build() async {
        let ledger = store.ledger
        let range = range
        let now = Date()
        let calendar = Calendar.current
        building = true
        defer { building = false }
        report = await Task.detached(priority: .userInitiated) {
            MileMarkersStats.build(ledger: ledger, range: range, now: now, calendar: calendar)
        }.value
    }

    // MARK: Sections

    private func position(_ report: MileMarkersReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.compactMiles(report.debtAtEndMiles))
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Spacer()
                        change(report)
                    }
                    Text(report.debtAtEndMiles < 0.05 ? "books are clean" : "on the tab")
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                }

                let chart = PositionChart(points: report.points, spans: report.spans)
                chart.frame(height: 160)
                key(legend(for: report), note: chart.isLogarithmic ? "log scale" : nil)

                VStack(alignment: .leading, spacing: 2) {
                    strip("miles run", Theme.creditSoft)
                    FlowChart(points: report.points, value: { $0.runMiles }, colour: Theme.creditSoft)
                        .frame(height: 38)
                    strip("beers", Theme.caution)
                    FlowChart(points: report.points, value: { Double($0.beers) }, colour: Theme.caution)
                        .frame(height: 30)
                }
                .padding(.top, 2)

                if !report.events.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.events) { event in
                            HStack(spacing: 8) {
                                Text(Format.day(event.date))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.cream.opacity(0.55))
                                    .frame(width: 52, alignment: .leading)
                                Text(event.title)
                                    .font(.caption)
                                    .foregroundStyle(Theme.cream.opacity(0.8))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
            .plainRow()
        } header: {
            header("The Tab")
        }
    }

    private func change(_ report: MileMarkersReport) -> some View {
        let delta = report.debtChangeMiles
        let flat = abs(delta) < 0.05
        return HStack(spacing: 4) {
            Image(systemName: flat ? "equal" : (delta < 0 ? "arrow.down.right" : "arrow.up.right"))
                .font(.caption.weight(.bold))
            Text(flat ? "flat" : Format.compactMiles(abs(delta)))
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(flat ? Theme.cream.opacity(0.6) : (delta < 0 ? Theme.credit : Theme.debt))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((flat ? Theme.cream : (delta < 0 ? Theme.credit : Theme.debt)).opacity(0.14), in: Capsule())
    }

    private func headlines(_ report: MileMarkersReport) -> some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    tile(Format.compact(report.milesRun), "miles run", "figure.run", Theme.creditSoft)
                    tile("\(report.beersAdded)", report.beersAdded == 1 ? "beer" : "beers", "mug.fill", Theme.gold)
                    tile(Format.compact(report.interestChargedMiles), "mi interest", "percent", Theme.debt)
                }
                // The number no other app can show: what the streak kept off
                // the books, from replaying the same ledger unprotected.
                if report.interestWaivedMiles > 0.05 {
                    HStack(spacing: 10) {
                        Image(systemName: "snowflake")
                            .foregroundStyle(Theme.frost)
                        Text("Your streak waived **\(Format.compactMiles(report.interestWaivedMiles))** of interest.")
                            .font(.footnote)
                            .foregroundStyle(Theme.cream.opacity(0.85))
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Theme.frost.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.vertical, 4)
            .plainRow()
        } header: {
            header("Over \(range.phrase)")
        }
    }

    private func outpacing(_ report: MileMarkersReport) -> some View {
        let owed = report.points.last?.cumulativeBeerMiles ?? 0
        let run = report.points.last?.cumulativeRunMiles ?? 0
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict(owed: owed, run: run))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(run >= owed ? Theme.credit : Theme.debt)
                    // Without this line the section contradicts the tab above:
                    // you can out-run every beer you ever drank and still be
                    // buried, because this compares what the beers cost and the
                    // tab is what the waiting turned that into.
                    if report.interestChargedMiles > 0.05 {
                        Text("Interest put \(Format.compactMiles(report.interestChargedMiles)) on top of that.")
                            .font(.caption)
                            .foregroundStyle(Theme.debt.opacity(0.9))
                    }
                }
                OutpacingChart(points: report.points)
                    .frame(height: 130)
                key([(Theme.caution, "beer miles"), (Theme.credit, "miles run")])
            }
            .padding(.vertical, 8)
            .plainRow()
        } header: {
            header("Keeping Up?")
        } footer: {
            Text("Beer miles are what the beers cost when you drank them. Interest is the tab above.")
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.5))
                .padding(.horizontal, 4)
        }
    }

    /// Principal only: beers drunk against miles run. Interest gets its own
    /// line, because folding it in here would make the chart's two series
    /// disagree with their own caption.
    private func verdict(owed: Double, run: Double) -> String {
        let gap = run - owed
        if abs(gap) < 0.1 { return "Dead even — every beer run off." }
        return gap > 0
            ? "Run \(Format.compactMiles(gap)) more than you drank."
            : "Drunk \(Format.compactMiles(-gap)) more than you've run."
    }

    private func streak(_ report: MileMarkersReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                StreakGrid(days: report.days)
                HStack(spacing: 10) {
                    tile("\(report.currentStreakDays)", "current", "flame.fill", Theme.gold)
                    tile("\(report.longestStreakDays)", "longest", "trophy.fill", Theme.caution)
                    tile("\(report.totalStreakDays)", "total days", "calendar", Theme.creditSoft)
                }
                HStack(spacing: 10) {
                    tile("\(report.freezesHeld)", report.freezesHeld == 1 ? "freeze held" : "freezes held", "snowflake", Theme.frost)
                    tile("\(report.freezesSpent)", "rest days", "zzz", Theme.frost)
                }
            }
            .padding(.vertical, 8)
            .plainRow()
        } header: {
            header("Running Days")
        } footer: {
            Text("Records are all-time. The grid covers \(range == .all ? "up to the last year" : range.phrase).")
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.5))
                .padding(.horizontal, 4)
        }
    }

    private func superlatives(_ report: MileMarkersReport) -> some View {
        Section {
            VStack(spacing: 0) {
                if let beer = report.priciestBeer, report.priciestBeerInterestMiles > 0.05 {
                    row("Priciest beer", "#\(beer.number)",
                        "\(Format.compactMiles(report.priciestBeerInterestMiles)) of interest", Theme.debt)
                }
                if let run = report.longestRun {
                    row("Longest run", Format.miles(run.run.distanceMiles), Format.day(run.run.endedAt), Theme.creditSoft)
                }
                if report.biggestDayBeers > 1, let day = report.biggestDay {
                    row("Biggest day", "\(report.biggestDayBeers) beers", Format.day(day), Theme.gold)
                }
                if report.longestDrySpellDays > 0 {
                    row("Longest dry spell", "\(report.longestDrySpellDays) days",
                        report.longestDrySpellDays >= 7 ? "impressive" : "", Theme.frost)
                }
            }
            .padding(.vertical, 4)
            .plainRow()
        } header: {
            header("Notable")
        }
    }

    // MARK: Pieces

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.cream)
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.top, 8)
    }

    private func tile(_ value: String, _ label: String, _ symbol: String, _ colour: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(colour)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.cream.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ label: String, _ value: String, _ detail: String, _ colour: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.cream.opacity(0.8))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colour)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.cream.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cream.opacity(0.08)).frame(height: 1)
        }
    }

    /// Only name the streak and freeze washes when there are any; an unused
    /// swatch is just clutter on a chart this small.
    private func legend(for report: MileMarkersReport) -> [(Color, String)] {
        var items: [(Color, String)] = [(Theme.debt, "owed"), (Theme.gold, "principal")]
        if report.spans.contains(where: { $0.kind == .protected }) {
            items.append((Theme.gold.opacity(0.35), "streak"))
        }
        if report.spans.contains(where: { $0.kind == .frozen }) {
            items.append((Theme.frost.opacity(0.6), "freeze"))
        }
        return items
    }

    private func key(_ items: [(Color, String)], note: String? = nil) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Circle().fill(item.0).frame(width: 7, height: 7)
                    Text(item.1)
                        .font(.caption2)
                        .foregroundStyle(Theme.cream.opacity(0.65))
                }
            }
            Spacer(minLength: 0)
            if let note {
                // Say so rather than quietly bending the axis under the reader.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.cream.opacity(0.45))
            }
        }
    }

    private func strip(_ label: String, _ colour: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.cream.opacity(0.6))
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func placeholder(_ text: String) -> some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    if building { ProgressView().tint(Theme.gold) }
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 60)
            .plainRow()
        }
    }
}

private extension View {
    /// A full-bleed row on the forest background: the charts draw their own
    /// cards, so the List shouldn't draw one around them.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
    }
}
