import Foundation

/// One local calendar day in the streak history.
struct StreakDay: Equatable, Sendable {
    /// Start of the day in the calendar the status was computed with.
    let day: Date
    let miles: Double
    /// At least a mile of verified running that day.
    let qualifies: Bool
    /// 1 on the first qualifying day of a run of days, counting up; 0 if the day doesn't qualify.
    let streakNumber: Int
    /// Interest postings on this day are skipped: it qualifies and so did the day before.
    let interestProtected: Bool
}

/// The running streak (docs/spec.md §25): a mile a day builds it, two days in a
/// row pauses debt interest. Derived from the runs on the books, never stored,
/// so a late HealthKit import or a deleted run simply changes the answer.
struct StreakStatus: Equatable, Sendable {
    /// Days from the first counted run through today, in order, no gaps.
    let days: [StreakDay]
    /// The streak that is alive right now: today's if today qualifies, else
    /// yesterday's (today can still be run), else 0.
    let currentStreakDays: Int
    let longestStreakDays: Int
    let totalQualifyingDays: Int
    let todayMiles: Double
    let todayQualifies: Bool
    /// Two or more days and still alive: the "0% APR — earned" state.
    var interestProtectionActive: Bool { currentStreakDays >= 2 }
    /// Today has already earned its protection (a posting today is skipped).
    let todayProtected: Bool
    let calendar: Calendar

    private var index: [Date: Int] { Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.day, $0) }) }

    func day(on date: Date) -> StreakDay? {
        let key = calendar.startOfDay(for: date)
        return days.first { $0.day == key }
    }

    func qualifies(on date: Date) -> Bool { day(on: date)?.qualifies ?? false }
    func isProtected(on date: Date) -> Bool { day(on: date)?.interestProtected ?? false }

    static func none(calendar: Calendar) -> StreakStatus {
        StreakStatus(days: [], currentStreakDays: 0, longestStreakDays: 0, totalQualifyingDays: 0,
                     todayMiles: 0, todayQualifies: false, todayProtected: false, calendar: calendar)
    }
}

enum StreakEngine {
    /// A mile, less a metre of GPS slack: a watch that says 1.00 mi counts.
    static let qualifyingMeters = RunEntry.metersPerMile - 1.0

    /// Pure. Groups the runs that ended by `now` into local calendar days,
    /// sums their distance, and walks the days in order. Runs that ended before
    /// the books opened are the caller's business (the balance engine drops
    /// them); everything passed in counts.
    static func calculate(runs: [RunEntry], at now: Date, calendar: Calendar) -> StreakStatus {
        let counted = runs.filter { $0.endedAt <= now }
        guard !counted.isEmpty else { return .none(calendar: calendar) }

        var metersByDay: [Date: Double] = [:]
        for run in counted {
            metersByDay[calendar.startOfDay(for: run.endedAt), default: 0] += run.distanceMeters
        }
        let today = calendar.startOfDay(for: now)
        let firstDay = min(metersByDay.keys.min()!, today)

        var days: [StreakDay] = []
        var cursor = firstDay
        var previous: StreakDay?
        while cursor <= today {
            let meters = metersByDay[cursor] ?? 0
            let qualifies = meters >= qualifyingMeters
            let number = qualifies ? ((previous?.qualifies ?? false) ? previous!.streakNumber + 1 : 1) : 0
            let entry = StreakDay(
                day: cursor,
                miles: meters / RunEntry.metersPerMile,
                qualifies: qualifies,
                streakNumber: number,
                interestProtected: qualifies && number >= 2
            )
            days.append(entry)
            previous = entry
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        let todayEntry = days.last!
        let yesterday = days.count >= 2 ? days[days.count - 2] : nil
        let current = todayEntry.qualifies ? todayEntry.streakNumber : (yesterday?.streakNumber ?? 0)
        return StreakStatus(
            days: days,
            currentStreakDays: current,
            longestStreakDays: days.map(\.streakNumber).max() ?? 0,
            totalQualifyingDays: days.filter(\.qualifies).count,
            todayMiles: todayEntry.miles,
            todayQualifies: todayEntry.qualifies,
            todayProtected: todayEntry.interestProtected,
            calendar: calendar
        )
    }
}
