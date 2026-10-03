import Foundation
import Testing
@testable import BeerDebt

/// "Mile Markers" reads the books; it never changes them. These pin the
/// readings, especially the two that aren't a plain sum: interest charged
/// during a range, and what the streak waived.
struct MileMarkersStatsTests {
    private func build(_ ledger: Ledger, _ range: MileMarkersRange = .all, at now: Date) -> MileMarkersReport {
        MileMarkersStats.build(ledger: ledger, range: range, now: now, calendar: utc)
    }

    @Test func emptyBooksReadAsEmpty() {
        let report = build(ledger(), at: at(day))
        #expect(report.isEmpty)
        #expect(report.beersAdded == 0)
        #expect(report.runCount == 0)
        #expect(report.interestChargedMiles == 0)
        #expect(report.interestWaivedMiles == 0)
        // Still a curve, so the chart has something to draw.
        #expect(report.points.count >= 2)
        #expect(report.points.allSatisfy { $0.debtMiles == 0 })
    }

    @Test func flowsAreCountedOnceAndTotalled() {
        let books = ledger(
            beers: [beer(at(hour)), beer(at(2 * hour)), beer(at(26 * hour))],
            runs: [run(2, endedAt: morning(1)), run(3.5, endedAt: morning(2))]
        )
        let report = build(books, at: at(3 * day))
        #expect(report.beersAdded == 3)
        #expect(report.runCount == 2)
        #expect(close(report.milesRun, 5.5))
        // Every beer and every run lands in exactly one bucket.
        #expect(report.points.reduce(0) { $0 + $1.beers } == 3)
        #expect(close(report.points.reduce(0) { $0 + $1.runMiles }, 5.5))
        // The cumulative lines end at the totals they are summing.
        #expect(close(report.points.last!.cumulativeRunMiles, 5.5))
        #expect(close(report.points.last!.cumulativeBeerMiles, 3.0))
    }

    @Test func theCurveEndsOnTheLiveBalance() {
        let books = ledger(beers: [beer(t0), beer(at(hour))])
        let now = at(5 * day)
        let report = build(books, at: now)
        let live = BalanceEngine.report(for: books, at: now, calendar: utc)
        #expect(report.points.last?.date == now)
        #expect(close(report.points.last!.debtMiles, live.balance.debtMiles))
        #expect(close(report.points.last!.principalMiles, live.balance.principalMiles))
        #expect(close(report.points.last!.interestMiles, live.balance.interestMiles))
        #expect(close(report.debtAtEndMiles, live.balance.debtMiles))
    }

    @Test func interestChargedIsWhatPostedInsideTheRange() {
        // One beer, left alone: interest posts daily after the grace period.
        let books = ledger(beers: [beer(t0)])
        let early = build(books, .all, at: at(3 * day))
        let later = build(books, .all, at: at(10 * day))
        #expect(later.interestChargedMiles > early.interestChargedMiles)

        // A window that opens after the beer charges only what posted inside it.
        let windowed = MileMarkersStats.build(ledger: books, range: .month, now: at(10 * day), calendar: utc)
        let total = MileMarkersStats.interestAccrued(in: BalanceEngine.report(for: books, at: at(10 * day), calendar: utc))
        // The month window reaches back past the books here, so it is the lot.
        #expect(close(windowed.interestChargedMiles, total))
    }

