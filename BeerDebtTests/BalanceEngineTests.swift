import Foundation
import Testing
@testable import BeerDebt

/// Engine tests (spec §17). Every case uses fixed instants, never `Date.now`,
/// so results are reproducible and can be mirrored as fixtures for Android.
struct BalanceEngineTests {

    // MARK: Basics

    @Test func freshLedgerIsEven() {
        #expect(report(ledger(), at: at(hour)).balance == .even)
    }

    @Test func oneBeerIsOneMileOfDebt() {
        let r = report(ledger(beers: [beer(t0)]), at: at(hour))
        #expect(r.balance.state == .debt)
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(close(r.balance.principalMiles, 1.0))
        #expect(close(r.balance.interestMiles, 0))
    }

    @Test func beersAddUpAndAreNumberedInOrder() {
        let r = report(ledger(beers: [beer(at(2 * hour)), beer(t0), beer(at(hour))]), at: at(3 * hour))
        #expect(close(r.balance.debtMiles, 3.0))
        #expect(r.beers.map(\.number) == [1, 2, 3])
        #expect(r.beers.map(\.createdAt) == [t0, at(hour), at(2 * hour)])
    }

    @Test func milesPerBeerSetsThePrincipal() {
        var rules = Rules.default
        rules.milesPerBeer = 2
        let r = report(ledger(rules: rules, beers: [beer(t0)]), at: at(hour))
        #expect(close(r.balance.debtMiles, 2.0))
    }

    @Test func eventsAfterNowDoNotExistYet() {
        let r = report(ledger(beers: [beer(at(day))]), at: t0)
        #expect(r.balance == .even)
        #expect(r.beers.isEmpty)
    }

    // MARK: Interest

    @Test func noInterestDuringGrace() {
        let r = report(ledger(beers: [beer(t0)]), at: at(day - 1))
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(r.nextInterestAt == at(day))
    }

    @Test func interestPostsDailyAfterGrace() {
        let l = ledger(beers: [beer(t0)])
        #expect(close(report(l, at: at(day)).balance.debtMiles, 1.10))
        #expect(close(report(l, at: at(2 * day)).balance.debtMiles, 1.21))
        let fiveDays = report(l, at: at(5 * day))
        #expect(close(fiveDays.balance.debtMiles, pow(1.1, 5)))
        #expect(close(fiveDays.balance.principalMiles, 1.0))
        #expect(close(fiveDays.balance.interestMiles, pow(1.1, 5) - 1))
        #expect(fiveDays.nextInterestAt == at(6 * day))
    }

    @Test func weeklyPeriodWaitsAFullWeek() {
        var rules = Rules.default
        rules.interestPeriod = .weekly
        let l = ledger(rules: rules, beers: [beer(t0)])
        #expect(close(report(l, at: at(6 * day)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: at(week)).balance.debtMiles, 1.10))
    }

    @Test func noGraceStillWaitsOnePeriod() {
        var rules = Rules.default
        rules.gracePeriod = 0
        let l = ledger(rules: rules, beers: [beer(t0)])
        #expect(close(report(l, at: at(hour)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: at(day)).balance.debtMiles, 1.10))
    }

    @Test func longGraceDelaysTheFirstPosting() {
        var rules = Rules.default
        rules.gracePeriod = 7 * day
        let l = ledger(rules: rules, beers: [beer(t0)])
        #expect(close(report(l, at: at(6 * day)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: at(7 * day)).balance.debtMiles, 1.10))
        #expect(close(report(l, at: at(8 * day)).balance.debtMiles, 1.21))
    }

    @Test func interestOffMeansNoGrowth() {
        var rules = Rules.default
        rules.interestRate = 0
        let r = report(ledger(rules: rules, beers: [beer(t0)]), at: at(30 * day))
        #expect(close(r.balance.debtMiles, 1.0))
        #expect(r.nextInterestAt == nil)
    }

