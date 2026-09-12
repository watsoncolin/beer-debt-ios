import Foundation

enum BalanceState: Sendable {
    case credit
    case even
    case debt
}

/// The engine's output for a given instant (spec §17). All miles.
struct Balance: Equatable, Sendable {
    var state: BalanceState
    /// principal + interest still owed
    var debtMiles: Double
    var principalMiles: Double
    var interestMiles: Double
    /// banked credit, after decay
    var creditMiles: Double
    /// creditMiles expressed in beers at the current miles-per-beer rule
    var creditBeers: Double

    static let even = Balance(
        state: .even, debtMiles: 0, principalMiles: 0, interestMiles: 0, creditMiles: 0, creditBeers: 0
    )
}
