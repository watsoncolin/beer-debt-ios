import Foundation

/// One local calendar day in the streak history.
struct StreakDay: Equatable, Sendable {
    /// Start of the day in the calendar the status was computed with.
    let day: Date
    let miles: Double
    /// At least a mile of verified running that day.
    let qualifies: Bool
    /// 1 on the first qualifying day of a run of days, counting up; 0 if the day doesn't qualify.
    /// A frozen day keeps the number it inherited, so the streak reads unbroken
    /// without the day being counted as running.
    let streakNumber: Int
    /// Interest postings on this day are skipped: it qualifies and so did the
    /// day before, or a freeze is holding it.
    let interestProtected: Bool
    /// A freeze was spent here: the day did not qualify on its own, and the
    /// streak survives it (spec §25.1). Never true on a day that qualifies --
    /// a late import that brings the day to a mile refunds the freeze instead.
    let frozen: Bool

    /// A day that counts as running. Frozen days deliberately do not: they earn
    /// no mileage, no repayment, no credit, and no progress toward the next freeze.
    var isRunningDay: Bool { qualifies }
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

    /// Freezes in hand: 0 or 1, never more (spec §25.1).
    let freezesHeld: Int
    /// Qualifying running days banked toward the next freeze, 0..<`daysPerFreeze`.
    /// Stays at 0 while a freeze is held: holding one stops the next accruing.
    let freezeProgressDays: Int
    /// Today is a rest day paid for with a freeze.
    let todayFrozen: Bool
    /// The day a retrospective freeze would repair: the first missed day that
    /// broke the streak that was alive before it, and only when that is the
    /// single break (one freeze cannot repair two days). Nil when there is
    /// nothing to repair or no freeze to spend.
    let repairableDay: Date?

    /// Offer "Use Freeze Today": a freeze in hand, a streak alive to protect,
    /// and today's mile not yet run (spec §25.1). Never consumed automatically.
    var canFreezeToday: Bool {
        freezesHeld > 0 && !todayQualifies && !todayFrozen && currentStreakDays >= 1
    }

    let calendar: Calendar

    private var index: [Date: Int] { Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.day, $0) }) }

    func day(on date: Date) -> StreakDay? {
        let key = calendar.startOfDay(for: date)
        return days.first { $0.day == key }
    }

    func qualifies(on date: Date) -> Bool { day(on: date)?.qualifies ?? false }
    func isProtected(on date: Date) -> Bool { day(on: date)?.interestProtected ?? false }
    func isFrozen(on date: Date) -> Bool { day(on: date)?.frozen ?? false }

    /// Which day of a streak `date` was, counting only streaks that reached
    /// two days: a lone mile is day one of nothing yet, so it gets no number
    /// until the next day qualifies.
    func streakDayNumber(on date: Date) -> Int? {
        let key = calendar.startOfDay(for: date)
        guard let i = days.firstIndex(where: { $0.day == key }), days[i].qualifies else { return nil }
        if days[i].streakNumber >= 2 { return days[i].streakNumber }
        let continued = i + 1 < days.count && days[i + 1].streakNumber == 2
        return continued ? 1 : nil
    }

    static func none(calendar: Calendar) -> StreakStatus {
        StreakStatus(days: [], currentStreakDays: 0, longestStreakDays: 0, totalQualifyingDays: 0,
                     todayMiles: 0, todayQualifies: false, todayProtected: false,
                     freezesHeld: 0, freezeProgressDays: 0, todayFrozen: false, repairableDay: nil,
                     calendar: calendar)
    }
}

enum StreakEngine {
    /// A mile, less a metre of GPS slack: a watch that says 1.00 mi counts.
    static let qualifyingMeters = RunEntry.metersPerMile - 1.0

    /// Pure. Groups the runs that ended by `now` into local calendar days,
    /// sums their distance, and walks the days in order. Runs that ended before
    /// the books opened are the caller's business (the balance engine drops
    /// them); everything passed in counts.
    /// Qualifying running days that earn one freeze (spec §25.1).
    static let daysPerFreeze = 5
    /// Never more than one in hand.
    static let maximumFreezes = 1

