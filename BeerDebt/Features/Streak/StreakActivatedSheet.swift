import SwiftUI

/// Shown once when a synced run makes it two days in a row: the moment the
/// streak earns its 0% rate (spec §25). Pairs with `DebtFreeSheet`.
struct StreakActivatedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let celebration: StreakCelebration

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 16) {
                Group {
                    if UIImage(named: "StreakActivated") != nil {
                        Image("StreakActivated").resizable().scaledToFit()
                    } else {
                        StreakFlame(lit: true, size: 150)
                    }
                }
                .frame(height: 170)
                .padding(.top, 32)

                Text("\(celebration.days) day streak")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)

                Text("0% APR — earned.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.cream)

                Text("Your debt interest is now paused. Keep running 1+ mile a day to keep it that way.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Spacer()

                Button("Cheers!") { dismiss() }
                    .buttonStyle(GoldButtonStyle())
            }
            .padding(24)
        }
    }
}

#Preview {
    StreakActivatedSheet(celebration: StreakCelebration(days: 2))
}
