import Charts
import SwiftUI

/// The tab over time: the total as a filled line, with principal drawn
/// underneath it so the space between the two *is* the interest. Not a stacked
/// area — the default rules compound at 10% a day (decisions §A.1), so within a
/// couple of months interest dwarfs principal and a stack buries the gold band
/// against the axis.
///
/// For the same reason the axis switches to a log scale once the range spans
/// more than two orders of magnitude. On a linear axis an exponential tab is a
/// flat line followed by a wall: literally true, and useless for seeing when
/// things turned.
struct PositionChart: View {
    let points: [MileMarkersReport.Point]
    /// Protected stretches and frozen days, washed in behind the curve. Faint
    /// on purpose: this is the answer to "why did it flatten here?", not a
    /// thing to read on its own.
    var spans: [MileMarkersReport.Span] = []

    private var values: [Double] { points.map(\.debtMiles).filter { $0 > 0 } }

    /// True when the smallest non-zero reading is more than 100× off the
    /// largest, which is when a linear axis stops showing the early history.
    var isLogarithmic: Bool {
        guard let high = values.max(), let low = values.min(), low > 0 else { return false }
        return high / low > 100
    }

    /// Fraction of the plot's height kept clear at the top for the marker lane,
    /// which is one row taller when there are freezes to put on their own.
    private var headroom: Double {
        if spans.isEmpty { return 0.04 }
        return spans.contains { $0.kind == .frozen } ? 0.22 : 0.16
    }

    /// Headroom has to be reserved in the scale's own space. On a log axis a
    /// plain multiplier buys almost nothing — ×1.5 on a range spanning three
    /// decades is a couple of pixels — so the ceiling is raised by the span
    /// itself, raised to the share of the height being reserved.
    private var yMax: Double {
        guard let high = values.max(), high > 0 else { return 1 }
        let f = headroom
        guard isLogarithmic, let low = values.min(), low > 0 else {
            return max(1, high * (1 + f))
        }
        return high * pow(high / low, f / (1 - f))
    }
    private var yMin: Double { isLogarithmic ? max(0.1, (values.min() ?? 1) * 0.8) : 0 }

    /// A frozen day is one day wide, which is sub-pixel at this scale, so it is
    /// widened a little to stay visible. Presentational only.
    private func bounds(_ span: MileMarkersReport.Span) -> (Date, Date) {
        guard span.kind == .frozen else { return (span.start, span.end) }
        let pad = max(0, (span.end.timeIntervalSince(span.start)) * 0.35)
        return (span.start.addingTimeInterval(-pad), span.end.addingTimeInterval(pad))
    }

    var body: some View {
        Chart {
            // First, so they sit behind the curve. A RectangleMark bounded on x
            // alone fills the plot's height and is clipped to it, which the
            // hand-drawn overlay this replaced was not.
            ForEach(spans) { span in
                let (from, to) = bounds(span)
                RectangleMark(
                    xStart: .value("From", from),
                    xEnd: .value("To", to)
                )
                .foregroundStyle(span.kind == .frozen
                                 ? Theme.frost.opacity(0.20)
                                 : Theme.gold.opacity(0.055))
            }
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Owed", max(point.debtMiles, yMin))
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Theme.debt.opacity(0.45), Theme.debt.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Owed", max(point.debtMiles, yMin)),
                    series: .value("Series", "Owed")
                )
                .foregroundStyle(Theme.debt)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            }
            // Principal underneath: the gap up to the red line is what the
            // waiting cost.
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Principal", max(point.principalMiles, yMin)),
                    series: .value("Series", "Principal")
                )
                .foregroundStyle(Theme.gold)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: yMin...yMax, type: isLogarithmic ? .symmetricLog : .linear)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.cream.opacity(0.12))
                AxisValueLabel {
                    if let miles = value.as(Double.self) {
                        Text(Format.compact(miles))
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.cream.opacity(0.55))
            }
        }
        .chartXAxis { dateAxis() }
        .chartLegend(.hidden)
        // On the log scale the domain floor is not zero, and the area fill is
        // drawn past it, out of the plot and over the strips below. Clip it.
        .clipped()
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let rect = geo[plot]
                    ForEach(markers) { marker in
                        if let x = proxy.position(forX: marker.date) {
                            Image(systemName: marker.symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(marker.colour)
                                .position(x: rect.minX + x,
                                          y: rect.minY + 9 + CGFloat(marker.row) * 14)
                        }
                    }
                }
            }
        }
    }

    /// The lane says *when*; the wash behind the curve says *how long*. Which
    /// spans earn an icon, where it sits and which row it is on are `Span`'s
    /// own rules.
    private var markers: [Marker] {
        spans.filter(\.isMarked).map { span in
            Marker(
                date: span.markerDate,
                symbol: span.kind == .frozen ? "snowflake" : "flame.fill",
                colour: span.kind == .frozen ? Theme.frost : Theme.gold,
                row: span.markerRow
            )
        }
    }

    struct Marker: Identifiable {
        let date: Date
        let symbol: String
        let colour: Color
        let row: Int
        /// A flame and a snowflake can share an instant, so the date alone
        /// isn't an identity.
        var id: String { "\(symbol)@\(date.timeIntervalSince1970)" }
    }
}

