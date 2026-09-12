import Foundation

/// Pure, deterministic ledger replay. No I/O, no clocks — `now` is injected.
///
/// Rebuilding from the same events at the same instant must always produce the
/// same `Balance` (acceptance criterion 16). See docs/spec.md §5–§9, §17 and the
/// accounting decisions in docs/decisions.md.
///
/// Planned algorithm (not yet implemented):
///   1. Merge beers (at `createdAt`) and runs (at `endedAt`) into one timeline.
///   2. Fold chronologically, carrying open debts (FIFO by createdAt) and a
///      single credit pool. Before each event, accrue interest steps on every
///      open debt and decay the credit pool up to that event's time.
///   3. Beer: consume credit first, remainder opens a debt at the beer's
///      snapshotted milesPerBeer.
///   4. Run: pay oldest debt first (interest, then principal); leftover miles
///      become credit up to the cap; excess is discarded.
///   5. Accrue/decay once more up to `now` and summarise.
enum BalanceEngine {
    static func calculateBalance(
        beers: [BeerEntry],
        runs: [RunEntry],
        rules: Rules,
        at now: Date
    ) -> Balance {
        // TODO: implement replay per the plan above.
        return .even
    }
}
