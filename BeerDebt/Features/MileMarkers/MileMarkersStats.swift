import Foundation

/// How far back "Mile Markers" looks. The picker at the top of the screen.
enum MileMarkersRange: String, CaseIterable, Identifiable, Sendable {
    case month = "1M"
    case quarter = "3M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    /// Spoken mid-sentence: "down 6.2 mi over the last month".
    var phrase: String {
        switch self {
        case .month: "the last month"
        case .quarter: "the last 3 months"
        case .year: "the last year"
        case .all: "all time"
        }
    }

    var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }

    /// How many points the balance curve is sampled at.
    ///
    /// Deliberately small and fixed. Each point is a full replay — the engine
    /// has no way to emit a series from one pass — and a replay costs roughly
    /// one interest posting per unpaid beer per period, so a tab that has been
    /// left to run grows the per-point cost without bound. Forty-odd points
    /// draw a smooth curve at phone width anyway; more would only buy
    /// invisible resolution at a cost the worst-off user pays most.
    var samples: Int {
        switch self {
        case .month: 30
        case .quarter: 45
        case .year: 52
        case .all: 40
        }
    }
}

/// Everything "Mile Markers" draws, computed once off the main thread.
///
/// Pure and `Sendable`: built from a `Ledger` snapshot and an instant, with no
/// clock and no I/O, the same contract the engine keeps. Deliberately *not* in
/// `Engine/`: it is a reading of the books rather than part of them, so it
/// stays out of the cross-platform fixture contract and can change here
/// without regenerating `cases.json`.
struct MileMarkersReport: Equatable, Sendable {
    /// One sampled instant on the balance curve, with the flows that landed in
    /// the bucket ending there.
    struct Point: Equatable, Sendable, Identifiable {
        let date: Date
        let debtMiles: Double
        let principalMiles: Double
        /// Stacked on top of `principalMiles` in the area chart: the wedge is
        /// what the waiting cost.
        let interestMiles: Double
        let creditMiles: Double
        /// Beers logged in this bucket.
        let beers: Int
        /// Miles run in this bucket.
        let runMiles: Double
        /// Cumulative miles owed from beers, from the start of the range.
        let cumulativeBeerMiles: Double
        /// Cumulative miles run, from the start of the range.
        let cumulativeRunMiles: Double

        var id: Date { date }
    }

    /// One calendar day in the streak grid.
    struct Day: Equatable, Sendable, Identifiable {
        let date: Date
        let miles: Double
        let qualifies: Bool
        /// Interest postings on this day were skipped (spec §25): the streak
        /// was alive, or a freeze was holding the day.
        let interestProtected: Bool
        let frozen: Bool
        var id: Date { date }
    }

    /// A stretch of days worth shading behind the balance curve. Protected
    /// spans are why the curve flattens; a freeze is a single day that held
    /// the line without a run.
    struct Span: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable { case protected, frozen }
        let start: Date
        let end: Date
        let kind: Kind
        var id: Date { start }

        var days: Double { end.timeIntervalSince(start) / 86_400 }

        /// A streak has to have held this long to earn an icon in the chart's
        /// marker lane. Over a long range an icon per stretch crowds the lane
        /// into a smear, and the ones worth pointing at are the ones that
        /// lasted; the wash behind the curve still shows every stretch.
        static let markableStreakDays: Double = 3

        /// Freezes are rare enough that every one is marked.
        var isMarked: Bool { kind == .frozen || days >= Self.markableStreakDays }

