import Foundation
import Testing
@testable import BeerDebt

/// Streak freezes (spec §25.1, APPS-6): five qualifying running days earn one
/// rest day that keeps the streak and the 0% APR without counting as running.
///
/// One test per acceptance criterion on the ticket, in its order, so a change
/// in behaviour points at the line it broke. `morning(n)` is 07:00 UTC on
/// t0 + n days, and the calendar is pinned to UTC as everywhere else.
struct StreakFreezeTests {
    private func streak(_ runs: [RunEntry], freezes: [Date] = [], at now: Date) -> StreakStatus {
        StreakEngine.calculate(
            runs: runs,
            freezeApplications: freezes.map { FreezeApplication.forDay(containing: $0, calendar: utc, appliedAt: $0) },
            at: now,
            calendar: utc
        )
    }

    /// A mile on each of days `d`.
    private func miles(_ d: [Int]) -> [RunEntry] { d.map { run(1.0, endedAt: morning($0)) } }
    /// Start of day n: what `repairableDay` reports and what the tests name.
    private func startOfDay(_ n: Int) -> Date { utc.startOfDay(for: morning(n)) }

    // MARK: Earning

    @Test func fiveQualifyingDaysEarnExactlyOneFreeze() {
        // Four is not enough.
        #expect(streak(miles([0, 1, 2, 3]), at: morning(3)).freezesHeld == 0)
        #expect(streak(miles([0, 1, 2, 3]), at: morning(3)).freezeProgressDays == 4)
        // The fifth earns it, and the counter resets rather than reading 5.
        let five = streak(miles([0, 1, 2, 3, 4]), at: morning(4))
        #expect(five.freezesHeld == 1)
        #expect(five.freezeProgressDays == 0)
    }

    @Test func inventoryNeverExceedsOne() {
        // Ten qualifying days would be two freezes if they stacked.
        let ten = streak(miles(Array(0..<10)), at: morning(9))
        #expect(ten.freezesHeld == 1)
        // And nothing is banked secretly toward a second.
        #expect(ten.freezeProgressDays == 0)
    }

    @Test func aFreezeDayDoesNotCountTowardTheNextFreeze() {
        // Five runs earn one; spend it on day 5; then four more runs. If the
        // frozen day counted, day 10 would be the fifth and earn another.
        let runs = miles([0, 1, 2, 3, 4, 6, 7, 8, 9])
        let s = streak(runs, freezes: [startOfDay(5)], at: morning(9))
        #expect(s.isFrozen(on: morning(5)))
        #expect(s.freezeProgressDays == 4)
        #expect(s.freezesHeld == 0)
    }

    @Test func fiveNewQualifyingDaysEarnAnotherAfterUse() {
        let runs = miles([0, 1, 2, 3, 4, 6, 7, 8, 9, 10])
        let s = streak(runs, freezes: [startOfDay(5)], at: morning(10))
        #expect(s.freezesHeld == 1)
        #expect(s.freezeProgressDays == 0)
    }

    // MARK: Applying

    @Test func aFreezeCanBeSpentOnToday() {
        // Five days run, nothing today, a freeze in hand: the offer stands.
        let before = streak(miles([0, 1, 2, 3, 4]), at: morning(5))
        #expect(before.canFreezeToday)
        #expect(before.currentStreakDays == 5)

        let after = streak(miles([0, 1, 2, 3, 4]), freezes: [startOfDay(5)], at: morning(5))
        #expect(after.todayFrozen)
        #expect(!after.canFreezeToday)
    }

    @Test func theOfferIsWithheldWithoutAFreezeOrWithTodayAlreadyRun() {
        // No freeze yet.
        #expect(!streak(miles([0, 1]), at: morning(2)).canFreezeToday)
        // Freeze in hand but today's mile is already run: nothing to protect.
        #expect(!streak(miles([0, 1, 2, 3, 4]), at: morning(4)).canFreezeToday)
    }

    @Test func aFreezeRepairsTheFirstMissedDayThatBrokeTheStreak() {
        // Days 0-4 run, day 5 missed, day 6 run. The break is day 5.
        let runs = miles([0, 1, 2, 3, 4, 6])
        let broken = streak(runs, at: morning(6))
        #expect(broken.repairableDay == startOfDay(5))
        // Repaired, the streak reads through: 5 days, then the frozen day, then day 6.
        let repaired = streak(runs, freezes: [startOfDay(5)], at: morning(6))
        #expect(repaired.isFrozen(on: morning(5)))
        #expect(repaired.currentStreakDays == 6)
    }

    @Test func oneFreezeCannotRepairTwoMissedDays() {
        // Days 5 and 6 both missed: repairing day 5 buys nothing, since the
        // streak breaks at day 6 regardless.
        let runs = miles([0, 1, 2, 3, 4, 7])
        #expect(streak(runs, at: morning(7)).repairableDay == nil)
        // Spending it anyway protects only its own day; the streak still broke.
        let s = streak(runs, freezes: [startOfDay(5)], at: morning(7))
        #expect(s.isFrozen(on: morning(5)))
        #expect(!s.isFrozen(on: morning(6)))
        #expect(s.currentStreakDays == 1)
    }

