import SwiftUI

/// Brief feedback after + Beer (spec §11, concept art screen 2). One tap to
/// dismiss; fast enough to do from a bar.
struct BeerAddedSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let beer: BeerEntry

    var body: some View {
        let report = store.report(at: beer.createdAt)
        let statement = report.statement(for: beer.id)

        ZStack {
            Backdrop()

            VStack(spacing: 18) {
                Text("🍺")
                    .font(.system(size: 96))
                    .padding(.top, 24)

                Text("Beer added!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cream)

                if let statement {
                    headline(statement, balance: report.balance, rules: report.rules)
                    if !statement.isPaid {
                        projection(statement, rules: report.rules)
                    }
                }

                Spacer()

                Button("Cheers!") { dismiss() }
                    .buttonStyle(GoldButtonStyle())
            }
            .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.cream.opacity(0.6))
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private func headline(_ statement: BeerStatement, balance: Balance, rules: Rules) -> some View {
        VStack(spacing: 6) {
            if statement.settledByCredit {
                Text("Covered by your credit.")
                    .font(.title3.weight(.semibold))
                Text("\(Format.beersLabel(balance.creditBeers)) still banked.")
                    .font(.subheadline)
                    .opacity(0.7)
            } else {
                Text("That's +\(Format.miles(statement.principalMiles))")
                    .font(.title3.weight(.semibold))
                if statement.coveredByCreditMiles > BalanceEngine.epsilon {
                    Text("\(Format.miles(statement.coveredByCreditMiles)) came out of credit.")
                        .font(.subheadline)
                        .opacity(0.7)
                } else if rules.interestEnabled {
                    Text("(for now...)")
                        .font(.subheadline)
                        .opacity(0.7)
                }
            }
        }
        .foregroundStyle(Theme.cream)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func projection(_ statement: BeerStatement, rules: Rules) -> some View {
        VStack(spacing: 12) {
            if rules.interestEnabled {
                Text("If you don't run it off, this beer will cost you:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(horizons(for: rules), id: \.label) { horizon in
                        let future = beer.createdAt.addingTimeInterval(horizon.seconds)
                        let cost = store.report(at: future).statement(for: beer.id)?.outstandingMiles ?? 0
                        HStack {
                            Text(Format.miles(cost, decimals: 2))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.debt)
                            Spacer()
                            Text(horizon.label)
                                .foregroundStyle(Theme.cream.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 8)

                if let next = statement.nextInterestAt {
                    Text("Interest starts \(Format.relative(next)).")
                        .font(.footnote)
                        .foregroundStyle(Theme.cream.opacity(0.6))
                }
            } else {
                Text("No interest. You turned it off. Still owed, though.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.forestDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    }

    private struct Horizon {
        let seconds: TimeInterval
        let label: String
    }

    private func horizons(for rules: Rules) -> [Horizon] {
        let day: TimeInterval = 86_400
        switch rules.interestPeriod {
        case .daily:
            return [
                Horizon(seconds: 1 * day, label: "in 1 day"),
                Horizon(seconds: 2 * day, label: "in 2 days"),
                Horizon(seconds: 5 * day, label: "in 5 days"),
            ]
        case .weekly:
            return [
                Horizon(seconds: 7 * day, label: "in 1 week"),
                Horizon(seconds: 14 * day, label: "in 2 weeks"),
                Horizon(seconds: 28 * day, label: "in 4 weeks"),
            ]
        }
    }
}
