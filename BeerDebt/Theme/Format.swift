import Foundation

/// Display formatting. Miles get one decimal on Home and two in the Ledger;
/// beers read naturally ("2", "2.5").
enum Format {
    static func number(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    static func miles(_ value: Double, decimals: Int = 1) -> String {
        number(value, decimals: decimals) + " mi"
    }

    static func beers(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func beersLabel(_ value: Double) -> String {
        let text = beers(value)
        return text + (text == "1" ? " beer" : " beers")
    }

    static func percent(_ rate: Double) -> String {
        rate.formatted(.percent.precision(.fractionLength(0)))
    }

    static func gracePeriod(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "None" }
        let hours = seconds / 3_600
        if hours < 48 { return "\(Int(hours)) hours" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// "today", "1 day old", "5 days old"
    static func age(from start: Date, to end: Date) -> String {
        let days = Int(end.timeIntervalSince(start) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "1 day old"
        default: return "\(days) days old"
        }
    }

    /// "Sep 9, 8:13 PM"
    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// "8:13 PM"
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Sep 9"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Today", "Yesterday", "Tuesday, Sep 9"
    static func dayHeader(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// How dear a paid beer turned out to be, by the miles actually run to
    /// clear it. Thresholds are absolute miles, not a multiple of the price,
    /// because what the reader is judging is the run they had to go on.
    ///
    /// Pure and shared by both platforms, so the bands cannot drift apart.
    enum PaidSeverity: Equatable, Sendable {
        /// About what a beer should cost.
        case ordinary
        /// It sat long enough to matter.
        case dear
        /// It got away.
        case steep

        static let dearMiles = 2.0
        static let steepMiles = 3.0

        init(milesRun: Double) {
            switch milesRun {
            case Self.steepMiles...: self = .steep
            case Self.dearMiles...: self = .dear
            default: self = .ordinary
            }
        }
    }

    /// "yesterday", "Tuesday", "Sep 9" — the day named mid-sentence, so it
    /// stays lowercase where `dayHeader` is capitalised for a header.
    static func dayPhrase(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        // Within the last week a weekday is clearer than a date.
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: now), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return day(date)
    }

    /// "today at 8:13 PM", "tomorrow at 8:13 PM", "Sep 14 at 8:13 PM"
    static func relative(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let clock = time(date)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(clock)"
        }
        return "\(day(date)) at \(clock)"
    }
}

extension Report {
    /// Miles from counted runs that ended in the same calendar week as `now`.
    func milesRun(inWeekOf now: Date, calendar: Calendar = .current) -> Double {
        runs
            .filter { !$0.ignored && calendar.isDate($0.run.endedAt, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.run.distanceMiles }
    }
}
