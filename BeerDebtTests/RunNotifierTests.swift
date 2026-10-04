import Foundation
import Testing
@testable import BeerDebt

/// The notification copy is a pure function of what a sync changed.
struct RunNotifierTests {
    private func balance(_ state: BalanceState, debt: Double = 0, credit: Double = 0) -> Balance {
        Balance(state: state, debtMiles: debt, principalMiles: debt, interestMiles: 0,
                interestPerPeriodMiles: debt * Rules.default.interestRate, creditMiles: credit, creditBeers: credit)
    }

    @Test func runThatPaysSomeBeersButNotAll() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(3.2, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 4.5), after: balance(.debt, debt: 1.3), debtPaidMiles: 3.2, beersPaidOff: 2))
        #expect(m == .init(title: "Run logged: 3.2 mi", body: "Paid off 2 beers. 1.3 mi still owed."))
    }

    @Test func runThatOnlyChipsAwayAtOneBeer() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(0.6, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1.9), after: balance(.debt, debt: 1.3), debtPaidMiles: 0.6, beersPaidOff: 0))
        #expect(m?.body == "Knocked 0.6 mi off your tab. 1.3 mi still owed.")
    }

    @Test func runThatClearsTheTabAndBanksSome() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(3, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1.6), after: balance(.credit, credit: 1.4), debtPaidMiles: 1.6, beersPaidOff: 2))
        #expect(m?.body == "Tab paid, and 1.4 beers banked. Cheers.")
    }

    @Test func runThatClearsTheTabExactly() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(1, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 1), after: balance(.even), debtPaidMiles: 1, beersPaidOff: 1))
        #expect(m?.body == "Tab paid. Books are clean.")
    }

    @Test func runWithNothingOwedBanksBeers() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(2, endedAt: t0)], removedRuns: 0,
            before: balance(.even), after: balance(.credit, credit: 2), debtPaidMiles: 0, beersPaidOff: 0))
        #expect(m?.body == "2 beers banked for later.")
    }

    @Test func runWhenAlreadyMaxedOut() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(5, endedAt: t0)], removedRuns: 0,
            before: balance(.credit, credit: 3), after: balance(.credit, credit: 3), debtPaidMiles: 0, beersPaidOff: 0))
        #expect(m?.body == "You're maxed out at 3 beers banked. Time to drink one.")
    }

    @Test func deletedWorkoutPutsTheBeerBack() {
        let m = RunNotifier.message(for: .init(addedRuns: [], removedRuns: 1,
            before: balance(.even), after: balance(.debt, debt: 2.3), debtPaidMiles: 0, beersPaidOff: 0))
        #expect(m == .init(title: "A run was removed from Health", body: "You're at 2.3 mi owed."))
    }

    @Test func nothingChangedMeansNoNotification() {
        let m = RunNotifier.message(for: .init(addedRuns: [], removedRuns: 0,
            before: balance(.even), after: balance(.even), debtPaidMiles: 0, beersPaidOff: 0))
        #expect(m == nil)
    }

    // MARK: Streaks (spec §25)

    @Test func dayTwoActivationGetsItsOwnTitle() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(1.2, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 3), after: balance(.debt, debt: 1.8), debtPaidMiles: 1.2, beersPaidOff: 1,
            streakDays: 2, streakDay: true, streakActivated: true))
        #expect(m?.title == "2 day streak: 0% APR, earned")
        #expect(m?.body == "Run logged: 1.2 mi. Paid off 1 beer. 1.8 mi still owed. Your debt interest is now paused.")
    }

    @Test func aStreakDayAddsOneLine() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(1.5, endedAt: t0)], removedRuns: 0,
            before: balance(.even), after: balance(.credit, credit: 1.5), debtPaidMiles: 0, beersPaidOff: 0,
            streakDays: 5, streakDay: true))
        #expect(m == .init(title: "Run logged: 1.5 mi", body: "1.5 beers banked for later. 🔥 5 day streak, interest paused."))
    }

    @Test func dayOneNudgesTowardTomorrow() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(1.0, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 2), after: balance(.debt, debt: 1), debtPaidMiles: 1, beersPaidOff: 1,
            streakDays: 1, streakDay: true))
        #expect(m?.body.hasSuffix("🔥 Day one of a streak. Run 1+ mile tomorrow to pause interest.") == true)
    }

    /// A run that carries the streak to two days makes today interest-protected,
    /// so the replay drops today's postings the earlier report had already
    /// made. The balance then falls by far more than was run, and the
    /// notification used to hand the whole drop to the run.
    @Test func aStreakDayReportsTheRunNotTheInterestItPaused() {
        let m = RunNotifier.message(for: .init(
            addedRuns: [run(1.4, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 34.35), after: balance(.debt, debt: 29.83),
            debtPaidMiles: 1.4, beersPaidOff: 0,
            streakDays: 3, streakDay: true))
        // 4.52 mi came off the tab; only 1.4 of it was the run.
        #expect(m?.body == "Knocked 1.4 mi off your tab. 29.8 mi still owed. 🔥 3 day streak, interest paused.")
    }

    /// The engine behaviour that makes the balance delta unusable, pinned here
    /// so a change to it is noticed: protection is derived at replay time, so
    /// the run that earns it retroactively removes today's postings the earlier
    /// report had already made.
    @Test func theBalanceDropExceedsWhatTheRunPaidOnADayTheStreakProtects() {
        let midnight = utc.startOfDay(for: t0)
        func d(_ days: Int, _ hour: Double) -> Date {
            utc.date(byAdding: .day, value: days, to: midnight)!.addingTimeInterval(hour * 3_600)
        }
        // A tab of evening beers, so their daily postings land at 21:00 — today's
        // included — and a streak alive through the two days before today.
        var books = ledger(openedAt: d(-40, 0))
        books.beers = (1...14).map { beer(d(-$0 - 3, 21)) }
        books.runs = [run(1.2, endedAt: d(-2, 7)), run(1.3, endedAt: d(-1, 7))]

        let now = d(0, 22)                              // after today's postings
        let before = report(books, at: now)
        #expect(before.streak.currentStreakDays == 2)
        #expect(!before.streak.todayProtected)

        var withRun = books
        let todays = run(1.4, endedAt: d(0, 7))
        withRun.runs.append(todays)
        let after = report(withRun, at: now)
        #expect(after.streak.currentStreakDays == 3)
        #expect(after.streak.todayProtected)

        let paid = after.runs.first { $0.run.id == todays.id }?.debtPaidMiles ?? 0
        let drop = before.balance.debtMiles - after.balance.debtMiles
        #expect(close(paid, 1.4))
        // The tab fell by well over the 1.4 that was run: the rest is today's
        // interest, un-posted. Reporting `drop` as the run's doing overstated
        // it by more than the run itself.
        #expect(drop > paid + 1.0)
    }

    @Test func aShortRunSaysNothingAboutStreaks() {
        let m = RunNotifier.message(for: .init(addedRuns: [run(0.5, endedAt: t0)], removedRuns: 0,
            before: balance(.debt, debt: 2), after: balance(.debt, debt: 1.5), debtPaidMiles: 0.5, beersPaidOff: 0,
            streakDays: 3, streakDay: false))
        #expect(m?.body == "Knocked 0.5 mi off your tab. 1.5 mi still owed.")
    }
}
