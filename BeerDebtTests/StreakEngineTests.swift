import Foundation
import Testing
@testable import BeerDebt

/// Running streaks (spec §24): a mile a day builds one, two days in a row
/// pauses interest, and the whole thing is derived from the runs on the books.
/// t0 is Saturday 2026-09-12 20:00 UTC; `day(n)` is 07:00 UTC on t0 + n days.
struct StreakEngineTests {
    private func streak(_ runs: [RunEntry], at now: Date) -> StreakStatus {
        StreakEngine.calculate(runs: runs, at: now, calendar: utc)
    }

    @Test func exactlyOneMileQualifiesAndJustUnderDoesNot() {
        #expect(streak([run(1.0, endedAt: morning(0))], at: t0).todayQualifies)
        // A watch that says 1.00 mi may be a few centimetres short: allowed.
        let meters = RunEntry.metersPerMile - 0.5
        let close = RunEntry(healthKitWorkoutID: UUID(), startedAt: morning(0), endedAt: morning(0), distanceMeters: meters, importedAt: t0)
        #expect(streak([close], at: t0).todayQualifies)
        #expect(!streak([run(0.999, endedAt: morning(0))], at: t0).todayQualifies)
    }

    @Test func twoRunsInOneDayAddUp() {
        let s = streak([run(0.4, endedAt: morning(0)), run(0.7, endedAt: at(-2 * hour))], at: t0)
        #expect(s.todayQualifies)
        #expect(close(s.todayMiles, 1.1))
        #expect(s.currentStreakDays == 1)
    }

    @Test func dayTwoActivatesProtection() {
        let one = streak([run(1.2, endedAt: morning(0))], at: t0)
        #expect(one.currentStreakDays == 1 && !one.interestProtectionActive && !one.todayProtected)

        let two = streak([run(1.2, endedAt: morning(0)), run(1.1, endedAt: morning(1))], at: at(day))
        #expect(two.currentStreakDays == 2 && two.interestProtectionActive && two.todayProtected)
        #expect(!two.isProtected(on: morning(0)) && two.isProtected(on: morning(1)))
    }

    @Test func aShortDayBreaksTheStreakAndTheNextMileIsDayOne() {
        // Mon 1.3, Tue 2.0, Wed 1.1, Thu 0.4, Fri 2.2 (spec §7).
        let runs = [run(1.3, endedAt: morning(0)), run(2.0, endedAt: morning(1)), run(1.1, endedAt: morning(2)),
                    run(0.4, endedAt: morning(3)), run(2.2, endedAt: morning(4))]
        let s = streak(runs, at: at(4 * day))
        #expect(s.days.map(\.streakNumber) == [1, 2, 3, 0, 1])
        #expect(s.days.map(\.interestProtected) == [false, true, true, false, false])
        #expect(s.currentStreakDays == 1)
        #expect(s.longestStreakDays == 3)
        #expect(s.totalQualifyingDays == 4)
    }

    @Test func aStreakStaysAliveUntilTodayIsOver() {
        // Ran the last three days, nothing yet today: still a 3-day streak, protection still on.
        let runs = [run(1, endedAt: morning(-3)), run(1, endedAt: morning(-2)), run(1, endedAt: morning(-1))]
        let s = streak(runs, at: t0)
        #expect(s.currentStreakDays == 3)
        #expect(s.interestProtectionActive)
        #expect(!s.todayProtected)
        // Skip today entirely and it's gone tomorrow.
        #expect(streak(runs, at: at(day)).currentStreakDays == 0)
    }

    @Test func aLateImportRebuildsTheSameStreak() {
        // Sunday morning the run isn't on the books yet; once it is, Sunday is day two.
        let saturday = run(1.5, endedAt: morning(0))
        let sunday = run(1.5, endedAt: at(day - hour), importedAt: at(day + 3 * hour))
        let before = streak([saturday], at: at(day - 2 * hour))
        #expect(before.currentStreakDays == 1)
        let after = streak([saturday, sunday], at: at(day + 4 * hour))
        #expect(after.currentStreakDays == 2 && after.isProtected(on: at(day - 2 * hour)))
    }

    @Test func daysFollowTheCalendarNotTheClock() {
        // 01:00 UTC Sunday is still Saturday evening in New York: one day there, two in UTC.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let runs = [run(1, endedAt: at(-2 * hour)), run(1, endedAt: at(5 * hour))]   // Sat 18:00 UTC, Sun 01:00 UTC
        #expect(StreakEngine.calculate(runs: runs, at: at(6 * hour), calendar: utc).currentStreakDays == 2)
        #expect(StreakEngine.calculate(runs: runs, at: at(6 * hour), calendar: newYork).currentStreakDays == 1)
    }

    @Test func noRunsMeansNoStreak() {
        let s = streak([], at: t0)
        #expect(s.days.isEmpty && s.currentStreakDays == 0 && !s.interestProtectionActive)
    }

    // MARK: Interest

