import Foundation
@testable import BeerDebt

let hour: TimeInterval = 3_600
let day: TimeInterval = 86_400
let week: TimeInterval = 7 * day

/// 2026-09-12 20:00:00 UTC, a Saturday night at the bar.
let t0 = Date(timeIntervalSince1970: 1_789_243_200)

func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

func ledger(rules: Rules = .default, openedAt: Date = t0, beers: [BeerEntry] = [], runs: [RunEntry] = []) -> Ledger {
    var ledger = Ledger(openedAt: openedAt, rules: rules)
    ledger.beers = beers
    ledger.runs = runs
    return ledger
}

func beer(_ date: Date) -> BeerEntry { BeerEntry(createdAt: date) }

func run(_ miles: Double, endedAt: Date, workoutID: UUID = UUID(), importedAt: Date? = nil) -> RunEntry {
    RunEntry(
        healthKitWorkoutID: workoutID,
        startedAt: endedAt.addingTimeInterval(-30 * 60),
        endedAt: endedAt,
        distanceMeters: miles * RunEntry.metersPerMile,
        importedAt: importedAt ?? endedAt,
        sourceName: "Test"
    )
}

/// Every test replays in UTC so streak days don't depend on the machine's zone.
var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

func report(_ ledger: Ledger, at date: Date, calendar: Calendar = utc) -> Report {
    BalanceEngine.report(for: ledger, at: date, calendar: calendar)
}

var noStreak: Rules {
    var rules = Rules.default
    rules.streakProtection = false
    return rules
}

func close(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

var noDecay: Rules {
    var rules = Rules.default
    rules.creditDecayRatePerWeek = 0
    return rules
}

func withChange(_ base: Ledger, at date: Date, _ mutate: (inout Rules) -> Void) -> Ledger {
    var ledger = base
    var rules = ledger.currentRules
    mutate(&rules)
    ledger.rulesHistory.append(RulesChange(effectiveAt: date, rules: rules))
    return ledger
}
