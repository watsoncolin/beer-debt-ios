import Foundation

/// One beer, recorded at the moment it was consumed. Immutable event.
///
/// The miles-per-beer rule and the interest terms are snapshotted here so later
/// settings changes don't rewrite history (spec §16). Whether this beer was
/// covered by credit or became debt is NOT stored — the engine works that out
/// during replay, which keeps the ledger deterministic (spec §5, §17).
struct BeerEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let milesPerBeer: Double
    let interestTerms: InterestTerms

    init(id: UUID = UUID(), createdAt: Date, rules: Rules) {
        self.id = id
        self.createdAt = createdAt
        self.milesPerBeer = rules.milesPerBeer
        self.interestTerms = rules.interest
    }
}
