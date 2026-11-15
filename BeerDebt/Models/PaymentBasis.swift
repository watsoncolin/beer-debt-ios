import Foundation

/// What pays down the tab (spec §28).
enum PaymentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Running workouts, by distance. The default.
    case runs
    /// Every workout: runs by distance, everything else by active energy.
    case calories

    var id: String { rawValue }
}

/// The mode and the calorie rate together: everything the engine needs to
/// turn a workout into miles paid.
///
/// Not a rule. Rules are forward-only; this reinterprets the whole ledger
/// on every replay (decisions §B.10), which is why it lives on `Ledger`
/// beside the rules history rather than inside it.
struct PaymentBasis: Hashable, Sendable {
    /// About what a mile of running burns, so a beer costs the same effort in
    /// either mode.
    static let defaultCaloriesPerMile = 100.0
    static let runs = PaymentBasis()

    var mode: PaymentMode = .runs
    /// Calories worth one mile. Converts a non-run workout's energy into
    /// miles on the way in and every amount into calories on the way out.
    var caloriesPerMile: Double = defaultCaloriesPerMile

    /// Miles this workout pays, or nil if it doesn't count in this mode.
    ///
    /// A run pays its distance in both modes, so a mile is worth the same
    /// either way and a run never depends on its source recording energy.
    /// Anything else pays nothing in runs mode, and its active energy at the
    /// calorie rate in calorie mode (zero if none was recorded).
    func miles(paidBy workout: RunEntry) -> Double? {
        if workout.isRunning { return workout.distanceMiles }
        guard mode == .calories else { return nil }
        guard caloriesPerMile > 0 else { return 0 }
        return (workout.activeEnergyKcal ?? 0) / caloriesPerMile
    }
}
