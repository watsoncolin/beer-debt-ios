import SwiftUI

/// Brief feedback after + Beer (spec §11, concept art screen 2). One tap to
/// dismiss; fast enough to do from a bar. A "change the date" link handles the
/// beer you forgot to log last night.
struct BeerAddedSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let beerID: UUID
    @State private var editingDate = false
    @State private var date = Date.now
    @State private var loaded = false

    var body: some View {
        let now = Date.now
        let entry = store.beer(id: beerID)
        let createdAt = entry?.createdAt ?? now
        let atCreation = store.report(at: createdAt)
        let current = store.report(at: now)
        let opening = atCreation.statement(for: beerID)
        let statement = current.statement(for: beerID)

        ZStack {
            Backdrop()

            ScrollView {
                VStack(spacing: 18) {
                    Text("🍺")
                        .font(.system(size: 96))
                        .padding(.top, 24)

                    Text("Beer added!")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cream)

                    if let opening, let statement, let entry {
                        headline(opening: opening, now: statement, entry: entry, balance: current.balance, rules: current.rules)
                        if !statement.isPaid {
                            projection(statement, rules: current.rules, from: now)
                        }
                    }

                    dateEditor(now: now)
                }
                .padding(24)
                .padding(.bottom, 80)
            }

            VStack {
                Spacer()
                Button("Cheers!") { dismiss() }
                    .buttonStyle(GoldButtonStyle())
                    .padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.cream.opacity(0.6))
                    .padding(16)
            }
        }
        .onAppear {
            if !loaded, let entry {
                date = entry.createdAt
                loaded = true
            }
        }
        .onChange(of: date) { _, newDate in
            if loaded { store.updateBeerDate(id: beerID, to: newDate) }
        }
    }

    @ViewBuilder
    private func headline(opening: BeerStatement, now statement: BeerStatement, entry: BeerEntry, balance: Balance, rules: Rules) -> some View {
        VStack(spacing: 6) {
            if opening.settledByCredit {
                Text("Covered by your credit.")
                    .font(.title3.weight(.semibold))
                Text("\(Format.beersLabel(balance.creditBeers)) still banked.")
                    .font(.subheadline)
                    .opacity(0.7)
            } else {
                Text("That's +\(Format.miles(opening.principalMiles))")
                    .font(.title3.weight(.semibold))
                if opening.coveredByCreditMiles > BalanceEngine.epsilon {
                    Text("\(Format.miles(opening.coveredByCreditMiles)) came out of credit.")
                        .font(.subheadline)
                        .opacity(0.7)
                } else if entry.isBackdated, statement.isPaid {
                    Text("Dated \(Format.dateTime(entry.createdAt)). Already paid off by a run.")
                        .font(.subheadline)
                        .opacity(0.7)
                } else if entry.isBackdated, statement.interestAccruedMiles > BalanceEngine.epsilon {
                    Text("Dated \(Format.dateTime(entry.createdAt)). Already \(Format.miles(statement.outstandingMiles, decimals: 2)) with interest.")
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
    private func projection(_ statement: BeerStatement, rules: Rules, from now: Date) -> some View {
        VStack(spacing: 12) {
            if rules.interestEnabled {
                Text("If you don't run it off, this beer will cost you:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(horizons(for: rules), id: \.label) { horizon in
                        let future = now.addingTimeInterval(horizon.seconds)
                        let cost = store.report(at: future).statement(for: beerID)?.outstandingMiles ?? 0
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
                    let verb = statement.interestAccruedMiles > BalanceEngine.epsilon ? "Next interest" : "Interest starts"
                    Text("\(verb) \(Format.relative(next, now: now)).")
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

    @ViewBuilder
    private func dateEditor(now: Date) -> some View {
        if editingDate {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "Logged for",
                    selection: $date,
                    in: store.earliestBeerDate(now: now)...now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .foregroundStyle(Theme.cream)
                .environment(\.colorScheme, .dark)
                Text("The books are redone as if it had been logged then.")
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.6))
            }
            .padding(18)
            .background(Theme.forestDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        } else {
            VStack(spacing: 14) {
                Button {
                    withAnimation { editingDate = true }
                } label: {
                    Label("Forgot one earlier? Change the date", systemImage: "calendar")
                }
                Button {
                    store.removeBeer(id: beerID)
                    dismiss()
                } label: {
                    Label("Didn't mean that? Remove it", systemImage: "arrow.uturn.backward")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.cream.opacity(0.75))
        }
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
