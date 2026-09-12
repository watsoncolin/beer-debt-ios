import Foundation

/// Pure, deterministic ledger replay. No I/O, no clocks: `now` is injected.
///
/// Rebuilding from the same ledger at the same instant always yields the same
/// `Report` (acceptance criterion 16). The accounting rules are written up in
/// docs/decisions.md §B. In short:
///
/// - Events (rules changes, beers, runs) are folded in time order. Beers sit at
///   `createdAt`, runs at `endedAt`, so a late HealthKit import lands at the
///   time the run actually happened.
/// - Before each event, every open debt posts the interest steps that fell due
///   and the credit pool decays, using the rules in force during that interval.
/// - A beer spends credit first; the remainder opens a debt.
/// - A run pays the oldest debt first (interest, then principal). Leftover
///   miles become credit up to the cap; anything past the cap is discarded.
/// - Rules changes apply forward only. Past postings are never recalculated.
enum BalanceEngine {
    static let epsilon = 1e-9
    static let week: TimeInterval = 7 * 24 * 60 * 60
    /// Below this much banked credit the books read as clean.
    static let evenThresholdBeers = 0.05
    /// A remnant smaller than this (about 80 m) left after a run or a credit
    /// cover is written off rather than left to accrue interest forever.
    static let writeOffThresholdMiles = 0.05

    static func report(for ledger: Ledger, at now: Date) -> Report {
        var replay = Replay(ledger: ledger, now: now)
        return replay.run()
    }
}

// MARK: - Replay

private enum Event {
    case rules(RulesChange)
    case beer(BeerEntry)
    case run(RunEntry)

    var time: Date {
        switch self {
        case .rules(let change): change.effectiveAt
        case .beer(let beer): beer.createdAt
        case .run(let run): run.endedAt
        }
    }

    /// Same-instant ordering: rules take effect first, then beers, then runs.
    var rank: Int {
        switch self {
        case .rules: 0
        case .beer: 1
        case .run: 2
        }
    }

    var tieBreaker: String {
        switch self {
        case .rules(let change): String(change.effectiveAt.timeIntervalSince1970)
        case .beer(let beer): beer.id.uuidString
        case .run(let run): run.id.uuidString
        }
    }
}

private struct DebtAccount {
    let beerID: UUID
    let createdAt: Date
    let costMiles: Double
    let coveredByCredit: Double
    let principalOriginal: Double
    var principalRemaining: Double
    var interestRemaining: Double = 0
    var interestAccrued: Double = 0
    var paid: Double = 0
    var lastPostingAt: Date?
    var nextPostingAt: Date
    var paidAt: Date?
    var writtenOff: Double = 0

    var outstanding: Double { principalRemaining + interestRemaining }

    /// Close the account at `date`, writing off whatever is left.
    mutating func settle(at date: Date) {
        writtenOff += outstanding
        principalRemaining = 0
        interestRemaining = 0
        paidAt = date
    }
}

private struct Replay {
    let ledger: Ledger
    let now: Date
    private var rules: Rules
    /// FIFO: appended in `createdAt` order because events are replayed in order.
    private var open: [DebtAccount] = []
    private var closed: [DebtAccount] = []
    private var credit: Double = 0
    /// The instant everything has been brought forward to.
    private var clock: Date
    private var runStatements: [RunStatement] = []

    init(ledger: Ledger, now: Date) {
        self.ledger = ledger
        self.now = now
        rules = ledger.rulesHistory.first?.rules ?? .default
        clock = min(ledger.booksOpenedAt, now)
    }

    mutating func run() -> Report {
        let events = (ledger.rulesHistory.map(Event.rules)
            + ledger.beers.map(Event.beer)
            + ledger.runs.map(Event.run))
            .filter { $0.time <= now }
            .sorted { a, b in
                if a.time != b.time { return a.time < b.time }
                if a.rank != b.rank { return a.rank < b.rank }
                return a.tieBreaker < b.tieBreaker
            }

        for event in events {
            advance(to: event.time)
            switch event {
            case .rules(let change): apply(change)
            case .beer(let beer): apply(beer)
            case .run(let run): apply(run)
            }
        }
        advance(to: now)
        return summary()
    }

    /// Bring every open debt and the credit pool forward to `t`.
    private mutating func advance(to t: Date) {
        guard t >= clock else { return }
        for i in open.indices {
            while open[i].nextPostingAt <= t {
                if rules.interestEnabled {
                    let step = open[i].outstanding * rules.interestRate
                    open[i].interestRemaining += step
                    open[i].interestAccrued += step
                }
                open[i].lastPostingAt = open[i].nextPostingAt
                open[i].nextPostingAt = open[i].nextPostingAt.addingTimeInterval(rules.interestPeriod.seconds)
            }
        }
        if t > clock, credit > 0, rules.creditDecayEnabled {
            let weeks = t.timeIntervalSince(clock) / BalanceEngine.week
            credit *= pow(1 - rules.creditDecayRatePerWeek, weeks)
            if credit < BalanceEngine.epsilon { credit = 0 }
        }
        clock = t
    }

