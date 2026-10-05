import Foundation
import Testing
@testable import BeerDebt

/// How calorie mode reads on screen and in notifications (spec §28): the
/// engine hands over miles, `Units` is the only place they become calories.
struct CalorieDisplayTests {
    private let kcal = Units(payment: PaymentBasis(mode: .calories, caloriesPerMile: 100))

    @Test func milesReadAsBefore() {
        #expect(Units.miles.amount(2.34) == "2.3 mi")
        #expect(Units.miles.amount(2.346, decimals: 2) == "2.35 mi")
        #expect(Units.miles.compactAmount(12_400) == "12k mi")
    }

    @Test func caloriesAreWholeNumbersAtTheRate() {
        #expect(kcal.amount(2.345) == "235 kcal")
        // Decimals asked for in miles mean nothing in calories.
        #expect(kcal.amount(0.1, decimals: 2) == "10 kcal")
        #expect(kcal.number(12.34) == "1,234")
        #expect(Units(payment: PaymentBasis(mode: .calories, caloriesPerMile: 120)).amount(1) == "120 kcal")
    }

    @Test func caloriesGoCompactAtFourFiguresNotFive() {
        #expect(kcal.compactAmount(4.5) == "450 kcal")
        #expect(kcal.compactAmount(12.4) == "1.2k kcal")
        #expect(kcal.compactAmount(1_240) == "124k kcal")
    }

    @Test func theDailyGoalIsOneMilesWorth() {
        #expect(Units.miles.dailyGoal == "Run 1+ mile")
        #expect(kcal.dailyGoal == "Burn 100+ kcal")
        #expect(StreakCopy.detail(StreakStatus.none(calendar: utc), units: kcal)
            == "Burn 100+ kcal today and tomorrow. From day two, interest on your tab pauses.")
    }

    @Test func aRideNotificationNamesTheRideInCalories() {
        let before = Balance(state: .debt, debtMiles: 3, principalMiles: 3, interestMiles: 0,
                             interestPerPeriodMiles: 0.3, creditMiles: 0, creditBeers: 0)
        let after = Balance(state: .debt, debtMiles: 1.5, principalMiles: 1.5, interestMiles: 0,
                            interestPerPeriodMiles: 0.15, creditMiles: 0, creditBeers: 0)
        let m = RunNotifier.message(for: .init(addedRuns: [ride(kcal: 150, endedAt: t0)], removedRuns: 0,
            before: before, after: after, debtPaidMiles: 1.5, beersPaidOff: 0, units: kcal))
        #expect(m == .init(title: "Ride logged: 150 kcal", body: "Knocked 150 kcal off your tab. 150 kcal still owed."))
    }

    @Test func theWeeklySummaryCountsRidesInCalorieMode() {
        let base = ledger(openedAt: at(-10 * day), runs: [run(1, endedAt: at(-3 * day)), ride(kcal: 250, endedAt: at(-2 * day))])
        #expect(WeeklySummary.message(ledger: base, at: t0, calendar: utc).body.hasPrefix("0 beers, 1.0 mi run."))
        #expect(WeeklySummary.message(ledger: inCalories(base), at: t0, calendar: utc).body.hasPrefix("0 beers, 350 kcal burned."))
    }

    @Test func aWeeksWorkoutsCountRidesOnlyInCalorieMode() {
        let base = ledger(openedAt: at(-10 * day), runs: [run(1, endedAt: at(-hour)), ride(kcal: 250, endedAt: at(-2 * hour))])
        #expect(close(report(base, at: t0).milesRun(inWeekOf: t0, calendar: utc), 1))
        #expect(close(report(inCalories(base), at: t0).milesRun(inWeekOf: t0, calendar: utc), 3.5))
    }

    @Test func mileMarkersCountWhatWorkoutsPaid() {
        let l = inCalories(ledger(openedAt: at(-10 * day), beers: [beer(at(-5 * day))],
                                  runs: [run(1, endedAt: at(-4 * day)), ride(kcal: 300, endedAt: at(-3 * day))]))
        let r = MileMarkersStats.build(ledger: l, range: .month, now: t0, calendar: utc)
        #expect(close(r.milesRun, 4))
        #expect(close(r.longestRun?.paidMiles ?? 0, 3))
    }
}