    @Test func anApplicationWithNoFreezeInHandIsIgnored() {
        // Two running days is not five, so there is nothing to spend.
        let s = streak(miles([0, 1]), freezes: [startOfDay(2)], at: morning(2))
        #expect(!s.isFrozen(on: morning(2)))
        #expect(s.currentStreakDays == 2)   // yesterday's streak, today not yet run
        #expect(s.freezesHeld == 0)
    }

    // MARK: Effect

    @Test func aFreezePreservesContinuityWithoutIncrementingLength() {
        let s = streak(miles([0, 1, 2, 3, 4]), freezes: [startOfDay(5)], at: morning(5))
        // The ticket's worked example: streak remains 5 across the rest day.
        #expect(s.currentStreakDays == 5)
        #expect(s.day(on: morning(5))?.streakNumber == 5)
        // And the next running day continues from there.
        let next = streak(miles([0, 1, 2, 3, 4, 6]), freezes: [startOfDay(5)], at: morning(6))
        #expect(next.currentStreakDays == 6)
    }

    @Test func aFreezeKeepsInterestPausedForItsDay() {
        let s = streak(miles([0, 1, 2, 3, 4]), freezes: [startOfDay(5)], at: morning(5))
        #expect(s.isProtected(on: morning(5)))
        #expect(s.todayProtected)
        #expect(s.interestProtectionActive)
    }

    @Test func aFreezeAddsNoMileageAndIsNotARunningDay() {
        let s = streak(miles([0, 1, 2, 3, 4]), freezes: [startOfDay(5)], at: morning(5))
        let frozenDay = s.day(on: morning(5))
        #expect(frozenDay?.miles == 0)
        #expect(frozenDay?.qualifies == false)
        #expect(frozenDay?.isRunningDay == false)
        // Five running days on the books, not six.
        #expect(s.totalQualifyingDays == 5)
    }

    @Test func aFrozenDayIsNeverTaggedAsAStreakRunDay() {
        let s = streak(miles([0, 1, 2, 3, 4]), freezes: [startOfDay(5)], at: morning(5))
        #expect(s.streakDayNumber(on: morning(5)) == nil)
        #expect(s.streakDayNumber(on: morning(4)) == 5)
    }

    // MARK: HealthKit reconciliation

    @Test func lateQualifyingDataRefundsTheFreeze() {
        let earned = miles([0, 1, 2, 3, 4])
        let frozen = streak(earned, freezes: [startOfDay(5)], at: morning(6))
        #expect(frozen.isFrozen(on: morning(5)))
        #expect(frozen.freezesHeld == 0)

        // The run for day 5 imports late. The day now qualifies on its own, so
        // the application stops being honoured and the freeze comes back.
        let reconciled = streak(earned + miles([5]), freezes: [startOfDay(5)], at: morning(6))
        #expect(!reconciled.isFrozen(on: morning(5)))
        #expect(reconciled.qualifies(on: morning(5)))
        #expect(reconciled.freezesHeld == 1, "the freeze is refunded, not spent")
        // And the run counts normally: six running days, streak of six.
        #expect(reconciled.totalQualifyingDays == 6)
        #expect(reconciled.currentStreakDays == 6)
    }

    @Test func aRefundKeepsInventoryCappedAtOne() {
        // Ten running days plus a refunded freeze must still be one, not two.
        let runs = miles(Array(0..<10))
        let s = streak(runs, freezes: [startOfDay(5)], at: morning(9))
        #expect(s.freezesHeld == 1)
    }

    @Test func duplicateApplicationsForOneDaySpendOneFreeze() {
        // Two taps, or a re-imported ledger, must not consume two.
        let day = startOfDay(5)
        let runs = miles([0, 1, 2, 3, 4, 6, 7, 8, 9])
        let s = streak(runs, freezes: [day, day], at: morning(9))
        #expect(s.isFrozen(on: morning(5)))
        #expect(s.freezeProgressDays == 4, "only one freeze was spent")
    }

    // MARK: Determinism

    @Test func replayingTheSameLedgerTwiceGivesTheSameAnswer() {
        let runs = miles([0, 1, 2, 3, 4, 6, 7])
        let freezes = [startOfDay(5)]
        let a = streak(runs, freezes: freezes, at: morning(7))
        let b = streak(runs.reversed(), freezes: freezes, at: morning(7))
        #expect(a.currentStreakDays == b.currentStreakDays)
        #expect(a.freezesHeld == b.freezesHeld)
        #expect(a.freezeProgressDays == b.freezeProgressDays)
        #expect(a.days.map(\.frozen) == b.days.map(\.frozen))
    }

