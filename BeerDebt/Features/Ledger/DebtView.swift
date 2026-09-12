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
    @State private var filter: Filter = .active
    @State private var selectedBeer: BeerStatement?
    @State private var beerToDelete: BeerStatement?

    var body: some View {
        let report = store.report()
        let active = Array(report.beers.filter { !$0.isPaid }.reversed())
        let paid = Array(report.beers.filter { $0.isPaid }.reversed())
        let shown = filter == .active ? active : paid

        List {
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
                    Text(Format.miles(statement.costMiles, decimals: 2))
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.65))
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

    private var paidCaption: String {
        if statement.settledByCredit { return "from credit" }
        if let paidAt = statement.paidAt { return "paid \(Format.day(paidAt))" }
        return ""
    }
}
