import SwiftUI

/// The Home card (spec §25): prominent, but second to the balance. Three
/// looks: no streak (quiet, dashed), day one (lit, nothing earned yet), and an
/// earned streak.
struct StreakCard: View {
    let streak: StreakStatus
    let balance: BalanceState

    private var lit: Bool { streak.currentStreakDays >= 1 }
    private var earned: Bool { streak.interestProtectionActive }

    var body: some View {
        HStack(spacing: 14) {
            StreakFlame(lit: lit, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(StreakCopy.title(streak))
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(StreakCopy.subtitle(streak, balance: balance))
                    .font(.caption)
                    .foregroundStyle(earned && streak.todayProtected ? Theme.gold : Theme.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        .padding(16)
        .background(Theme.forestDeep.opacity(lit ? 0.85 : 0.6), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            if !lit {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.cream.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
        }
        .multilineTextAlignment(.leading)
    }
}