    @Test func aFreezeSurvivesTheUserChangingTimeZone() {
        // Keyed to midday, so re-bucketing through another calendar still lands
        // on the same date. Midnight would slide onto the day before.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let runs = miles([0, 1, 2, 3, 4])
        let applied = FreezeApplication.forDay(containing: morning(5), calendar: utc, appliedAt: morning(5))

        #expect(StreakEngine.calculate(runs: runs, freezeApplications: [applied], at: morning(5), calendar: utc)
            .isFrozen(on: morning(5)))
        #expect(StreakEngine.calculate(runs: runs, freezeApplications: [applied], at: morning(5), calendar: newYork)
            .isFrozen(on: morning(5)), "a five-hour shift must not move the frozen day")

        // Midnight-keyed, which is what we are avoiding, does move.
        let atMidnight = FreezeApplication(day: utc.startOfDay(for: morning(5)), appliedAt: morning(5))
        #expect(!StreakEngine.calculate(runs: runs, freezeApplications: [atMidnight], at: morning(5), calendar: newYork)
            .isFrozen(on: morning(5)))
    }

    @Test func aFreezeBeforeAnyRunEarnsNothingAndChangesNothing() {
        let s = streak([], freezes: [startOfDay(0)], at: morning(0))
        #expect(!s.todayFrozen)
        #expect(s.currentStreakDays == 0)
        #expect(s.freezesHeld == 0)
    }

}

/// The store's half: it never spends a freeze on its own, and it refuses any
/// day but today or the one break a freeze could repair (spec §25.1, the MVP
/// guard against arbitrary history editing).
@MainActor
struct StreakFreezeStoreTests {
    /// The books open at the start of day 0. `t0` itself is 20:00, which would
    /// drop that morning's run as pre-books and shift every count by one.
    private func store(runs days: [Int], openedAt: Date = utc.startOfDay(for: morning(0))) -> LedgerStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beerdebt-freeze-\(UUID().uuidString)", isDirectory: true)
        let store = LedgerStore(directory: dir, now: openedAt)
        store.importRuns(days.map { run(1.0, endedAt: morning($0)) })
        return store
    }

    @Test func todayIsFrozenOnlyWhenAFreezeIsHeld() {
        // Four running days: nothing earned, so nothing to spend.
        let short = store(runs: [0, 1, 2, 3])
        #expect(!short.freezeToday(now: morning(4), calendar: utc))
        #expect(short.ledger.freezeApplications.isEmpty)

        // The fifth earns one, and today can be frozen -- once.
        let earned = store(runs: [0, 1, 2, 3, 4])
        #expect(earned.freezeToday(now: morning(5), calendar: utc))
        #expect(earned.ledger.freezeApplications.count == 1)
        #expect(!earned.freezeToday(now: morning(5), calendar: utc))
        #expect(earned.ledger.freezeApplications.count == 1)
    }

    @Test func theBreakThatEndedTheStreakCanBeRepaired() {
        // Days 0-4 run (earning the freeze on day 4), day 5 missed, day 6 run.
        let s = store(runs: [0, 1, 2, 3, 4, 6])
        #expect(s.applyFreeze(on: morning(5), now: morning(6), calendar: utc))
        #expect(s.report(at: morning(6)).streak.isFrozen(on: morning(5)))
    }

    @Test func anArbitraryHistoricalDayIsRefused() {
        // Twelve running days, so a freeze is definitely in hand.
        let s = store(runs: Array(0..<12))
        #expect(s.report(at: morning(11)).streak.freezesHeld == 1)
        // Day 2 is neither today nor a break: refused, and nothing written.
        #expect(!s.applyFreeze(on: morning(2), now: morning(11), calendar: utc))
        #expect(s.ledger.freezeApplications.isEmpty)
    }

    @Test func aFreezeCannotBeSpentOnADayBeforeItWasEarned() {
        // Days 1-4 and 6 run, day 5 missed. The fifth running day is day 6, so
        // the freeze is not in hand until after the break it would repair.
        let s = store(runs: [1, 2, 3, 4, 6], openedAt: utc.startOfDay(for: morning(1)))
        #expect(s.report(at: morning(6)).streak.freezesHeld == 1)
        // The store allows the tap, since day 5 is the break...
        #expect(s.applyFreeze(on: morning(5), now: morning(6), calendar: utc))
        // ...but the replay refuses to honour it: nothing was held on day 5.
        let streak = s.report(at: morning(6)).streak
        #expect(!streak.isFrozen(on: morning(5)))
        #expect(streak.currentStreakDays == 1)
    }

    @Test func aFreezeSurvivesARelaunch() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beerdebt-freeze-\(UUID().uuidString)", isDirectory: true)
        let first = LedgerStore(directory: dir, now: utc.startOfDay(for: morning(0)))
        first.importRuns((0..<5).map { run(1.0, endedAt: morning($0)) })
        #expect(first.freezeToday(now: morning(5), calendar: utc))

        let second = LedgerStore(directory: dir, now: morning(5))
        #expect(second.ledger.freezeApplications.count == 1)
        #expect(second.report(at: morning(5)).streak.todayFrozen)
    }
}
