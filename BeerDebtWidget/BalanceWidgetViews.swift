import SwiftUI
import WidgetKit

struct BalanceEntry: TimelineEntry {
    let date: Date
    let report: Report?
}

/// The widget faces, shared with the app target so the DEBUG `-debugScreen
/// widgets` screen can render them for screenshots.
struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: BalanceEntry
    /// The app's DEBUG preview passes this; the real widget uses the environment.
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                LinearGradient(colors: [Theme.forest, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
            } else {
                Color.clear
            }
        }
    }

    private var balance: Balance? { entry.report?.balance }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            hero(numberSize: 44)
            Spacer(minLength: 0)
            Text(runLine)
                .font(.caption2)
                .foregroundStyle(Theme.cream.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                hero(numberSize: 48)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if let balance, balance.state == .debt {
                    HStack(spacing: 14) {
                        stat(Format.number(balance.principalMiles), "principal")
                        stat(Format.number(balance.interestMiles), "interest")
                    }
                } else if let balance, balance.state == .credit {
                    Text("Credit slowly expires.")
                        .font(.caption)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                } else {
                    Text("Drink now. Run later.")
                        .font(.caption)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                }
                Label(runLine, systemImage: "figure.run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.cream)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("🍺")
            Text("Beer Debt")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.cream)
        }
    }

    private func hero(numberSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroNumber)
                .font(.system(size: numberSize, weight: .black, design: .rounded))
                .foregroundStyle(Theme.cream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(heroCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(heroCaptionColor)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
    }

    // MARK: Lock Screen

    private var inline: some View {
        Text("🍺 \(standing)")
    }

    private var circular: some View {
        VStack(spacing: -2) {
            Text(heroNumber)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(circularCaption)
                .font(.system(size: 9, weight: .semibold))
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("🍺 Beer Debt")
                .font(.headline)
            Text(standing)
                .font(.title3.weight(.bold))
            Text(runLine)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Copy

    private var heroNumber: String {
        guard let balance else { return "–" }
        switch balance.state {
        case .debt: return Format.number(balance.debtMiles)
        case .credit: return Format.beers(balance.creditBeers)
        case .even: return "0"
        }
    }

    private var heroCaption: String {
        guard let balance else { return "open the app" }
        switch balance.state {
        case .debt: return "mi owed"
        case .credit: return balance.creditBeers < 1.05 ? "beer banked" : "beers banked"
        case .even: return "BOOKS ARE CLEAN"
        }
    }

    private var heroCaptionColor: Color {
        switch balance?.state {
        case .debt: Theme.debt
        case .credit: Theme.credit
        default: Theme.gold
        }
    }

    private var circularCaption: String {
        switch balance?.state {
        case .debt: "mi owed"
        case .credit: "banked"
        default: "clean"
        }
    }

    private var standing: String {
        guard let balance else { return "Open the app" }
        switch balance.state {
        case .debt: return "\(Format.miles(balance.debtMiles)) owed"
        case .credit: return "\(Format.beersLabel(balance.creditBeers)) banked"
        case .even: return "Books are clean"
        }
    }

    private var runLine: String {
        guard let report = entry.report else { return "" }
        let miles = report.milesRun(inWeekOf: entry.date)
        return "\(Format.miles(miles)) \(report.balance.state == .debt ? "paid" : "run") this week"
    }
}
