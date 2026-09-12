import Foundation
import Observation

/// Owns the persisted event ledger (beers, runs, rules) and exposes the derived
/// balance to the UI. Local-first: a single JSON file in Application Support,
/// written atomically (spec §15, §16). Views never touch the engine directly.
@MainActor
@Observable
final class LedgerStore {
    private(set) var beers: [BeerEntry] = []
    private(set) var runs: [RunEntry] = []
    var rules: Rules = .default

    func balance(at now: Date = .now) -> Balance {
        BalanceEngine.calculateBalance(beers: beers, runs: runs, rules: rules, at: now)
    }

    /// Records one beer immediately, no confirmation (spec §3).
    func addBeer(at date: Date = .now) {
        // TODO: append BeerEntry(createdAt:rules:) and save.
    }

    /// Idempotent: returns false if this HealthKit workout was already imported.
    @discardableResult
    func importRun(_ run: RunEntry) -> Bool {
        // TODO: dedup on healthKitWorkoutID, append, save.
        return false
    }

    // TODO: load()/save() — Codable snapshot { beers, runs, rules } to
    // Application Support/ledger.json, atomic write.
}
