import Foundation

/// A rules change, effective from `effectiveAt` forward.
struct RulesChange: Codable, Hashable, Sendable {
    let effectiveAt: Date
    let rules: Rules
}

/// The whole persisted state: an append-only event log plus the instant the
/// books were opened. Everything the UI shows is derived from this by
/// `BalanceEngine` (spec §15–§17).
struct Ledger: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// First launch. Runs that ended before this are ignored: the books open at zero.
    var booksOpenedAt: Date
    /// Sorted by `effectiveAt`. The first entry is the opening rules.
    var rulesHistory: [RulesChange]
    var beers: [BeerEntry]
    var runs: [RunEntry]
    /// HealthKit workouts the user took off the books in the app. Kept so a
    /// re-sync from scratch (reinstall, anchor reset) doesn't bring them back.
    var excludedWorkoutIDs: Set<UUID>
    /// Days the user spent a streak freeze on (spec §25.1). The only freeze
    /// state stored; everything else about freezes is derived from the runs.
    var freezeApplications: [FreezeApplication]

    init(openedAt: Date, rules: Rules = .default) {
        version = Self.currentVersion
        booksOpenedAt = openedAt
        rulesHistory = [RulesChange(effectiveAt: openedAt, rules: rules)]
        beers = []
        runs = []
        excludedWorkoutIDs = []
        freezeApplications = []
    }

    private enum CodingKeys: String, CodingKey {
        case version, booksOpenedAt, rulesHistory, beers, runs, excludedWorkoutIDs, freezeApplications
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        booksOpenedAt = try c.decode(Date.self, forKey: .booksOpenedAt)
        rulesHistory = try c.decode([RulesChange].self, forKey: .rulesHistory)
        beers = try c.decode([BeerEntry].self, forKey: .beers)
        runs = try c.decode([RunEntry].self, forKey: .runs)
        excludedWorkoutIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .excludedWorkoutIDs) ?? []
        // Absent in every ledger written before freezes existed.
        freezeApplications = try c.decodeIfPresent([FreezeApplication].self, forKey: .freezeApplications) ?? []
    }

    var currentRules: Rules { rulesHistory.last?.rules ?? .default }

    func rules(at instant: Date) -> Rules {
        rulesHistory.last(where: { $0.effectiveAt <= instant })?.rules
            ?? rulesHistory.first?.rules
            ?? .default
    }

    func containsRun(healthKitWorkoutID id: UUID) -> Bool {
        runs.contains { $0.healthKitWorkoutID == id }
    }
}

extension Date {
    /// Event timestamps are whole seconds so the ledger round-trips through
    /// ISO 8601 exactly and a reload replays to the identical balance.
    var flooredToSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
