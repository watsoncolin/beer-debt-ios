import SwiftUI

/// The product (spec §10). The balance dominates; one big + Beer button; one
/// line of running context; one line of copy. Nothing else.
struct HomeView: View {
    @Environment(LedgerStore.self) private var store
    @State private var addedBeer: BeerEntry?

    var body: some View {
        // Re-render each minute so an interest posting shows up while the app is open.
        // The schedule only ticks; the report is dated from the clock, not from the
        // tick. A beer added between ticks is timestamped after the last tick and the
        // replay would leave it out until the next one.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = max(context.date, .now)
            content(report: store.report(at: now), now: now)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.cream)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $addedBeer) { beer in
            BeerAddedSheet(beerID: beer.id)
        }
        .sensoryFeedback(.success, trigger: addedBeer)
        .onAppear {
            #if DEBUG
            if DebugLaunch.screen == "beerAdded" { addedBeer = store.ledger.beers.last }
            #endif
        }
    }

    private func content(report: Report, now: Date) -> some View {
        let balance = report.balance
        return ZStack {
            Backdrop()

            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Beer Debt")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text("Drink now. Run later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.7))
                }

                Spacer(minLength: 0)

                NavigationLink(value: Route.debt) {
                    VStack(spacing: 14) {
                        BalanceHero(report: report)
                        Text("Your tab ›")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.gold.opacity(0.9))
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                NavigationLink(value: Route.streak) {
                    StreakCard(streak: report.streak, balance: balance.state)
                }
                .buttonStyle(.plain)

                Button {
                    addedBeer = store.addBeer()
                } label: {
                    Label("+ Beer", systemImage: "mug.fill")
                }
                .buttonStyle(GoldButtonStyle())

                NavigationLink(value: Route.runs) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.miles(report.milesRun(inWeekOf: now)))
                                .font(.headline)
                            Text(balance.state == .debt ? "paid this week" : "run this week")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(Theme.cream)
                    .padding(16)
                    .background(Theme.forestDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                }

                Text(quip(for: balance))
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func quip(for balance: Balance) -> String {
        switch balance.state {
        case .debt:
            balance.interestMiles > 0.05
                ? "Your tab is getting expensive."
                : "Your drinking is currently outpacing your running."
        case .credit:
            balance.creditBeers >= 2 ? "You've earned a couple." : "You've earned one."
        case .even:
            "Every beer has a price. Yours is measured in miles."
        }
    }
}

/// The number that dominates the screen, per state (spec §10, §19).
private struct BalanceHero: View {
    let report: Report

    private var balance: Balance { report.balance }

    var body: some View {
        switch balance.state {
        case .debt:
            VStack(spacing: 0) {
                bigNumber(Format.number(balance.debtMiles))
                Text("mi owed")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.85))
                HStack(spacing: 0) {
                    stat(Format.number(balance.principalMiles), "principal")
                    Rectangle()
                        .fill(Theme.cream.opacity(0.25))
                        .frame(width: 1, height: 36)
                    InterestRateStat(report: report)
                }
                .padding(.top, 20)
            }
        case .credit:
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("🍺").font(.system(size: 64))
                    bigNumber(Format.beers(balance.creditBeers))
                }
                Text(balance.creditBeers < 1.05 ? "beer banked" : "beers banked")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.85))
                Text("Credit slowly expires.")
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.55))
                    .padding(.top, 12)
            }
        case .even:
            VStack(spacing: 8) {
                bigNumber("0")
                Text("BOOKS ARE CLEAN")
                    .font(.headline.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    private func bigNumber(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 108, weight: .black, design: .rounded))
            .foregroundStyle(Theme.cream)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(LedgerStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID())")))
}
