import SwiftUI

/// Shown once when a synced run clears the tab (spec §19, concept art screen 6).
struct DebtFreeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let celebration: DebtFreeCelebration

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 16) {
                Image("DebtFreeTrophy")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
                    .padding(.top, 32)

                Text("Debt Free!")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)

                Text("Nice work. Your tab is paid.")
                    .font(.title3)
                    .foregroundStyle(Theme.cream)

                HStack(spacing: 0) {
                    stat("\(celebration.totalBeers)", "total beers")
                    divider
                    stat(Format.number(celebration.milesRepaid), "miles repaid")
                    divider
                    stat(Format.beers(celebration.creditBeers), "beers banked")
                }
                .padding(.top, 24)

                Spacer()

                Button("Cheers!") { dismiss() }
                    .buttonStyle(GoldButtonStyle())
            }
            .padding(24)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.cream.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DebtFreeSheet(celebration: DebtFreeCelebration(totalBeers: 137, milesRepaid: 149.3, creditBeers: 1.5))
}