        /// Where the icon sits: the middle of the span it belongs to, so the
        /// icon reads as a label on its band rather than hanging off the edge.
        var markerDate: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }

    /// Something worth a line under the chart.
    struct Event: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case bigDay(beers: Int)
            case streakStarted(days: Int)
            case restDay
            case lowPoint(miles: Double)
            case clean
        }

        let date: Date
        let kind: Kind
        var id: Date { date }

        var title: String {
            switch kind {
            case .bigDay(let beers): "Big one: +\(beers) beers"
            case .streakStarted(let days): "\(days) day streak started"
            case .restDay: "Rest day — freeze spent"
            case .lowPoint(let miles): miles < 0.05 ? "Lowest tab of the range" : "Lowest tab: \(Format.miles(miles))"
            case .clean: "Books went clean"
            }
        }
    }

    let range: MileMarkersRange
    let start: Date
    let end: Date
    /// Oldest first. Empty when the books have nothing in them yet.
    let points: [Point]
    /// Every calendar day in the range, for the grid.
    let days: [Day]
    /// Protected stretches and frozen days, for the wash behind the curve.
    let spans: [Span]
    let events: [Event]

    // Totals over the range.
    let beersAdded: Int
    let runCount: Int
    let milesRun: Double
    /// Interest that posted during the range. Interest only ever accrues, so
    /// this is the end total less the start total.
    let interestChargedMiles: Double
    /// What the streak's protected days kept off the books: the same figure
    /// replayed with protection off, less what was actually charged.
    let interestWaivedMiles: Double
    /// End of range less start of range. Negative is progress.
    let debtChangeMiles: Double
    let debtAtStartMiles: Double
    let debtAtEndMiles: Double

    // Records. All-time, not range-scoped: a record you set last year is still
    // your record, and scoping it to the picker would quietly erase it.
    let currentStreakDays: Int
    let longestStreakDays: Int
    let totalStreakDays: Int
    let freezesHeld: Int
    let freezesSpent: Int

    // Superlatives, within the range.
    let priciestBeer: BeerStatement?
    let priciestBeerInterestMiles: Double
    let longestDrySpellDays: Int
    let biggestDayBeers: Int
    let biggestDay: Date?
    let longestRun: RunStatement?

    var isEmpty: Bool { beersAdded == 0 && runCount == 0 }
}

enum MileMarkersStats {
    /// Builds the whole screen's data from one ledger.
    ///
    /// Cost is dominated by `range.samples` replays plus three: the two ends of
    /// the counterfactual used for interest waived, and nothing else. Call it
    /// off the main actor; `Ledger` is `Sendable` precisely so this can be
    /// handed to a background task.
    static func build(
        ledger: Ledger,
        range: MileMarkersRange,
        now: Date,
        calendar: Calendar = .current
    ) -> MileMarkersReport {
        let end = now
        let start = startOfRange(range, ledger: ledger, now: now, calendar: calendar)
        let final = BalanceEngine.report(for: ledger, at: end, calendar: calendar)

        // The curve. Sampled, because the engine reports one instant at a time.
        let sampleCount = max(2, min(range.samples, 400))
        let span = max(end.timeIntervalSince(start), 1)
        let step = span / Double(sampleCount)
        var instants: [Date] = (0...sampleCount).map { start.addingTimeInterval(Double($0) * step) }
        instants[instants.count - 1] = end          // land exactly on now
        let balances = instants.map { BalanceEngine.report(for: ledger, at: $0, calendar: calendar).balance }

        // Flows per bucket, read off the final report's statements rather than
        // replayed: what was logged when doesn't depend on the instant.
        let beersInRange = final.beers.filter { $0.createdAt >= start && $0.createdAt <= end }
        let runsInRange = final.runs.filter { !$0.ignored && $0.run.endedAt >= start && $0.run.endedAt <= end }

        var points: [MileMarkersReport.Point] = []
        var cumulativeBeerMiles = 0.0
        var cumulativeRunMiles = 0.0
        points.reserveCapacity(sampleCount + 1)
        for (i, instant) in instants.enumerated() {
            // Buckets are half-open, (from, instant], so nothing is counted
            // twice. The first one takes its lower edge too, or an event landing
            // exactly on the opening instant would belong to no bucket at all.
            let from = i == 0 ? start : instants[i - 1]
            let inBucket = { (date: Date) in (i == 1 ? date >= from : date > from) && date <= instant }
            let beers = i == 0 ? [] : beersInRange.filter { inBucket($0.createdAt) }
            let runs = i == 0 ? [] : runsInRange.filter { inBucket($0.run.endedAt) }
            cumulativeBeerMiles += beers.reduce(0) { $0 + $1.costMiles }
            cumulativeRunMiles += runs.reduce(0) { $0 + $1.run.distanceMiles }
            let balance = balances[i]
            points.append(MileMarkersReport.Point(
                date: instant,
                debtMiles: balance.debtMiles,
                principalMiles: balance.principalMiles,
                interestMiles: balance.interestMiles,
                creditMiles: balance.creditMiles,
                beers: beers.count,
                runMiles: runs.reduce(0) { $0 + $1.run.distanceMiles },
                cumulativeBeerMiles: cumulativeBeerMiles,
                cumulativeRunMiles: cumulativeRunMiles
            ))
        }

        // Interest charged, and what the streak kept off.
        let interestAtStart = interestAccrued(in: BalanceEngine.report(for: ledger, at: start, calendar: calendar))
        let interestAtEnd = interestAccrued(in: final)
        let charged = max(0, interestAtEnd - interestAtStart)
        let bare = unprotected(ledger)
        let bareStart = interestAccrued(in: BalanceEngine.report(for: bare, at: start, calendar: calendar))
        let bareEnd = interestAccrued(in: BalanceEngine.report(for: bare, at: end, calendar: calendar))
        let waived = max(0, (bareEnd - bareStart) - charged)

        // The streak grid: every day in the range, whether or not a run touched it.
        let days = grid(from: start, to: end, streak: final.streak, calendar: calendar)
        let priciest = beersInRange.max { $0.interestAccruedMiles < $1.interestAccruedMiles }
        let big = biggestDay(beers: beersInRange, calendar: calendar)

        return MileMarkersReport(
            range: range,
            start: start,
            end: end,
            points: points,
            days: days,
            spans: spans(in: days, calendar: calendar),
            events: events(points: points, days: days, beers: beersInRange, streak: final.streak, calendar: calendar),
            beersAdded: beersInRange.count,
            runCount: runsInRange.count,
            milesRun: runsInRange.reduce(0) { $0 + $1.run.distanceMiles },
            interestChargedMiles: charged,
            interestWaivedMiles: waived,
            debtChangeMiles: (balances.last?.debtMiles ?? 0) - (balances.first?.debtMiles ?? 0),
            debtAtStartMiles: balances.first?.debtMiles ?? 0,
            debtAtEndMiles: balances.last?.debtMiles ?? 0,
            currentStreakDays: final.streak.currentStreakDays,
            longestStreakDays: final.streak.longestStreakDays,
            totalStreakDays: final.streak.totalQualifyingDays,
            freezesHeld: final.streak.freezesHeld,
            freezesSpent: final.streak.days.filter(\.frozen).count,
            priciestBeer: priciest,
            priciestBeerInterestMiles: priciest?.interestAccruedMiles ?? 0,
            longestDrySpellDays: longestDrySpell(beers: beersInRange, from: start, to: end, calendar: calendar),
            biggestDayBeers: big?.count ?? 0,
            biggestDay: big?.day,
            longestRun: runsInRange.max { $0.run.distanceMiles < $1.run.distanceMiles }
        )
    }