    @Test func aStreakWaivesInterestAndSaysHowMuch() {
        // Ten beers, then a mile a day: from day two the streak pauses
        // interest. The runs are deliberately too small to clear the tab, so
        // there is still a debt for the protection to be worth something on.
        var runs: [RunEntry] = []
        for n in 1...6 { runs.append(run(1.1, endedAt: morning(n))) }
        let books = ledger(beers: (0..<10).map { beer(at(Double($0) * 60)) }, runs: runs)
        let now = at(7 * day)
        let report = build(books, at: now)

        // Those runs are too short to repay much, so debt is still open and
        // the protection is the only thing holding interest down.
        #expect(report.interestWaivedMiles > 0)

        // And it is exactly the difference against the same books unprotected.
        let bare = MileMarkersStats.unprotected(books)
        let bareInterest = MileMarkersStats.interestAccrued(in: BalanceEngine.report(for: bare, at: now, calendar: utc))
        let realInterest = MileMarkersStats.interestAccrued(in: BalanceEngine.report(for: books, at: now, calendar: utc))
        #expect(close(report.interestWaivedMiles, bareInterest - realInterest))
    }

    @Test func noStreakWaivesNothing() {
        let books = ledger(beers: [beer(t0)])
        let report = build(books, at: at(6 * day))
        #expect(report.interestChargedMiles > 0)
        #expect(report.interestWaivedMiles == 0)
    }

    @Test func theCounterfactualNeverTouchesTheRealBooks() {
        let books = ledger(beers: [beer(t0)], runs: [run(1, endedAt: morning(1))])
        let before = books
        _ = build(books, at: at(3 * day))
        #expect(books == before)
        // And `unprotected` returns a copy with protection off everywhere.
        let bare = MileMarkersStats.unprotected(books)
        #expect(bare.rulesHistory.allSatisfy { !$0.rules.streakProtection })
        #expect(books.rulesHistory.allSatisfy { $0.rules.streakProtection })
        #expect(bare.beers == books.beers)
        #expect(bare.runs == books.runs)
    }

    @Test func theGridCoversEveryDayInTheRange() {
        let books = ledger(runs: [run(2, endedAt: morning(1)), run(0.3, endedAt: morning(3))])
        let report = build(books, at: at(5 * day))
        // Consecutive, no gaps, start of day each.
        for (a, b) in zip(report.days, report.days.dropFirst()) {
            #expect(close(b.date.timeIntervalSince(a.date), day))
        }
        // The two-mile day qualifies; the third-of-a-mile day doesn't.
        #expect(report.days.filter(\.qualifies).count == 1)
        #expect(close(report.days.first { $0.qualifies }?.miles ?? 0, 2.0))
    }

    @Test func protectedStretchesBecomeSpansBehindTheCurve() {
        // Days 1-5 qualify, day 6 is missed, days 7-8 qualify again.
        var runs: [RunEntry] = []
        for n in [1, 2, 3, 4, 5, 7, 8] { runs.append(run(1.4, endedAt: morning(n))) }
        let books = ledger(beers: [beer(t0)], runs: runs)
        let report = build(books, at: at(9 * day))

        let protected = report.spans.filter { $0.kind == .protected }
        // Protection starts on day two of each streak, so two separate washes.
        #expect(protected.count == 2)
        #expect(protected.allSatisfy { $0.end > $0.start })
        // The gap day is inside neither.
        let missed = utc.startOfDay(for: morning(6))
        #expect(!protected.contains { $0.start <= missed && missed < $0.end })
        // Every protected day the grid reports is covered by exactly one span.
        for day in report.days where day.interestProtected {
            #expect(protected.filter { $0.start <= day.date && day.date < $0.end }.count == 1)
        }
    }

    @Test func aFrozenDayGetsItsOwnSpanOverTheProtectionItBuys() {
        // Five running days earn a freeze; spend it on the day after the last.
        var runs: [RunEntry] = []
        for n in 1...5 { runs.append(run(1.4, endedAt: morning(n))) }
        var books = ledger(beers: [beer(t0)], runs: runs)
        books.freezeApplications = [
            .forDay(containing: morning(6), calendar: utc, appliedAt: morning(6))
        ]
        let report = build(books, at: at(7 * day))

        let frozen = report.spans.filter { $0.kind == .frozen }
        #expect(frozen.count == 1)
        #expect(frozen[0].start == utc.startOfDay(for: morning(6)))
        // And the day it covers is still protected, so the wash sits on top
        // of a protected span rather than replacing it.
        #expect(report.days.first { $0.date == frozen[0].start }?.frozen == true)
        #expect(report.days.first { $0.date == frozen[0].start }?.interestProtected == true)
    }