    static func calculate(
        runs: [RunEntry],
        freezeApplications: [FreezeApplication] = [],
        at now: Date,
        calendar: Calendar
    ) -> StreakStatus {
        let counted = runs.filter { $0.endedAt <= now }
        let today = calendar.startOfDay(for: now)
        // Applications are keyed by start-of-day so they survive a device whose
        // clock or zone moved between the tap and the replay.
        var appliedDays = Set(freezeApplications.map { calendar.startOfDay(for: $0.day) })
        appliedDays = appliedDays.filter { $0 <= today }
        guard !counted.isEmpty || !appliedDays.isEmpty else { return .none(calendar: calendar) }

        var metersByDay: [Date: Double] = [:]
        for run in counted {
            metersByDay[calendar.startOfDay(for: run.endedAt), default: 0] += run.distanceMeters
        }
        let firstDay = min(metersByDay.keys.min() ?? today, appliedDays.min() ?? today, today)

        var days: [StreakDay] = []
        var cursor = firstDay
        var previous: StreakDay?
        // Freeze inventory as of the day being walked. Both are derived here
        // and never stored, so a deleted or late-imported run simply changes
        // the answer -- the same contract the streak itself has always had.
        var held = 0
        var progress = 0

        while cursor <= today {
            let meters = metersByDay[cursor] ?? 0
            let qualifies = meters >= qualifyingMeters
            // A day that qualifies on its own never spends a freeze. This is
            // the refund: late HealthKit data brings the day to a mile, the
            // application stops being honoured, and the freeze is back.
            let frozen = !qualifies && appliedDays.contains(cursor) && held > 0

            let number: Int
            if qualifies {
                number = (previous?.streakNumber ?? 0) > 0 && (previous?.qualifies ?? false) || (previous?.frozen ?? false)
                    ? (previous?.streakNumber ?? 0) + 1
                    : 1
            } else if frozen {
                // Continuity without credit: the streak keeps its length.
                number = previous?.streakNumber ?? 0
            } else {
                number = 0
            }

            let carriedProtection = (previous?.streakNumber ?? 0) >= 2 || (qualifies && number >= 2)
            let entry = StreakDay(
                day: cursor,
                miles: meters / RunEntry.metersPerMile,
                qualifies: qualifies,
                streakNumber: number,
                interestProtected: (qualifies && number >= 2) || (frozen && carriedProtection),
                frozen: frozen
            )
            days.append(entry)

            if frozen {
                // Spent. The next one needs five new running days.
                held = 0
                progress = 0
            } else if qualifies, held < maximumFreezes {
                // Holding one stops the next accruing, so nothing is banked
                // secretly. Progress is cumulative running days, not a streak:
                // a break costs the streak, not the freeze being worked toward.
                progress += 1
                if progress >= daysPerFreeze {
                    held = maximumFreezes
                    progress = 0
                }
            }

            previous = entry
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        let todayEntry = days.last!
        let yesterday = days.count >= 2 ? days[days.count - 2] : nil
        let current = todayEntry.qualifies || todayEntry.frozen
            ? todayEntry.streakNumber
            : (yesterday?.streakNumber ?? 0)

        return StreakStatus(
            days: days,
            currentStreakDays: current,
            longestStreakDays: days.map(\.streakNumber).max() ?? 0,
            totalQualifyingDays: days.filter(\.qualifies).count,
            todayMiles: todayEntry.miles,
            todayQualifies: todayEntry.qualifies,
            todayProtected: todayEntry.interestProtected,
            freezesHeld: held,
            freezeProgressDays: progress,
            todayFrozen: todayEntry.frozen,
            repairableDay: repairable(days: days, held: held, calendar: calendar),
            calendar: calendar
        )
    }

    /// The single missed day a freeze in hand could repair.
    ///
    /// Only the first day that broke the streak, and only when it is the only
    /// break: one freeze protects one day, so if the day after is also missed
    /// the streak breaks there anyway and repairing the first buys nothing.
    private static func repairable(days: [StreakDay], held: Int, calendar: Calendar) -> Date? {
        guard held > 0, days.count >= 2 else { return nil }
        // Walk back over the days already accounted for to find the break that
        // ended the last streak, skipping today (which is not a miss yet).
        let history = days.dropLast()
        guard let breakIndex = history.lastIndex(where: { !$0.qualifies && !$0.frozen }) else { return nil }
        // The streak it broke has to have been worth protecting.
        let before = breakIndex > history.startIndex ? history[history.index(before: breakIndex)] : nil
        guard let before, before.qualifies || before.frozen, before.streakNumber >= 1 else { return nil }
        // Every day since the break must already count, or one freeze is not enough.
        let after = history[history.index(after: breakIndex)...]
        guard after.allSatisfy({ $0.qualifies || $0.frozen }) else { return nil }
        return history[breakIndex].day
    }
}
