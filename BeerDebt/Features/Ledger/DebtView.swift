import SwiftUI

/// Your Debt (concept art screen 3): active beers with what they cost now,
/// paid beers below. Tap for the statement; swipe to take one off the books.
struct DebtView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case active = "Active"
        case paid = "Paid"
        var id: String { rawValue }
    }

    @Environment(LedgerStore.self) private var store
    @State private var filter: Filter = {
        #if DEBUG
        // `-debugScreen paid` opens straight onto the paid list, which is the
        // only way to screenshot it.
        if DebugLaunch.screen == "paid" { return .paid }
        #endif
        return .active
    }()
    @State private var selectedBeer: BeerStatement?
    @State private var beerToDelete: BeerStatement?

    var body: some View {
        let report = store.report()
        let active = Array(report.beers.filter { !$0.isPaid }.reversed())
        let paid = Array(report.beers.filter { $0.isPaid }.reversed())
        let shown = filter == .active ? active : paid

        List {
            Section {
                TotalsPanel(report: report)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
            }

            Section {
                Picker("Filter", selection: $filter) {
                    Text("Active (\(active.count))").tag(Filter.active)
                    Text("Paid (\(paid.count))").tag(Filter.paid)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
            }

            Section {
                if shown.isEmpty {
                    Text(filter == .active ? "Nothing owed. Books are clean." : "No beers paid off yet. Go for a run.")
                        .foregroundStyle(Theme.cream.opacity(0.7))
                        .cardRow()
                } else {
                    ForEach(shown) { statement in
                        Button { selectedBeer = statement } label: {
                            BeerCard(statement: statement, now: report.at)
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { beerToDelete = statement } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if filter == .active, !active.isEmpty {
                Label("Runs are applied to your oldest beers first.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 24, trailing: 24))
            }
        }
        .listStyle(.plain)
        .forestScreen()
        .navigationTitle("Your Debt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedBeer) { statement in
            BeerDetailSheet(beerID: statement.id)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Take this beer off the books?",
            isPresented: Binding(get: { beerToDelete != nil }, set: { if !$0 { beerToDelete = nil } }),
            titleVisibility: .visible,
            presenting: beerToDelete
        ) { statement in
            Button("Delete Beer #\(statement.number)", role: .destructive) {
                store.removeBeer(id: statement.id)
            }
        } message: { _ in
            Text("Any run that paid for it goes to your other beers or to credit instead.")
        }
        .onAppear {
            #if DEBUG
            if DebugLaunch.screen == "beerDetail" { selectedBeer = report.beers.last }
            #endif
        }
    }
}

/// The totals, in a panel over the list. They used to be the second line of
/// the Home hero; Home now leads with what a period of the tab costs, and the
/// standing figures belong here, next to the beers they came from.
private struct TotalsPanel: View {
    let report: Report

    private var balance: Balance { report.balance }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if balance.state != .even {
                Rectangle()
                    .fill(Theme.cream.opacity(0.15))
                    .frame(height: 1)
                stats
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var header: some View {
        switch balance.state {
        case .debt:
            caption("TOTAL OWED")
            bigNumber(Format.miles(balance.debtMiles, decimals: 2), color: Theme.debt)
        case .credit:
            caption("BANKED")
            bigNumber(Format.beersLabel(balance.creditBeers), color: Theme.creditSoft)
        case .even:
            caption("BOOKS ARE CLEAN")
            Text("Nothing owed, nothing banked.")
                .font(.subheadline)
                .foregroundStyle(Theme.cream.opacity(0.7))
        }
    }

    @ViewBuilder
    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            switch balance.state {
            case .debt:
                stat(Format.number(balance.principalMiles, decimals: 2), "principal")
                stat(Format.number(balance.interestMiles, decimals: 2), "interest so far")
                InterestRateStat(report: report, alignment: .leading)
            case .credit, .even:
                stat(Format.number(balance.creditMiles, decimals: 2), "miles banked")
                stat(Format.number(report.creditExpiringThisWeekMiles, decimals: 2), "expires this week")
                Spacer(minLength: 0).frame(maxWidth: .infinity)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(Theme.cream.opacity(0.6))
    }

    private func bigNumber(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BeerCard: View {
    let statement: BeerStatement
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Beer #\(statement.number)")
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(Format.dateTime(statement.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.65))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if statement.isPaid {
                    Pill(text: "PAID", color: Theme.creditSoft)
                    // What it actually took to run off, not what it cost at the
                    // bar: a beer left alone accrues interest, so 1.00 is only
                    // ever the opening price.
                    Text(Format.miles(statement.paidMiles, decimals: 2))
                        .font(ranAway ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(paidColor)
                    Text(paidCaption)
                        .font(.caption)
                        .foregroundStyle(Theme.cream.opacity(0.5))
                } else {
                    Text(Format.miles(statement.outstandingMiles, decimals: 2))
                        .font(.headline)
                        .foregroundStyle(Theme.debt)
                    Text(Format.miles(statement.principalMiles, decimals: 2))
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.65))
                    Text(Format.age(from: statement.createdAt, to: now))
                        .font(.caption)
                        .foregroundStyle(Theme.cream.opacity(0.5))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var severity: Format.PaidSeverity { .init(milesRun: statement.paidMiles) }

    private var paidColor: Color {
        switch severity {
        case .steep: Theme.debt
        case .dear: Theme.caution
        case .ordinary: Theme.cream.opacity(0.65)
        }
    }

    /// An ordinary beer stays quiet; a dear one earns some weight.
    private var ranAway: Bool { severity != .ordinary }

    private var paidCaption: String {
        if statement.settledByCredit { return "from credit" }
        if let paidAt = statement.paidAt { return "paid \(Format.day(paidAt))" }
        return ""
    }
}
