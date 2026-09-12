import SwiftUI

/// One beer's full statement (spec §12): principal, interest, repaid, age, status.
struct BeerDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let statement: BeerStatement
    let now: Date

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Added", value: Format.dateTime(statement.createdAt))
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
            }
            .navigationTitle("Beer #\(statement.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
