import SwiftUI

/// What the tab costs to leave alone: the interest one compounding period adds
/// at the rate in force. Home leads with this instead of interest-to-date,
/// which is a total that barely moves; the totals live on Your Debt.
///
/// It is also where the streak becomes worth something you can see. When today
/// is protected the charge is struck through and lit, so the number reads as
/// what running saved. The condition is `todayProtected`, not
/// `interestProtectionActive`: a streak alive from yesterday pauses nothing
/// until today has its mile, and showing the charge live is exactly the nudge
/// the streak card underneath then spells out.
struct InterestRateStat: View {
    let report: Report
    var alignment: Alignment = .center

    private var paused: Bool { report.streak.todayProtected }
    private var on: Bool { report.rules.interestEnabled }
    private var value: String { Format.number(report.balance.interestPerPeriodMiles, decimals: 2) }
    private var label: String { on ? report.rules.interestPeriod.perLabel : "interest off" }

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: 2) {
            HStack(spacing: 4) {
                if on, paused { StreakFlame(lit: true, size: 18) }
                Text(on ? value : "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(on && paused ? Theme.gold : Theme.cream)
                    .strikethrough(on && paused, color: Theme.gold)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        // Fills its column so a row of stats divides evenly, flame or not.
        .frame(maxWidth: .infinity, alignment: alignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard on else { return "Interest is off" }
        let amount = "\(value) miles \(label) in interest"
        return paused ? "\(amount), paused by your streak today" : amount
    }
}
