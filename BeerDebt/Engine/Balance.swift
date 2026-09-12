import Foundation

enum BalanceState: Sendable {
    case credit
    case even
    case debt
}

/// The headline numbers for one instant (spec §17). All miles.
struct Balance: Equatable, Sendable {
    var state: BalanceState
    /// principal + interest still owed
    var debtMiles: Double
    var principalMiles: Double
    var interestMiles: Double
    /// banked credit, after decay
    var creditMiles: Double
    /// creditMiles expressed in beers at the current miles-per-beer rule
    var creditBeers: Double

    static let even = Balance(
        state: .even, debtMiles: 0, principalMiles: 0, interestMiles: 0, creditMiles: 0, creditBeers: 0
    )
}

/// One beer's line on the books.
struct BeerStatement: Identifiable, Equatable, Sendable {
    let id: UUID
    /// 1-based, in order of consumption: "Beer #42".
    let number: Int
    let createdAt: Date
    /// What the beer cost at the time (miles per beer then).
    let costMiles: Double
    /// Portion of the cost paid from banked credit the moment it was added.
    let coveredByCreditMiles: Double
    /// The debt it opened: cost minus credit cover.
    let principalMiles: Double
    let interestAccruedMiles: Double
    let paidMiles: Double
    let principalRemainingMiles: Double
    let interestRemainingMiles: Double
    /// Remnant under `BalanceEngine.writeOffThresholdMiles` forgiven at settlement.
    let writtenOffMiles: Double
    let paidAt: Date?
    /// When interest next posts, if still outstanding and interest is on.
    let nextInterestAt: Date?

    var outstandingMiles: Double { principalRemainingMiles + interestRemainingMiles }
    var isPaid: Bool { paidAt != nil }
    /// Settled the moment it was added, out of banked credit.
    var settledByCredit: Bool { paidAt == createdAt && coveredByCreditMiles > 0 }
}

/// One run's line on the books.
struct RunStatement: Identifiable, Equatable, Sendable {
    let run: RunEntry
    let debtPaidMiles: Double
    let creditEarnedMiles: Double
    /// Miles beyond the credit cap. Gone, by design (spec §8).
    let discardedMiles: Double
    /// Ended before the books were opened; contributes nothing.
    let ignored: Bool
    /// Which day of a two-or-more-day streak this run's day was; nil for a
    /// short day or a lone mile (see `StreakStatus.streakDayNumber`).
    let streakDayNumber: Int?

    var id: UUID { run.id }
}

/// Everything the UI needs for one instant.
struct Report: Equatable, Sendable {
    let at: Date
    let balance: Balance
    /// Chronological, oldest first.
    let beers: [BeerStatement]
    /// Chronological by end time, oldest first.
    let runs: [RunStatement]
    /// Rules in force at `at`.
    let rules: Rules
    /// Earliest upcoming interest posting across open debts.
    let nextInterestAt: Date?
    /// Credit that will decay away over the next week at the current rate.
    let creditExpiringThisWeekMiles: Double
    /// The running streak as of `at` (spec §25).
    let streak: StreakStatus

    func statement(for beerID: UUID) -> BeerStatement? {
        beers.first { $0.id == beerID }
    }
}
