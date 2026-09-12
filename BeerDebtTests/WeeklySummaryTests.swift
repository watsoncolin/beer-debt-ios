import Foundation
import Testing
@testable import BeerDebt

struct WeeklySummaryTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func aTypicalWeek() {
        // Two beers this week, one run, still in debt at fire time.
        let l = ledger(openedAt: at(-10 * day), beers: [beer(at(-2 * day)), beer(at(-day))], runs: [run(1.5, endedAt: at(-3 * day))])
        let m = WeeklySummary.message(ledger: l, at: t0, calendar: utc)
        #expect(m.title == "Your week in beer")
        #expect(m.body.hasPrefix("2 beers, 1.5 mi run."))
        #expect(m.body.hasSuffix("owed."))
    }

    @Test func aQuietWeekIsSuspicious() {
        let m = WeeklySummary.message(ledger: ledger(), at: t0, calendar: utc)
        #expect(m.body == "0 beers, 0.0 mi run. Nothing to report. Suspicious.")
    }

    @Test func beersWithoutRunningGetsANudge() {
        let l = ledger(openedAt: at(-10 * day), beers: [beer(at(-day))])
        let m = WeeklySummary.message(ledger: l, at: t0, calendar: utc)
        // One posting has landed by the time it fires: 1.0 → 1.1.
        #expect(m.body == "1 beer, 0.0 mi run. The running part is optional, apparently. You're at 1.1 mi owed.")
    }

    @Test func standingIsProjectedToTheFireTime() {
        // Beer on Saturday; the summary fires a week later, after seven daily postings.
        let l = ledger(beers: [beer(t0)])
        let m = WeeklySummary.message(ledger: l, at: at(week), calendar: utc)
        #expect(m.body.hasSuffix("You're at 1.9 mi owed."))   // 1.1^7 = 1.95
    }

    @Test func nextFourSundaysAtSix() {
        let dates = WeeklySummary.nextFireDates(after: t0, weekday: 1, hour: 18, minute: 0, count: 4, calendar: utc)
        #expect(dates.count == 4)
        for (i, d) in dates.enumerated() {
            let parts = utc.dateComponents([.weekday, .hour, .minute], from: d)
            #expect(parts.weekday == 1 && parts.hour == 18 && parts.minute == 0)
            if i > 0 { #expect(close(d.timeIntervalSince(dates[i - 1]), week)) }
        }
        #expect(dates[0] > t0)
    }
}