    /// Where the range opens. "All" starts at the first thing on the books,
    /// which may predate the opening: a beer can be backdated behind it.
    static func startOfRange(_ range: MileMarkersRange, ledger: Ledger, now: Date, calendar: Calendar) -> Date {
        let earliest = min(
            ledger.booksOpenedAt,
            ledger.beers.map(\.createdAt).min() ?? ledger.booksOpenedAt
        )
        guard let days = range.days else { return min(earliest, now) }
        let windowed = calendar.date(byAdding: .day, value: -days, to: now) ?? now.addingTimeInterval(-Double(days) * 86_400)
        // Never open the range before the books: an empty run-up reads as a
        // flat line the user never lived through.
        return max(windowed, min(earliest, now))
    }

    /// Total interest ever posted, paid or not. Monotonic over time, which is
    /// what lets two of these be subtracted to get "charged during the range".
    static func interestAccrued(in report: Report) -> Double {
        report.beers.reduce(0) { $0 + $1.interestAccruedMiles }
    }

    /// The same books with streak protection switched off throughout — the
    /// counterfactual behind "your streak waived N miles". Replaying it is
    /// pure, so this costs a replay and changes nothing.
    static func unprotected(_ ledger: Ledger) -> Ledger {
        var copy = ledger
        copy.rulesHistory = ledger.rulesHistory.map { change in
            var rules = change.rules
            rules.streakProtection = false
            return RulesChange(effectiveAt: change.effectiveAt, rules: rules)
        }
        return copy
    }