    @Test func noStreakDrawsNoSpans() {
        let books = ledger(beers: [beer(t0)])
        #expect(build(books, at: at(5 * day)).spans.isEmpty)
    }

    @Test func rangesClampToTheBooksRatherThanInventingHistory() {
        let books = ledger(beers: [beer(t0)])
        let report = MileMarkersStats.build(ledger: books, range: .year, now: at(2 * day), calendar: utc)
        // The books opened at t0; a year-long window doesn't pretend otherwise.
        #expect(report.start == t0)
        #expect(report.end == at(2 * day))
    }

    @Test func aBackdatedBeerPullsTheAllTimeRangeBackBehindTheBooks() {
        // A beer may predate the opening (30-day backdating); runs may not.
        var books = ledger()
        books.beers = [beer(at(-5 * day))]
        let report = MileMarkersStats.build(ledger: books, range: .all, now: at(day), calendar: utc)
        #expect(report.start == at(-5 * day))
        #expect(report.beersAdded == 1)
    }

    @Test func theDrySpellIsTheLongestStretchWithNoBeer() {
        // Beers on day 0 and day 5: four clear days between them.
        let books = ledger(beers: [beer(at(hour)), beer(at(5 * day + hour))])
        let report = build(books, at: at(5 * day + 2 * hour))
        #expect(report.longestDrySpellDays == 4)
    }

    @Test func theBiggestDayAndPriciestBeerAreNamed() {
        let books = ledger(beers: [
            beer(t0), beer(at(hour)), beer(at(2 * hour)),     // three on day one
            beer(at(3 * day)),
        ])
        let report = build(books, at: at(6 * day))
        #expect(report.biggestDayBeers == 3)
        #expect(report.biggestDay == utc.startOfDay(for: t0))
        // The oldest unpaid beer has had the longest to accrue.
        #expect(report.priciestBeer?.createdAt == t0)
        #expect(report.priciestBeerInterestMiles > 0)
    }

    @Test func eventsStayFewAndInOrder() {
        var runs: [RunEntry] = []
        for n in 1...5 { runs.append(run(1.5, endedAt: morning(n))) }
        let books = ledger(beers: [beer(t0), beer(at(hour)), beer(at(2 * hour))], runs: runs)
        let report = build(books, at: at(6 * day))
        #expect(report.events.count <= 4)
        #expect(report.events == report.events.sorted { $0.date < $1.date })
        #expect(report.events.contains { if case .bigDay(let n) = $0.kind { return n == 3 }; return false })
    }

    @Test func recordsAreAllTimeNotRangeScoped() {
        // A six-day streak a month ago, nothing since.
        var runs: [RunEntry] = []
        for n in 1...6 { runs.append(run(1.5, endedAt: morning(n))) }
        let books = ledger(runs: runs)
        let now = at(40 * day)
        let month = MileMarkersStats.build(ledger: books, range: .month, now: now, calendar: utc)
        // The window holds no runs at all...
        #expect(month.runCount == 0)
        // ...but the record it set still stands.
        #expect(month.longestStreakDays == 6)
        #expect(month.totalStreakDays == 6)
    }

    @Test func sampleCountIsBoundedWhateverTheSpan() {
        // Three years of books still draws a chart a phone can hold.
        var beers: [BeerEntry] = []
        for n in 0..<150 { beers.append(beer(at(Double(n) * 7 * day))) }
        let books = ledger(beers: beers)
        let report = MileMarkersStats.build(ledger: books, range: .all, now: at(1_095 * day), calendar: utc)
        #expect(report.points.count == MileMarkersRange.all.samples + 1)
        #expect(report.points.count <= 64)
    }
}