    private mutating func apply(_ change: RulesChange) {
        rules = change.rules
        // Forward only: reschedule the next posting under the new period and
        // grace, never earlier than the change itself. Past postings stand.
        for i in open.indices {
            let scheduled: Date
            if let last = open[i].lastPostingAt {
                scheduled = last.addingTimeInterval(rules.interestPeriod.seconds)
            } else {
                scheduled = open[i].createdAt.addingTimeInterval(rules.firstPostingDelay)
            }
            open[i].nextPostingAt = max(scheduled, change.effectiveAt)
        }
    }

    private mutating func apply(_ beer: BeerEntry) {
        let cost = rules.milesPerBeer
        let fromCredit = min(credit, cost)
        credit -= fromCredit
        if credit < BalanceEngine.epsilon { credit = 0 }
        let remainder = cost - fromCredit

        var account = DebtAccount(
            beerID: beer.id,
            createdAt: beer.createdAt,
            costMiles: cost,
            coveredByCredit: fromCredit,
            principalOriginal: remainder,
            principalRemaining: remainder,
            nextPostingAt: beer.createdAt.addingTimeInterval(rules.firstPostingDelay)
        )
        if remainder > BalanceEngine.writeOffThresholdMiles {
            open.append(account)
        } else {
            account.settle(at: beer.createdAt)
            closed.append(account)
        }
    }

    private mutating func apply(_ run: RunEntry) {
        guard run.endedAt >= ledger.booksOpenedAt else {
            runStatements.append(RunStatement(
                run: run, debtPaidMiles: 0, creditEarnedMiles: 0, discardedMiles: 0, ignored: true
            ))
            return
        }

        var miles = run.distanceMiles
        var debtPaid = 0.0
        var i = 0
        while miles > BalanceEngine.epsilon, i < open.count {
            let payment = min(miles, open[i].outstanding)
            let toInterest = min(payment, open[i].interestRemaining)
            open[i].interestRemaining = max(0, open[i].interestRemaining - toInterest)
            open[i].principalRemaining = max(0, open[i].principalRemaining - (payment - toInterest))
            open[i].paid += payment
            miles -= payment
            debtPaid += payment
            if open[i].outstanding <= BalanceEngine.writeOffThresholdMiles {
                var settled = open.remove(at: i)
                settled.settle(at: run.endedAt)
                closed.append(settled)
            } else {
                i += 1
            }
        }

        let leftover = max(miles, 0)
        let room = max(0, rules.creditCapMiles - credit)
        let earned = min(leftover, room)
        credit += earned
        runStatements.append(RunStatement(
            run: run,
            debtPaidMiles: debtPaid,
            creditEarnedMiles: earned,
            discardedMiles: leftover - earned,
            ignored: false
        ))
    }

    private func summary() -> Report {
        let accounts = (open + closed).sorted { a, b in
            a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.beerID.uuidString < b.beerID.uuidString
        }
        let statements = accounts.enumerated().map { index, account in
            BeerStatement(
                id: account.beerID,
                number: index + 1,
                createdAt: account.createdAt,
                costMiles: account.costMiles,
                coveredByCreditMiles: account.coveredByCredit,
                principalMiles: account.principalOriginal,
                interestAccruedMiles: account.interestAccrued,
                paidMiles: account.paid,
                principalRemainingMiles: account.principalRemaining,
                interestRemainingMiles: account.interestRemaining,
                writtenOffMiles: account.writtenOff,
                paidAt: account.paidAt,
                nextInterestAt: (account.paidAt == nil && rules.interestEnabled) ? account.nextPostingAt : nil
            )
        }

        let debt = open.reduce(0) { $0 + $1.outstanding }
        let principal = open.reduce(0) { $0 + $1.principalRemaining }
        let interest = open.reduce(0) { $0 + $1.interestRemaining }
        let creditBeers = rules.milesPerBeer > 0 ? credit / rules.milesPerBeer : 0
        let state: BalanceState
        if debt > BalanceEngine.epsilon {
            state = .debt
        } else if creditBeers >= BalanceEngine.evenThresholdBeers {
            state = .credit
        } else {
            state = .even
        }

        return Report(
            at: now,
            balance: Balance(
                state: state,
                debtMiles: debt,
                principalMiles: principal,
                interestMiles: interest,
                creditMiles: credit,
                creditBeers: creditBeers
            ),
            beers: statements,
            runs: runStatements.sorted { $0.run.endedAt < $1.run.endedAt },
            rules: rules,
            nextInterestAt: rules.interestEnabled ? open.map(\.nextPostingAt).min() : nil,
            creditExpiringThisWeekMiles: credit * rules.creditDecayRatePerWeek
        )
    }
}
