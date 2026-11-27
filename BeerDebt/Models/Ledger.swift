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
    /// What pays the tab, and at what calorie rate (spec §28). Sorted by
    /// `effectiveAt`; the first entry is the opening basis. Forward-only like
    /// `rulesHistory`: a workout pays under the entry in force when it ended
    /// (decisions §B.10).
    var paymentHistory: [PaymentChange]

    init(openedAt: Date, rules: Rules = .default, payment: PaymentBasis = .runs) {
        version = Self.currentVersion
        booksOpenedAt = openedAt
        rulesHistory = [RulesChange(effectiveAt: openedAt, rules: rules)]
        beers = []
        runs = []
        excludedWorkoutIDs = []
        freezeApplications = []
        paymentHistory = [PaymentChange(effectiveAt: openedAt, payment: payment)]
    }

    private enum CodingKeys: String, CodingKey {
        case version, booksOpenedAt, rulesHistory, beers, runs, excludedWorkoutIDs, freezeApplications,
             paymentHistory
        // Written by 1.2, when the basis reinterpreted the whole history. Read only.
        case paymentMode, caloriesPerMile
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(booksOpenedAt, forKey: .booksOpenedAt)
        try c.encode(rulesHistory, forKey: .rulesHistory)
        try c.encode(beers, forKey: .beers)
        try c.encode(runs, forKey: .runs)
        try c.encode(excludedWorkoutIDs, forKey: .excludedWorkoutIDs)
        try c.encode(freezeApplications, forKey: .freezeApplications)
        try c.encode(paymentHistory, forKey: .paymentHistory)
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
        if let history = try c.decodeIfPresent([PaymentChange].self, forKey: .paymentHistory), !history.isEmpty {
            paymentHistory = history
        } else {
            // 1.2 kept one basis and replayed everything under it, so it has
            // been in force since the books opened: the numbers don't move on
            // upgrade. Before calorie mode there was none: runs, at the default rate.
            let legacy = PaymentBasis(
                mode: try c.decodeIfPresent(PaymentMode.self, forKey: .paymentMode) ?? .runs,
                caloriesPerMile: try c.decodeIfPresent(Double.self, forKey: .caloriesPerMile)
                    ?? PaymentBasis.defaultCaloriesPerMile
            )
            paymentHistory = [PaymentChange(effectiveAt: booksOpenedAt, payment: legacy)]
        }
    }

    /// The basis in force now: what Settings shows and what amounts display in.
    ///
    /// Setting it replaces the history with this basis from the day the books
    /// opened. That is right only when nothing has been paid yet (onboarding)
    /// and for fixtures; a switch on live books goes through
    /// `LedgerStore.updatePayment`, which appends.
    var payment: PaymentBasis {
        get { paymentHistory.last?.payment ?? .runs }
        set { paymentHistory = [PaymentChange(effectiveAt: booksOpenedAt, payment: newValue)] }
    }

    var paymentMode: PaymentMode { payment.mode }
    var caloriesPerMile: Double { payment.caloriesPerMile }

    /// The basis a workout that ended at `instant` pays under.
    func payment(at instant: Date) -> PaymentBasis {
        paymentHistory.last(where: { $0.effectiveAt <= instant })?.payment
            ?? paymentHistory.first?.payment
            ?? .runs
    }

    /// Miles this workout pays under the basis in force when it ended, or nil
    /// if that basis doesn't count it.
    func miles(paidBy workout: RunEntry) -> Double? {
        payment(at: workout.endedAt).miles(paidBy: workout)
    }

    /// Whether calorie mode has ever been in force. Once it has, Health is
    /// read for every workout type whatever the mode now, so a ride that ended
    /// in calorie mode but syncs after a switch back still lands, and its
    /// deletion is still seen.
    var hasCaloriePeriod: Bool { paymentHistory.contains { $0.mode == .calories } }

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
