import Foundation

/// How often debt interest compounds. Interest is applied in discrete steps at
/// period boundaries after the grace period ends (spec §5; concept art shows
/// whole-day steps: 1.00 → 1.10 → 1.21 → 1.46).
enum CompoundingPeriod: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly

    var seconds: TimeInterval {
        switch self {
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        }
    }
}

/// Interest terms for a single beer debt. Snapshotted onto each `BeerEntry` at
/// creation so changing the rules later never rewrites existing debt (spec §16).
struct InterestTerms: Codable, Hashable, Sendable {
    /// Seconds after `createdAt` before interest starts. 0 = no grace period.
    var gracePeriod: TimeInterval
    /// Fraction per compounding period. 0.10 = 10%. 0 = interest disabled.
    var rate: Double
    var period: CompoundingPeriod
}

/// The user-tunable rules (spec §2, §13). "Settings" in the spec; named `Rules`
/// here to match the product copy ("Tune the rules") and avoid clashing with
/// SwiftUI's `Settings` scene.
struct Rules: Codable, Hashable, Sendable {
    var milesPerBeer: Double = 1.0
    // OPEN DECISION (docs/decisions.md #1): spec table says 10%/week, but every
    // worked example and the concept art imply 10%/day. Defaulting to the table
    // until decided — this is a one-line change.
    var interest = InterestTerms(gracePeriod: 24 * 60 * 60, rate: 0.10, period: .weekly)
    /// Cap on banked credit, in beers. Running beyond this is discarded (spec §8).
    var maximumCreditBeers: Double = 3
    /// Fraction of banked credit lost per week. 0 = decay disabled (spec §9).
    var creditDecayRatePerWeek: Double = 0.10

    static let `default` = Rules()
}