    static func grid(from start: Date, to end: Date, streak: StreakStatus, calendar: Calendar) -> [MileMarkersReport.Day] {
        var days: [MileMarkersReport.Day] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            let day = streak.day(on: cursor)
            days.append(MileMarkersReport.Day(
                date: cursor,
                miles: day?.miles ?? 0,
                qualifies: day?.qualifies ?? false,
                interestProtected: day?.interestProtected ?? false,
                frozen: day?.frozen ?? false
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
            // A year of days is 365 small structs; anything longer is still cheap,
            // but refuse to spin forever on a broken calendar.
            if days.count > 4_000 { break }
        }
        return days
    }

    /// Contiguous protected stretches, plus every frozen day on its own.
    /// A span runs to the end of its last day so the shading covers it.
    static func spans(in days: [MileMarkersReport.Day], calendar: Calendar) -> [MileMarkersReport.Span] {
        var spans: [MileMarkersReport.Span] = []
        var open: Date?
        var previous: Date?
        for day in days {
            if day.interestProtected {
                if open == nil { open = day.date }
                previous = day.date
            } else if let start = open, let last = previous {
                spans.append(.init(start: start, end: endOfDay(last, calendar: calendar), kind: .protected))
                open = nil
                previous = nil
            }
        }
        if let start = open, let last = previous {
            spans.append(.init(start: start, end: endOfDay(last, calendar: calendar), kind: .protected))
        }
        // Freezes are drawn over the protection they create, because the point
        // is that this one was bought rather than run for.
        for day in days where day.frozen {
            spans.append(.init(start: day.date, end: endOfDay(day.date, calendar: calendar), kind: .frozen))
        }
        return spans
    }

    private static func endOfDay(_ day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    /// The longest stretch of consecutive days with no beer on them.
    static func longestDrySpell(beers: [BeerStatement], from start: Date, to end: Date, calendar: Calendar) -> Int {
        let wet = Set(beers.map { calendar.startOfDay(for: $0.createdAt) })
        var longest = 0
        var current = 0
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            if wet.contains(cursor) {
                current = 0
            } else {
                current += 1
                longest = max(longest, current)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return longest
    }

    static func biggestDay(beers: [BeerStatement], calendar: Calendar) -> (day: Date, count: Int)? {
        let byDay = Dictionary(grouping: beers) { calendar.startOfDay(for: $0.createdAt) }
        guard let best = byDay.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return (best.key, best.value.count)
    }

    /// A handful of lines for under the chart. Capped, newest last, because a
    /// wall of them says nothing — the point is the two or three days that
    /// explain the shape of the curve.
    static func events(
        points: [MileMarkersReport.Point],
        days: [MileMarkersReport.Day],
        beers: [BeerStatement],
        streak: StreakStatus,
        calendar: Calendar
    ) -> [MileMarkersReport.Event] {
        var events: [MileMarkersReport.Event] = []

        if let big = biggestDay(beers: beers, calendar: calendar), big.count >= 3 {
            events.append(MileMarkersReport.Event(date: big.day, kind: .bigDay(beers: big.count)))
        }

        // Where a streak that reached two days began, the longest one first.
        let starts = streakStarts(days: days, streak: streak, calendar: calendar)
        if let best = starts.max(by: { $0.length < $1.length }), best.length >= 2 {
            events.append(MileMarkersReport.Event(date: best.day, kind: .streakStarted(days: best.length)))
        }

        if let rest = days.last(where: \.frozen) {
            events.append(MileMarkersReport.Event(date: rest.date, kind: .restDay))
        }

        // The low point, and the moment the books went clean if they did.
        if let clean = points.dropFirst().first(where: { $0.debtMiles < BalanceEngine.epsilon }),
           let opening = points.first, opening.debtMiles > BalanceEngine.epsilon {
            events.append(MileMarkersReport.Event(date: clean.date, kind: .clean))
        } else if let low = points.dropFirst().min(by: { $0.debtMiles < $1.debtMiles }) {
            events.append(MileMarkersReport.Event(date: low.date, kind: .lowPoint(miles: low.debtMiles)))
        }

        return Array(events.sorted { $0.date < $1.date }.prefix(4))
    }

    /// First day of each streak that reached two days, with how long it ran.
    static func streakStarts(days: [MileMarkersReport.Day], streak: StreakStatus, calendar: Calendar) -> [(day: Date, length: Int)] {
        var result: [(day: Date, length: Int)] = []
        var runStart: Date?
        var length = 0
        for day in days {
            let counts = day.qualifies || day.frozen
            if counts {
                if runStart == nil { runStart = day.date }
                if day.qualifies { length += 1 }
            } else {
                if let s = runStart, length >= 2 { result.append((s, length)) }
                runStart = nil
                length = 0
            }
        }
        if let s = runStart, length >= 2 { result.append((s, length)) }
        return result
    }
}
