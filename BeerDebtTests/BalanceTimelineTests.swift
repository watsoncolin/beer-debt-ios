import Foundation
import Testing
@testable import BeerDebt

/// The widget's timeline shape (spec §22). Entries are projections of the
/// ledger as it stood when they were built, so the horizon is the worst case
/// for how long a stale face can survive a reload the system declined.
struct BalanceTimelineTests {
    @Test func entriesRunHourlyAcrossTheHorizon() {
        let dates = BalanceTimeline.entryDates(now: t0, nextInterestAt: nil)
        #expect(dates.count == 7)
        #expect(dates.first == t0)
        #expect(dates.last == t0.addingTimeInterval(6 * hour))
        for (i, date) in dates.enumerated() {
            #expect(date == t0.addingTimeInterval(Double(i) * hour))
        }
    }

    @Test func rebuildIsAskedForAtTheEndOfTheHorizon() {
        #expect(BalanceTimeline.refresh(after: t0) == t0.addingTimeInterval(6 * hour))
    }

    @Test func anInterestPostingInsideTheWindowGetsItsOwnEntry() {
        let posting = t0.addingTimeInterval(2 * hour + 900)
        let dates = BalanceTimeline.entryDates(now: t0, nextInterestAt: posting)
        #expect(dates.count == 8)
        #expect(dates.contains(posting))
        #expect(dates == dates.sorted())
        // It lands between the hours either side of it, not on the end.
        #expect(dates[3] == posting)
    }

    @Test func aPostingBeyondTheHorizonNeverStretchesIt() {
        // The bug this guards: appending a posting a day out and refreshing
        // at the last entry left the widget without a rebuild for a day.
        let dates = BalanceTimeline.entryDates(now: t0, nextInterestAt: t0.addingTimeInterval(20 * hour))
        #expect(dates.count == 7)
        #expect(dates.last == t0.addingTimeInterval(6 * hour))
    }

    @Test func aPostingAlreadyPastIsIgnored() {
        let dates = BalanceTimeline.entryDates(now: t0, nextInterestAt: t0.addingTimeInterval(-hour))
        #expect(dates.count == 7)
        #expect(dates.first == t0)
    }

    @Test func theHorizonIsShortEnoughToBeARepair() {
        // A day of staleness is the thing being fixed; keep it to hours.
        #expect(BalanceTimeline.horizon <= 6 * hour)
    }
}
