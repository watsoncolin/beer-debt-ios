import Foundation
import Testing
@testable import BeerDebt

/// The bands behind the paid list's colour. Pure, and mirrored in the Kotlin
/// `PaidSeverity`, so the two platforms cannot drift apart silently.
struct PaidSeverityTests {
    @Test func aBeerThatCostAboutAMileIsOrdinary() {
        #expect(Format.PaidSeverity(milesRun: 0) == .ordinary)
        #expect(Format.PaidSeverity(milesRun: 1.0) == .ordinary)
        #expect(Format.PaidSeverity(milesRun: 1.99) == .ordinary)
    }

    @Test func twoMilesIsDearAndThreeGotAway() {
        // The boundaries belong to the harsher band, so "over 2" reads as
        // dear from 2.00 exactly.
        #expect(Format.PaidSeverity(milesRun: 2.0) == .dear)
        #expect(Format.PaidSeverity(milesRun: 2.99) == .dear)
        #expect(Format.PaidSeverity(milesRun: 3.0) == .steep)
        #expect(Format.PaidSeverity(milesRun: 12.4) == .steep)
    }

    @Test func theBandsAreTheOnesTheSpecNames() {
        #expect(Format.PaidSeverity.dearMiles == 2.0)
        #expect(Format.PaidSeverity.steepMiles == 3.0)
    }
}

/// The figure the paid list shows. `costMiles` is the price at the bar and is
/// always 1.00; what the reader wants is the run it actually took.
@MainActor
struct PaidMilesTests {
    @Test func aBeerLeftToAccrueCostsMoreRunningThanItsPrice() {
        // One beer, left ten days past the grace period at 10% a day, then run
        // off in one go.
        let l = ledger(beers: [beer(t0)], runs: [run(6.0, endedAt: at(11 * day))])
        let paid = report(l, at: at(12 * day)).beers[0]
        #expect(paid.isPaid)
        #expect(paid.costMiles == 1.0, "the price at the bar never changes")
        #expect(paid.paidMiles > 2.0, "but it took more than two miles to clear")
        // And that is what decides the colour.
        #expect(Format.PaidSeverity(milesRun: paid.paidMiles) != .ordinary)
    }

    @Test func aBeerRunOffSameDayCostsItsPrice() {
        let l = ledger(beers: [beer(t0)], runs: [run(1.0, endedAt: at(hour))])
        let paid = report(l, at: at(2 * hour)).beers[0]
        #expect(paid.isPaid)
        #expect(close(paid.paidMiles, 1.0))
        #expect(Format.PaidSeverity(milesRun: paid.paidMiles) == .ordinary)
    }

    @Test func aBeerSettledFromCreditTookNoRunningAtAll() {
        // Run first, bank the credit, then the beer is covered on arrival.
        let l = ledger(beers: [beer(at(2 * hour))], runs: [run(2.0, endedAt: at(hour))])
        let paid = report(l, at: at(3 * hour)).beers[0]
        #expect(paid.settledByCredit)
        // Honest: no run went into it. The row says "from credit" beside it.
        #expect(close(paid.paidMiles, 0))
        #expect(Format.PaidSeverity(milesRun: paid.paidMiles) == .ordinary)
    }
}
