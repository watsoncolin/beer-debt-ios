import Foundation
import Testing
@testable import BeerDebt

/// When Home offers Fresh Start (spec §29, decisions §B.11).
struct BankruptcyOfferTests {
    private func owing(_ miles: Double) -> Balance {
        Balance(state: .debt, debtMiles: miles, principalMiles: min(miles, 5), interestMiles: max(miles - 5, 0),
                interestPerPeriodMiles: miles * 0.1, creditMiles: 0, creditBeers: 0)
    }

    @Test func theOfferStartsAtAHundredMiles() {
        #expect(BankruptcyOffer.thresholdMiles == 100)
        #expect(BankruptcyOffer.tier(for: owing(99.9)) == nil)
        #expect(BankruptcyOffer.tier(for: owing(100)) == 0)
    }

    @Test func eachTierIsTenTimesTheLast() {
        #expect(BankruptcyOffer.tier(for: owing(999.9)) == 0)
        #expect(BankruptcyOffer.tier(for: owing(1_000)) == 1)
        #expect(BankruptcyOffer.tier(for: owing(9_999)) == 1)
        #expect(BankruptcyOffer.tier(for: owing(10_000)) == 2)
        #expect(BankruptcyOffer.tier(for: owing(174_417.9)) == 3)
    }

    @Test func creditAndCleanBooksAreNeverOffered() {
        #expect(BankruptcyOffer.tier(for: .even) == nil)
        let credit = Balance(state: .credit, debtMiles: 0, principalMiles: 0, interestMiles: 0,
                             interestPerPeriodMiles: 0, creditMiles: 300, creditBeers: 3)
        #expect(BankruptcyOffer.tier(for: credit) == nil)
    }

    @Test func notNowHoldsUntilTheNextTier() {
        #expect(BankruptcyOffer.shows(tier: 0, dismissedTier: nil))
        #expect(!BankruptcyOffer.shows(tier: 0, dismissedTier: 0))
        #expect(BankruptcyOffer.shows(tier: 1, dismissedTier: 0))
        #expect(!BankruptcyOffer.shows(tier: 1, dismissedTier: 1))
        #expect(!BankruptcyOffer.shows(tier: nil, dismissedTier: nil))
    }

    @Test func calorieModeMovesTheWordingNotTheThreshold() {
        // Measured in engine miles: 100 mi is 10,000 kcal at the default rate.
        let l = inCalories(ledger(beers: [beer(t0)], runs: []))
        let balance = report(l, at: at(60 * day)).balance
        #expect(balance.debtMiles > 100)
        #expect(BankruptcyOffer.tier(for: balance) == BankruptcyOffer.tier(for: report(ledger(beers: [beer(t0)], runs: []), at: at(60 * day)).balance))
    }
}

/// The hero keeps the full number until six displayed figures (spec §29).
struct HeroNumberTests {
    private let kcal = Units(payment: PaymentBasis(mode: .calories, caloriesPerMile: 100))

    @Test func fiveFiguresStayInFull() {
        #expect(Units.miles.hero(12.34) == "12.3")
        #expect(Units.miles.hero(99_999.9) == "99,999.9")
        #expect(kcal.hero(970) == "97,000")
    }

    @Test func sixFiguresGoCompact() {
        #expect(Units.miles.hero(174_417.9) == "174k")
        #expect(kcal.hero(1_000) == "100k")
        #expect(kcal.hero(174_417.88) == "17M")
    }
}
