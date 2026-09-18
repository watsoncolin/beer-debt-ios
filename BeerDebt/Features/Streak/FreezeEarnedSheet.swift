import SwiftUI

/// Shown once when a synced run is the fifth running day (spec §25.1). The
/// quietest of the three celebration sheets: it grants permission to rest, not
/// credit for running that wasn't done, so it states the fact and gets out.
struct FreezeEarnedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let celebration: FreezeEarnedCelebration

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 18) {
                Text("🧊")
                    .font(.system(size: 96))
                    .accessibilityHidden(true)

                Text(StreakCopy.freezeEarnedTitle.uppercased())
                    .font(.headline.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.frost)

                Text(StreakCopy.freezeEarnedBody())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("It keeps your \(celebration.streakDays) day streak and your 0% rate. It adds no miles and pays nothing off your tab.")
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Got it") { dismiss() }
                    .buttonStyle(GoldButtonStyle())
                    .padding(.top, 4)
            }
            .padding(28)
        }
        .presentationBackground(.clear)
    }
}
