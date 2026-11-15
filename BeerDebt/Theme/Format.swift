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

    /// Short enough for a stat tile. The tab compounds at 10% a day by default
    /// (decisions §A.1), so a few unpaid months reach five and six figures and
    /// the full number stops being readable long before it stops being true.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return number(value / 1_000_000, decimals: magnitude < 10_000_000 ? 1 : 0) + "M"
        case 10_000...:
            return number(value / 1_000, decimals: 0) + "k"
        case 1_000...:
            return number(value / 1_000, decimals: 1) + "k"
        default:
            return number(value, decimals: magnitude < 100 ? 1 : 0)
        }
    }

    /// `compact`, with the unit.
    static func compactMiles(_ value: Double) -> String { compact(value) + " mi" }

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

/// How amounts read on screen: miles, or calories at the ledger's rate
/// (spec §28). The engine works in miles either way; this is the one place
/// they become calories, so views pass it miles and never multiply.
///
/// Calories are whole numbers. At the default rate they are about 100× the
/// mile figure, so a decimal would be noise and the compact forms engage at
/// four figures, not five.
struct Units: Equatable, Sendable {
    var payment: PaymentBasis

    static let miles = Units(payment: .runs)

    init(payment: PaymentBasis) { self.payment = payment }

    var isCalories: Bool { payment.mode == .calories }

    /// "mi" / "kcal"
    var symbol: String { isCalories ? "kcal" : "mi" }
    /// "miles" / "calories", for VoiceOver and running copy.
    var word: String { isCalories ? "calories" : "miles" }

    /// The display value for an engine amount.
    func value(_ miles: Double) -> Double { isCalories ? miles * payment.caloriesPerMile : miles }

    /// Bare number: miles at `decimals`, calories whole.
    func number(_ miles: Double, decimals: Int = 1) -> String {
        isCalories ? Format.number(value(miles), decimals: 0) : Format.number(miles, decimals: decimals)
    }

    /// "2.3 mi" / "230 kcal"
    func amount(_ miles: Double, decimals: Int = 1) -> String { number(miles, decimals: decimals) + " " + symbol }

    /// Short enough for a stat tile: "4.8k", "1.2M". Calories stay whole under a thousand.
    func compact(_ miles: Double) -> String {
        let shown = value(miles)
        if isCalories, abs(shown) < 1_000 { return Format.number(shown, decimals: 0) }
        return Format.compact(shown)
    }

    /// `compact`, with the unit.
    func compactAmount(_ miles: Double) -> String { compact(miles) + " " + symbol }

    // MARK: Words

    /// What a single workout is called: "run" / "workout".
    var workout: String { isCalories ? "workout" : "run" }
    /// "Runs" / "Workouts", for the screen and its rows.
    var workoutsTitle: String { isCalories ? "Workouts" : "Runs" }
    /// Past tense of the effort: "run" / "burned", as in "4.2 mi run this week".
    var effortPast: String { isCalories ? "burned" : "run" }
    /// How the tab is paid off: "Run it off" / "Burn it off".
    var payOffPhrase: String { isCalories ? "Burn it off" : "Run it off" }
    /// The verb: "run" / "work out", as in "if you run today".
    var verb: String { isCalories ? "work out" : "run" }
    /// A day that counts toward the streak: "running day" / "workout day".
    var activeDay: String { isCalories ? "workout day" : "running day" }
    /// The streak's daily bar, one mile's worth (spec §25, §28): "Run 1+ mile" / "Burn 100+ kcal".
    var dailyGoal: String { isCalories ? "Burn \(number(1))+ kcal" : "Run 1+ mile" }
    /// "Keep running 1+ mile" / "Keep burning 100+ kcal".
    var keepGoing: String { isCalories ? "Keep burning \(number(1))+ kcal" : "Keep running 1+ mile" }
    /// SF Symbol for the workouts card and empty states.
    var workoutSymbol: String { isCalories ? "figure.mixed.cardio" : "figure.run" }
}

extension Report {
    /// Miles from counted workouts that ended in the same calendar week as
    /// `now`: a run's distance, or a ride's calories at the rate.
    func milesRun(inWeekOf now: Date, calendar: Calendar = .current) -> Double {
        runs
            .filter { !$0.ignored && calendar.isDate($0.run.endedAt, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.paidMiles }
    }
}
