import Foundation

/// How often debt interest posts (spec §5; the concept art shows whole-day
/// steps: 1.00 → 1.10 → 1.21 → 1.46). Periods are fixed lengths in seconds,
/// not calendar days, so a beer at 8 PM posts at 8 PM the next day (drifting an
/// hour across a DST change). Deterministic and time-zone independent.
enum CompoundingPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    /// "10% a day"
    var perLabel: String {
        switch self {
        case .daily: "a day"
        case .weekly: "a week"
        }
    }
}

/// The user-tunable rules (spec §2, §13). "Settings" in the spec; named `Rules`
/// to match the product copy ("Tune the rules") and avoid SwiftUI's `Settings`.
///
/// Rule changes are forward-only: they are recorded as `RulesChange` events in
/// the ledger and apply from that instant on. Nothing already posted is ever
/// recalculated (docs/decisions.md §B).
struct Rules: Codable, Hashable, Sendable {
    /// Cost of one beer, in miles.
    var milesPerBeer: Double = 1.0
    /// Interest per compounding period on the outstanding amount. 0.10 = 10%. 0 = off.
    var interestRate: Double = 0.10
    var interestPeriod: CompoundingPeriod = .daily
    /// Seconds after a beer before interest can post. 0 = none.
    var gracePeriod: TimeInterval = 24 * 60 * 60
    /// Cap on banked credit, in beers. Running beyond it is discarded (spec §8).
    var maximumCreditBeers: Double = 3
    /// Fraction of banked credit lost per week, applied continuously. 0 = off (spec §9).
    var creditDecayRatePerWeek: Double = 0.10

    static let `default` = Rules()

    var interestEnabled: Bool { interestRate > 0 }
    var creditDecayEnabled: Bool { creditDecayRatePerWeek > 0 }
    var creditCapMiles: Double { maximumCreditBeers * milesPerBeer }

    /// Delay from a beer to its first interest posting. Interest can post
    /// neither before the grace period ends nor before a full period has
    /// elapsed. With the defaults (24 h grace, daily) that is exactly 24 h.
    var firstPostingDelay: TimeInterval { max(gracePeriod, interestPeriod.seconds) }
}