/// A flow, as bars under the position chart — the price-and-volume pairing.
/// Runs and beers get a strip each: one is miles, the other is a count, and
/// putting them on one axis would be a lie about the units.
struct FlowChart: View {
    let points: [MileMarkersReport.Point]
    let value: (MileMarkersReport.Point) -> Double
    let colour: Color

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Date", point.date),
                y: .value("Amount", value(point)),
                width: .fixed(3)
            )
            .foregroundStyle(colour)
            .cornerRadius(1.5)
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { _ in
                AxisGridLine().foregroundStyle(Theme.cream.opacity(0.10))
                AxisValueLabel().font(.caption2).foregroundStyle(Theme.cream.opacity(0.5))
            }
        }
        .chartXAxis(.hidden)
    }
}

/// Are you outpacing it? Two cumulative lines: miles the beers put on the tab,
/// and miles actually run. The gap between them is the whole app.
struct OutpacingChart: View {
    let points: [MileMarkersReport.Point]

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Miles", point.cumulativeBeerMiles),
                    series: .value("Series", "Owed")
                )
                .foregroundStyle(Theme.caution)
                .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Miles", point.cumulativeRunMiles),
                    series: .value("Series", "Run")
                )
                .foregroundStyle(Theme.credit)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { milesAxis() }
        .chartXAxis { dateAxis() }
        .chartLegend(.hidden)
    }
}

@AxisContentBuilder
private func milesAxis() -> some AxisContent {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Theme.cream.opacity(0.12))
        AxisValueLabel().font(.caption2).foregroundStyle(Theme.cream.opacity(0.55))
    }
}

@AxisContentBuilder
private func dateAxis() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Theme.cream.opacity(0.08))
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            .font(.caption2)
            .foregroundStyle(Theme.cream.opacity(0.6))
    }
}

/// Running days as a contribution grid: a column per week, a cell per day.
/// Warm where you ran, frost where a freeze covered the day, dark where
/// nothing happened — the streak's own palette (spec §25.1), so the grid reads
/// the same way the streak screen does.
struct StreakGrid: View {
    let days: [MileMarkersReport.Day]
    var calendar: Calendar = .current

    /// A year of columns is as much as a phone can show without the cells
    /// becoming specks; beyond that the grid shows the most recent year.
    private static let maxWeeks = 53

    private var weeks: [[MileMarkersReport.Day?]] {
        guard let first = days.first else { return [] }
        // Pad the first column so rows line up with weekdays.
        let leading = calendar.component(.weekday, from: first.date) - calendar.firstWeekday
        var cells: [MileMarkersReport.Day?] = Array(repeating: nil, count: (leading + 7) % 7)
        cells.append(contentsOf: days.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        let columns = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        return columns.suffix(Self.maxWeeks)
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(weeks.count, 1)
            let spacing: CGFloat = count > 30 ? 1.5 : 3
            let side = max(3, min(16, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: side > 8 ? 3 : 1.5, style: .continuous)
                                .fill(colour(for: day))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let count = max(weeks.count, 1)
        let spacing: CGFloat = count > 30 ? 1.5 : 3
        let side = max(3, min(16, (UIScreen.main.bounds.width - 88 - spacing * CGFloat(count - 1)) / CGFloat(count)))
        return side * 7 + spacing * 6
    }

    private func colour(for day: MileMarkersReport.Day?) -> Color {
        guard let day else { return .clear }
        if day.frozen { return Theme.frost.opacity(0.85) }
        guard day.qualifies else {
            // A short run still shows, faintly: it happened.
            return day.miles > 0.05 ? Theme.creditSoft.opacity(0.28) : Theme.cream.opacity(0.07)
        }
        // Three bands, so a long day reads differently from a bare mile.
        switch day.miles {
        case 4...: return Theme.credit
        case 2..<4: return Theme.credit.opacity(0.75)
        default: return Theme.creditSoft.opacity(0.55)
        }
    }
}