    @Test func protectedDaysSkipThePostingAndNothingElseChanges() {
        // Beer Saturday night. Postings land 20:00 each day. Runs Sunday and Monday
        // mornings: Sunday is day one (posts), Monday is day two (skipped), Tuesday
        // has no run (posts again on the same balance).
        let l = ledger(beers: [beer(t0)], runs: [run(1.2, endedAt: morning(1)), run(1.2, endedAt: morning(2))])
        let sunday = report(l, at: at(day + hour)).balance
        #expect(close(sunday.debtMiles, 0))   // the mile paid it; add a bigger tab instead
        let big = ledger(beers: [beer(t0), beer(t0), beer(t0), beer(t0), beer(t0)],
                         runs: [run(1.2, endedAt: morning(1)), run(1.2, endedAt: morning(2))])
        // 5 beers = 5.0 mi. Sunday run pays 1.2 → 3.8; Sunday 20:00 posts 10% → 4.18.
        #expect(close(report(big, at: at(day + hour)).balance.debtMiles, 4.18))
        // Monday run pays 1.2 → 2.98; Monday 20:00 is protected: still 2.98.
        #expect(close(report(big, at: at(2 * day + hour)).balance.debtMiles, 2.98))
        // Tuesday, no run: posts again → 3.278. Interest already owed (0.2 left after
        // Monday's run paid the rest) was never refunded: 0.2 + 0.298.
        #expect(close(report(big, at: at(3 * day + hour)).balance.debtMiles, 3.278))
        #expect(close(report(big, at: at(3 * day + hour)).balance.interestMiles, 0.498))
    }

    @Test func protectionIsOffForOldLedgersUntilTheRuleTurnsOn() {
        let runs = [run(1.2, endedAt: morning(1)), run(1.2, endedAt: morning(2))]
        let beers = Array(repeating: (), count: 5).map { _ in beer(t0) }
        let off = ledger(rules: noStreak, beers: beers, runs: runs)
        #expect(close(report(off, at: at(2 * day + hour)).balance.debtMiles, 2.98 * 1.1))
        // Switched on Monday noon, before the 20:00 posting: that posting is skipped.
        let on = withChange(off, at: at(2 * day - 8 * hour)) { $0.streakProtection = true }
        #expect(close(report(on, at: at(2 * day + hour)).balance.debtMiles, 2.98))
    }

    @Test func aWeeklyPostingOnAProtectedDayIsSkippedWhole() {
        var weekly = Rules.default
        weekly.interestPeriod = .weekly
        weekly.gracePeriod = 0
        // Beer Saturday; the weekly posting lands next Saturday 20:00. Runs Fri + Sat that week.
        let l = ledger(rules: weekly, beers: [beer(t0), beer(t0), beer(t0)],
                       runs: [run(1, endedAt: morning(6)), run(1, endedAt: morning(7))])
        // 3.0 − 1.0 − 1.0 = 1.0 owed; the posting is skipped, so still 1.0 on Sunday.
        #expect(close(report(l, at: at(week + hour)).balance.debtMiles, 1.0))
    }

    @Test func aStreakSurvivesDebtAndCreditAndANewBeer() {
        // Six streak days with no debt, then a beer on day six: protection carries over.
        let runs = (0..<6).map { run(1.5, endedAt: morning($0)) }
        let l = ledger(openedAt: at(-day), beers: [beer(at(5 * day))], runs: runs)   // beer Thursday 20:00
        let r = report(l, at: at(6 * day + hour))               // Friday 21:00: no run yet today, streak alive from Thursday
        #expect(r.streak.currentStreakDays == 6)
        #expect(r.balance.state == .credit)                     // the beer came out of banked credit
        #expect(r.streak.interestProtectionActive)
        #expect(r.runs.map(\.streakDayNumber) == [1, 2, 3, 4, 5, 6])
    }

    @Test func theReportCarriesTheStreak() {
        let l = ledger(openedAt: at(-day), runs: [run(1, endedAt: morning(0)), run(0.5, endedAt: at(-hour))])
        let r = report(l, at: t0)
        #expect(r.streak.currentStreakDays == 1)
        // A lone mile is day one of nothing yet: no day number until tomorrow qualifies.
        #expect(r.runs.map(\.streakDayNumber) == [nil, nil])
    }

    @Test func runsAreNumberedOnlyOnceAStreakReachesTwoDays() {
        // Mon 1.3 (alone), Wed 1.0, Thu 1.0, Fri 0.5.
        let l = ledger(openedAt: at(-day), runs: [run(1.3, endedAt: morning(0)), run(1, endedAt: morning(2)),
                                                  run(1, endedAt: morning(3)), run(0.5, endedAt: morning(4))])
        let r = report(l, at: at(4 * day))
        #expect(r.runs.map(\.streakDayNumber) == [nil, 1, 2, nil])
        // Both runs on a day share the day's number.
        let two = ledger(openedAt: at(-day), runs: [run(0.6, endedAt: morning(0)), run(0.6, endedAt: at(-hour)), run(1, endedAt: morning(1))])
        #expect(report(two, at: at(day)).runs.map(\.streakDayNumber) == [1, 1, 2])
    }
}
