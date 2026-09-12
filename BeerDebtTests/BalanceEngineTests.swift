import Foundation
import Testing
@testable import BeerDebt

/// Engine tests (spec §17). Every case uses fixed instants — never `Date.now` —
/// so results are reproducible and can be mirrored as JSON fixtures for the
/// Android port.
struct BalanceEngineTests {
    /// 2026-09-12 20:00:00 UTC — a Saturday night at the bar.
    let t0 = Date(timeIntervalSince1970: 1_789_243_200)

    @Test func freshLedgerIsEven() {
        let balance = BalanceEngine.calculateBalance(beers: [], runs: [], rules: .default, at: t0)
        #expect(balance == .even)
    }

    // Planned coverage (spec §17), one @Test each once the engine lands:
    //   one beer → 1.0 mi debt · multiple beers · FIFO repayment · partial repayment
    //   grace period · interest steps · credit generation · credit cap · credit decay
    //   partial credit consumption · credit→debt · debt→credit · settings snapshot
    //   duplicate HealthKit workout · late-imported run is applied at its own time
    //   time-zone / DST boundaries
}
