import Foundation
import Testing
@testable import BeerDebt

/// The notification copy is a pure function of what a sync changed.
struct RunNotifierTests {
    private func balance(_ state: BalanceState, debt: Double = 0, credit: Double = 0) -> Balance {
        Balance(state: state, debtMiles: debt, principalMiles: debt, interestMiles: 0, creditMiles: credit, creditBeers: credit)
    }

    @Test func runThatPaysSomeBeersButNotAll() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(3.2, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 4.5), after: balance(.debt, debt: 1.3), beersPaidOff: 2))
        #expect(m == .init(title: "Run logged: 3.2 mi", body: "Paid off 2 beers. 1.3 mi still owed."))
    }

    @Test func runThatOnlyChipsAwayAtOneBeer() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(0.6, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1.9), after: balance(.debt, debt: 1.3), beersPaidOff: 0))
        #expect(m?.body == "Knocked 0.6 mi off your tab. 1.3 mi still owed.")
    }

    @Test func runThatClearsTheTabAndBanksSome() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(3, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1.6), after: balance(.credit, credit: 1.4), beersPaidOff: 2))
        #expect(m?.body == "Tab paid, and 1.4 beers banked. Cheers.")
    }

    @Test func runThatClearsTheTabExactly() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(1, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1), after: balance(.even), beersPaidOff: 1))
        #expect(m?.body == "Tab paid. Books are clean.")
    }

    @Test func runWithNothingOwedBanksBeers() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(2, endedAt: t0)], removedRuns: 0,
            before: balance(.even), after: balance(.credit, credit: 2), beersPaidOff: 0))
        #expect(m?.body == "2 beers banked for later.")
    }

    @Test func runWhenAlreadyMaxedOut() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(5, endedAt: t0)], removedRuns: 0,
            before: balance(.credit, credit: 3), after: balance(.credit, credit: 3), beersPaidOff: 0))
        #expect(m?.body == "You're maxed out at 3 beers banked. Time to drink one.")
    }

    @Test func deletedWorkoutPutsTheBeerBack() {
        let m = RunNotifier.message(for: .init(addedRuns: [], removedRuns: 1,
            before: balance(.even), after: balance(.debt, debt: 2.3), beersPaidOff: 0))
        #expect(m == .init(title: "A run was removed from Health", body: "You're at 2.3 mi owed."))
    }

    @Test func nothingChangedMeansNoNotification() {
        let m = RunNotifier.message(for: .init(addedRuns: [], removedRuns: 0,
            before: balance(.even), after: balance(.even), beersPaidOff: 0))
        #expect(m == nil)
    }
}