    @Test func interestOnlyAccruesOnUnpaidDebt() {
        let l = ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(hour))])
        let r = report(l, at: at(10 * day))
        #expect(r.balance == .even)
        #expect(close(r.beers[0].interestAccruedMiles, 0))
    }

    // MARK: Repayment

    @Test func runPaysDebt() {
        let r = report(ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(2 * hour))]), at: at(3 * hour))
        #expect(r.balance.state == .even)
        #expect(r.beers[0].isPaid)
        #expect(r.beers[0].paidAt == at(2 * hour))
        #expect(close(r.runs[0].debtPaidMiles, 1.0))
    }

    @Test func partialRepayment() {
        let r = report(ledger(beers: [beer(t0)], runs: [run(0.4, endedAt: at(2 * hour))]), at: at(3 * hour))
        #expect(close(r.balance.debtMiles, 0.6))
        #expect(!r.beers[0].isPaid)
        #expect(close(r.beers[0].paidMiles, 0.4))
    }

    @Test func oldestBeerIsPaidFirst() {
        let l = ledger(
            beers: [beer(at(2 * hour)), beer(t0), beer(at(hour))],
            runs: [run(1.5, endedAt: at(3 * hour))]
        )
        let r = report(l, at: at(4 * hour))
        #expect(r.beers[0].isPaid)
        #expect(close(r.beers[1].outstandingMiles, 0.5))
        #expect(close(r.beers[2].outstandingMiles, 1.0))
        #expect(close(r.balance.debtMiles, 1.5))
    }

    @Test func repaymentClearsInterestBeforePrincipal() {
        // 1.10 owed after one posting; pay 0.5.
        let l = ledger(beers: [beer(t0)], runs: [run(0.5, endedAt: at(day + hour))])
        let s = report(l, at: at(day + 2 * hour)).beers[0]
        #expect(close(s.outstandingMiles, 0.6))
        #expect(close(s.interestRemainingMiles, 0))
        #expect(close(s.principalRemainingMiles, 0.6))
        #expect(close(s.interestAccruedMiles, 0.1))
    }

    @Test func interestCompoundsOnTheReducedBalanceAfterRepayment() {
        let l = ledger(beers: [beer(t0)], runs: [run(0.5, endedAt: at(day + hour))])
        #expect(close(report(l, at: at(2 * day)).balance.debtMiles, 0.66))
    }

    // MARK: Credit

    @Test func excessRunBecomesCredit() {
        let l = ledger(rules: noDecay, beers: [beer(t0)], runs: [run(3, endedAt: at(hour))])
        let r = report(l, at: at(2 * hour))
        #expect(r.balance.state == .credit)
        #expect(close(r.balance.creditMiles, 2.0))
        #expect(close(r.balance.creditBeers, 2.0))
        #expect(close(r.runs[0].debtPaidMiles, 1.0))
        #expect(close(r.runs[0].creditEarnedMiles, 2.0))
    }

    @Test func creditIsCapped() {
        let r = report(ledger(rules: noDecay, runs: [run(5, endedAt: t0)]), at: at(hour))
        #expect(close(r.balance.creditBeers, 3.0))
        #expect(close(r.runs[0].creditEarnedMiles, 3.0))
        #expect(close(r.runs[0].discardedMiles, 2.0))
    }

    @Test func creditCapIsInBeersAtCurrentMilesPerBeer() {
        var rules = noDecay
        rules.milesPerBeer = 2
        let r = report(ledger(rules: rules, runs: [run(10, endedAt: t0)]), at: at(hour))
        #expect(close(r.balance.creditMiles, 6.0))
        #expect(close(r.balance.creditBeers, 3.0))
    }

    @Test func creditDecaysTenPercentAWeek() {
        let l = ledger(runs: [run(2, endedAt: t0)])
        #expect(close(report(l, at: at(week)).balance.creditMiles, 1.8))
        #expect(close(report(l, at: at(2 * week)).balance.creditMiles, 1.62))
        #expect(close(report(l, at: t0).creditExpiringThisWeekMiles, 0.2))
    }

    @Test func creditDecayCanBeTurnedOff() {
        let r = report(ledger(rules: noDecay, runs: [run(2, endedAt: t0)]), at: at(10 * week))
        #expect(close(r.balance.creditMiles, 2.0))
    }

    @Test func beerSpendsCreditFirst() {
        let l = ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(2, endedAt: t0)])
        let r = report(l, at: at(2 * hour))
        #expect(r.balance.state == .credit)
        #expect(close(r.balance.creditBeers, 1.0))
        let s = r.beers[0]
        #expect(s.isPaid)
        #expect(s.settledByCredit)
        #expect(close(s.coveredByCreditMiles, 1.0))
        #expect(close(s.principalMiles, 0))
    }

    @Test func partialCreditThenDebt() {
        let l = ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(0.4, endedAt: t0)])
        let r = report(l, at: at(2 * hour))
        #expect(r.balance.state == .debt)
        #expect(close(r.balance.debtMiles, 0.6))
        #expect(close(r.balance.creditMiles, 0))
        #expect(close(r.beers[0].coveredByCreditMiles, 0.4))
        #expect(close(r.beers[0].principalMiles, 0.6))
    }

    @Test func crossingFromCreditIntoDebt() {
        let l = ledger(rules: noDecay, beers: [beer(at(hour)), beer(at(2 * hour))], runs: [run(1, endedAt: t0)])
        #expect(report(l, at: at(30 * 60)).balance.state == .credit)
        #expect(report(l, at: at(90 * 60)).balance.state == .even)
        let r = report(l, at: at(3 * hour))
        #expect(r.balance.state == .debt)
        #expect(close(r.balance.debtMiles, 1.0))
    }

    @Test func crossingFromDebtIntoCredit() {
        let l = ledger(rules: noDecay, beers: [beer(t0)], runs: [run(2, endedAt: at(hour))])
        #expect(report(l, at: at(30 * 60)).balance.state == .debt)
        let r = report(l, at: at(2 * hour))
        #expect(r.balance.state == .credit)
        #expect(close(r.balance.creditBeers, 1.0))
    }

    @Test func remnantsUnderFiveHundredthsAreWrittenOff() {
        let byRun = report(ledger(beers: [beer(t0)], runs: [run(0.97, endedAt: at(hour))]), at: at(2 * hour))
        #expect(byRun.balance == .even)
        #expect(byRun.beers[0].isPaid)
        #expect(close(byRun.beers[0].writtenOffMiles, 0.03))

        let byCredit = report(ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(0.97, endedAt: t0)]), at: at(2 * hour))
        #expect(byCredit.balance == .even)
        #expect(byCredit.beers[0].settledByCredit)
        #expect(close(byCredit.beers[0].coveredByCreditMiles, 0.97))
        #expect(close(byCredit.beers[0].writtenOffMiles, 0.03))

        // Just over the line is real debt.
        let kept = report(ledger(beers: [beer(t0)], runs: [run(0.9, endedAt: at(hour))]), at: at(2 * hour))
        #expect(kept.balance.state == .debt)
        #expect(close(kept.balance.debtMiles, 0.1))
    }

    @Test func tinyCreditReadsAsEven() {
        let r = report(ledger(rules: noDecay, runs: [run(0.04, endedAt: t0)]), at: at(hour))
        #expect(r.balance.state == .even)
    }

    // MARK: Rules changes are forward-only

    @Test func changingMilesPerBeerDoesNotRepriceOldBeers() {
        var l = ledger(beers: [beer(t0), beer(at(2 * hour))])
        l = withChange(l, at: at(hour)) { $0.milesPerBeer = 2 }
        let r = report(l, at: at(3 * hour))
        #expect(close(r.beers[0].principalMiles, 1.0))
        #expect(close(r.beers[1].principalMiles, 2.0))
        #expect(close(r.balance.debtMiles, 3.0))
    }

    @Test func turningInterestOffKeepsPastInterest() {
        var l = ledger(beers: [beer(t0)])
        l = withChange(l, at: at(2 * day + hour)) { $0.interestRate = 0 }
        #expect(close(report(l, at: at(2 * day)).balance.debtMiles, 1.21))
        #expect(close(report(l, at: at(30 * day)).balance.debtMiles, 1.21))
        #expect(report(l, at: at(30 * day)).nextInterestAt == nil)
    }

    @Test func turningInterestOnAccruesFromThen() {
        var rules = Rules.default
        rules.interestRate = 0
        var l = ledger(rules: rules, beers: [beer(t0)])
        l = withChange(l, at: at(2 * day + hour)) { $0.interestRate = 0.10 }
        #expect(close(report(l, at: at(2 * day + 2 * hour)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: at(3 * day)).balance.debtMiles, 1.10))
    }

    @Test func changingRateAppliesToFuturePostingsOnly() {
        var l = ledger(beers: [beer(t0)])
        l = withChange(l, at: at(day + hour)) { $0.interestRate = 0.20 }
        #expect(close(report(l, at: at(day + hour)).balance.debtMiles, 1.10))
        #expect(close(report(l, at: at(2 * day)).balance.debtMiles, 1.10 * 1.20))
    }

    @Test func changingPeriodReschedulesFromTheLastPosting() {
        var l = ledger(beers: [beer(t0)])
        l = withChange(l, at: at(2 * day + hour)) { $0.interestPeriod = .weekly }
        #expect(close(report(l, at: at(8 * day)).balance.debtMiles, 1.21))
        #expect(close(report(l, at: at(9 * day)).balance.debtMiles, 1.331))
    }

    @Test func shorteningGracePostsAtTheChangeNotBefore() {
        var rules = Rules.default
        rules.gracePeriod = 7 * day
        var l = ledger(rules: rules, beers: [beer(t0)])
        l = withChange(l, at: at(3 * day)) { $0.gracePeriod = day }
        #expect(close(report(l, at: at(3 * day - 1)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: at(3 * day)).balance.debtMiles, 1.10))
        #expect(close(report(l, at: at(4 * day)).balance.debtMiles, 1.21))
    }

    @Test func creditCapChangeAppliesForward() {
        var l = ledger(rules: noDecay, runs: [run(5, endedAt: t0), run(5, endedAt: at(2 * hour))])
        l = withChange(l, at: at(hour)) { $0.maximumCreditBeers = 5 }
        let r = report(l, at: at(3 * hour))
        #expect(close(r.balance.creditBeers, 5.0))
        #expect(close(r.runs[0].discardedMiles, 2.0))
        #expect(close(r.runs[1].discardedMiles, 3.0))
    }

    // MARK: HealthKit realities

    @Test func runsBeforeTheBooksOpenedAreIgnored() {
        let r = report(ledger(runs: [run(5, endedAt: at(-hour))]), at: at(hour))
        #expect(r.balance == .even)
        #expect(r.runs[0].ignored)
    }

    @Test func aBeerFromBeforeTheBooksOpenedStillCounts() {
        // Installed Saturday, owned up to Thursday's beer. It has been accruing
        // since Thursday; Sunday's run pays it and banks the rest.
        let l = ledger(rules: noDecay, beers: [beer(at(-2 * day))], runs: [run(3, endedAt: at(hour))])
        #expect(close(report(l, at: t0).balance.debtMiles, 1.21))
        let r = report(l, at: at(2 * hour))
        #expect(r.beers[0].isPaid)
        #expect(close(r.beers[0].interestAccruedMiles, 0.21))
        #expect(close(r.balance.creditMiles, 3 - 1.21))
    }

    @Test func lateImportedRunLandsAtItsOwnTime() {
        let prompt = ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(hour), importedAt: at(hour))])
        let late = ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(hour), importedAt: at(5 * day))])
        let a = report(prompt, at: at(6 * day))
        let b = report(late, at: at(6 * day))
        #expect(a.balance == b.balance)
        #expect(a.balance == .even)
    }

    @Test func aBackdatedBeerIsPaidByTheRunThatFollowedIt() {
        // Ran 2 mi on day 1 (banked it), then on day 2 remembered Saturday's beer.
        let forgotten = BeerEntry(createdAt: t0, recordedAt: at(2 * day))
        let l = ledger(rules: noDecay, beers: [forgotten], runs: [run(2, endedAt: at(day))])
        let r = report(l, at: at(2 * day))
        #expect(r.beers[0].isPaid)
        #expect(r.beers[0].paidAt == at(day))
        #expect(close(r.beers[0].interestAccruedMiles, 0.1))
        #expect(r.balance.state == .credit)
        #expect(close(r.balance.creditBeers, 0.9))
    }

    @Test func replayIsDeterministicRegardlessOfArrayOrder() {
        let beers = [beer(t0), beer(at(hour)), beer(at(2 * hour))]
        let runs = [run(1.5, endedAt: at(3 * hour)), run(2, endedAt: at(2 * day))]
        let a = report(ledger(beers: beers, runs: runs), at: at(3 * day))
        let b = report(ledger(beers: beers.reversed(), runs: runs.reversed()), at: at(3 * day))
        #expect(a == b)
    }

    @Test func aDayIsAlwaysEightySixThousandFourHundredSeconds() {
        // Oct 31 → Nov 1 2026 spans the US DST change. Periods are fixed
        // lengths, so the posting lands exactly 86,400 s later, not at "the
        // same wall-clock time tomorrow".
        let halloween = at(49 * day)
        let l = ledger(openedAt: halloween, beers: [beer(halloween)])
        #expect(close(report(l, at: halloween.addingTimeInterval(day - 1)).balance.debtMiles, 1.0))
        #expect(close(report(l, at: halloween.addingTimeInterval(day)).balance.debtMiles, 1.10))
    }
}
