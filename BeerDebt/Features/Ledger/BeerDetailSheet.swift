import SwiftUI

/// One beer's full statement (spec §12): principal, interest, repaid, age,
/// status. The date is editable so a forgotten beer can be dated back.
struct BeerDetailSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let beerID: UUID
    @State private var date = Date.now
    @State private var loaded = false

    var body: some View {
        let now = Date.now
        let report = store.report(at: now)
        let statement = report.statement(for: beerID)
        let entry = store.beer(id: beerID)

        NavigationStack {
            List {
                if let statement, let entry {
                    Section {
                        DatePicker(
                            "Added",
                            selection: $date,
                            in: store.ledger.booksOpenedAt...now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if entry.isBackdated, let recordedAt = entry.recordedAt {
                            LabeledContent("Logged", value: Format.dateTime(recordedAt))
                        }
                    } footer: {
                        Text("Forgot one? Change the date and the books are redone as if it had been logged then.")
                    }

                    Section {
                        LabeledContent("Cost", value: Format.miles(statement.costMiles, decimals: 2))
                        if statement.coveredByCreditMiles > BalanceEngine.epsilon {
                            LabeledContent("Paid from credit", value: Format.miles(statement.coveredByCreditMiles, decimals: 2))
                        }
                        LabeledContent("Principal", value: Format.miles(statement.principalMiles, decimals: 2))
                        LabeledContent("Interest accrued", value: Format.miles(statement.interestAccruedMiles, decimals: 2))
                        LabeledContent("Repaid by running", value: Format.miles(statement.paidMiles, decimals: 2))
                        if statement.writtenOffMiles > BalanceEngine.epsilon {
                            LabeledContent("Written off", value: Format.miles(statement.writtenOffMiles, decimals: 2))
                        }
                        LabeledContent("Outstanding") {
                            Text(Format.miles(statement.outstandingMiles, decimals: 2))
                                .fontWeight(.semibold)
                                .foregroundStyle(statement.isPaid ? Color.secondary : Theme.debt)
                        }
                    }

                    Section {
                        LabeledContent("Status", value: statement.isPaid ? "Paid" : "Unpaid")
                        if let paidAt = statement.paidAt {
                            LabeledContent("Paid", value: Format.dateTime(paidAt))
                        } else {
                            LabeledContent("Age", value: Format.age(from: statement.createdAt, to: now))
                            if let next = statement.nextInterestAt {
                                LabeledContent("Next interest", value: Format.relative(next, now: now))
                            } else {
                                LabeledContent("Interest", value: "Off")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("That beer isn't on the books", systemImage: "mug")
                }
            }
            .navigationTitle(statement.map { "Beer #\($0.number)" } ?? "Beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
}
