import SwiftUI

/// When Home offers Fresh Start (spec §29). Pure: the threshold and the tiers
/// are the whole rule, and the dismissal is a preference the view owns.
enum BankruptcyOffer {
    /// Total debt, in engine miles, past which the tab can't sensibly be run
    /// off (decisions §B.11). Calorie mode changes how it reads, not where it is.
    static let thresholdMiles = 100.0

    /// UserDefaults key for the highest tier the user has said "Not now" to.
    static let dismissedTierKey = "bankruptcyOfferDismissedTier"

    /// 0 from 100 mi, 1 from 1,000, 2 from 10,000: each tier ten times the
    /// last, so a dismissed offer comes back about once a month at the default
    /// rate however large the tab has grown. `nil` under the threshold, and
    /// whenever the books aren't in debt.
    static func tier(for balance: Balance) -> Int? {
        guard balance.state == .debt, balance.debtMiles >= thresholdMiles else { return nil }
        var tier = 0
        var next = thresholdMiles * 10
        while balance.debtMiles >= next {
            tier += 1
            next *= 10
        }
        return tier
    }

    /// Shown until dismissed, and again once the tab reaches a higher tier.
    static func shows(tier: Int?, dismissedTier: Int?) -> Bool {
        guard let tier else { return false }
        guard let dismissedTier else { return true }
        return tier > dismissedTier
    }
}

/// The Home card (spec §29). Deadpan, like the filing it leads to: the amount
/// carries the point, and nothing says the user should have run more.
struct BankruptcyOfferCard: View {
    let owed: String
    let onFile: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This tab got away.")
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text("You owe \(owed). Some tabs are better closed than run off.")
                    .font(.caption)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 20) {
                Button("Fresh Start", action: onFile)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                Button("Not now", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.6))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forestDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .multilineTextAlignment(.leading)
    }
}

#Preview {
    BankruptcyOfferCard(owed: "174k mi", onFile: {}, onDismiss: {})
        .padding()
        .background(Theme.forest)
}
