import SwiftUI

/// The one destructive act in the app (spec §26). Played as a filing, not a
/// scolding: the bank's voice stays deadpan, the warning is in the line items
/// rather than in a tone of voice, and nothing here says the user should have
/// run more.
///
/// Two phases in one sheet. The filing states exactly what goes and what
/// stays; the stamp is the payoff, so the reset has a moment of its own
/// instead of dumping the user back into Settings with a changed number.
struct BankruptcySheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The books as they stood when the sheet opened. Snapshotted so the line
    /// items hold still, including after a write that failed and left the
    /// in-memory books already empty.
    let filing: Filing
    let onWriteOff: () -> Bool

    @State private var writtenOff: Bool
    @State private var writeFailed = false

    /// `startWrittenOff` is for previews and `-debugScreen`; the app always
    /// opens on the filing.
    init(filing: Filing, startWrittenOff: Bool = false, onWriteOff: @escaping () -> Bool) {
        self.filing = filing
        self.onWriteOff = onWriteOff
        _writtenOff = State(initialValue: startWrittenOff)
    }

    /// What is about to be written off, read once when the sheet opens.
    /// `Identifiable` so Settings can present the sheet with `.sheet(item:)`.
    struct Filing: Identifiable, Equatable {
        var id = UUID()
        var beers: Int
        var outstandingMiles: Double
        var runs: Int
        var creditMiles: Double
        var streakDays: Int
    }

    var body: some View {
        ZStack {
            Backdrop()
            if writtenOff { writeOffNotice } else { filingForm }
        }
        .sensoryFeedback(.success, trigger: writtenOff)
    }

    // MARK: Before

    private var filingForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Chapter 7 · Section Beer")
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.gold.opacity(0.9))
                        .padding(.top, 28)

                    Text("Declare Bankruptcy")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)

                    Text("Wipe the tab and open fresh books. No judgment here — some tabs are better closed than run off.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    liabilities

                    VStack(alignment: .leading, spacing: 12) {
                        note(
                            "trash",
                            Theme.debt,
                            "**Gone for good:** every beer, run, streak, and freeze on the books. There's no undo."
                        )
                        note(
                            "checkmark.seal",
                            Theme.credit,
                            "**Untouched:** the rules you set, and every run in Apple Health. They simply stop counting here."
                        )
                    }
                    .padding(.horizontal, 4)

                    if writeFailed {
                        Text("Couldn't write the fresh books to this phone. Nothing is lost — try again in a moment.")
                            .font(.footnote)
                            .foregroundStyle(Theme.debt)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                Button(writeFailed ? "Try again" : "Write it all off") {
                    if onWriteOff() {
                        withAnimation(.snappy) { writtenOff = true }
                    } else {
                        writeFailed = true
                    }
                }
                .buttonStyle(DebtButtonStyle())

                Button("Never mind") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.75))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    /// The filing's line items: the actual tab, named in the app's own
    /// vocabulary. Seeing the number is most of the warning.
    private var liabilities: some View {
        VStack(spacing: 0) {
            Text("On the books")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.cream.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            lineItem("Beers", Format.beersLabel(Double(filing.beers)))
            if filing.outstandingMiles > 0 {
                lineItem("Outstanding", Format.miles(filing.outstandingMiles), color: Theme.debt)
            }
            if filing.creditMiles > 0 {
                lineItem("Banked credit", Format.miles(filing.creditMiles), color: Theme.credit)
            }
            lineItem("Runs", "\(filing.runs)")
            if filing.streakDays > 0 {
                lineItem("Streak", "\(filing.streakDays) day\(filing.streakDays == 1 ? "" : "s")", color: Theme.gold)
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private func lineItem(_ label: String, _ value: String, color: Color = Theme.cream) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.cream.opacity(0.8))
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .font(.subheadline)
        .padding(.vertical, 7)
    }

    private func note(_ symbol: String, _ color: Color, _ markdown: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(markdown)
                .font(.footnote)
                .foregroundStyle(Theme.cream.opacity(0.75))
        }
    }

    // MARK: After

    private var writeOffNotice: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("Written Off")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .textCase(.uppercase)
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.credit)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.credit, lineWidth: 4)
                )
                .rotationEffect(.degrees(-7))
                .padding(.bottom, 12)

            Text("Books are clean.")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.cream)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Theme.cream.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer()

            Button("Start fresh") { dismiss() }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(24)
    }

    private var summary: String {
        let written = filing.beers == 0
            ? "Nothing was owed"
            : "\(Format.beersLabel(Double(filing.beers))) written off"
        return "\(written). Your rules carry over untouched, and the tab starts from zero."
    }
}

extension BankruptcySheet.Filing {
    init(report: Report) {
        self.init(
            beers: report.beers.count,
            outstandingMiles: report.balance.debtMiles,
            runs: report.runs.count,
            creditMiles: report.balance.creditMiles,
            streakDays: report.streak.currentStreakDays
        )
    }
}

private let sampleFiling = BankruptcySheet.Filing(
    beers: 14, outstandingMiles: 23.7, runs: 6, creditMiles: 0, streakDays: 3
)

#Preview("Filing") {
    BankruptcySheet(filing: sampleFiling, onWriteOff: { true })
}

#Preview("Written off") {
    BankruptcySheet(filing: sampleFiling, startWrittenOff: true, onWriteOff: { true })
}
