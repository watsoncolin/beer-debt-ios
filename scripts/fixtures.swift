// Generates docs/engine-fixtures/cases.json: scenarios run through the Swift
// BalanceEngine, with the exact expected output. The Android engine (and any
// future port) must reproduce these numbers. Deterministic: fixed instants,
// sequential UUIDs, sorted keys.
//
//   scripts/fixtures.sh
import Foundation

let hour: TimeInterval = 3_600
let day: TimeInterval = 86_400
let week: TimeInterval = 7 * day
/// 2026-09-12 20:00:00 UTC, a Saturday night at the bar.
let t0 = Date(timeIntervalSince1970: 1_789_243_200)
func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

var nextID = 0
func uuid() -> UUID {
    nextID += 1
    return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", nextID))!
}

func ledger(rules: Rules = .default, openedAt: Date = t0, beers: [BeerEntry] = [], runs: [RunEntry] = []) -> Ledger {
    var l = Ledger(openedAt: openedAt, rules: rules)
    l.beers = beers
    l.runs = runs
    return l
}
func beer(_ date: Date, recordedAt: Date? = nil) -> BeerEntry { BeerEntry(id: uuid(), createdAt: date, recordedAt: recordedAt) }
func run(_ miles: Double, endedAt: Date, importedAt: Date? = nil) -> RunEntry {
    RunEntry(id: uuid(), healthKitWorkoutID: uuid(), startedAt: endedAt.addingTimeInterval(-30 * 60), endedAt: endedAt,
             distanceMeters: miles * RunEntry.metersPerMile, importedAt: importedAt ?? endedAt, sourceName: "Fixture")
}
var noDecay: Rules { var r = Rules.default; r.creditDecayRatePerWeek = 0; return r }
func withChange(_ base: Ledger, at date: Date, _ mutate: (inout Rules) -> Void) -> Ledger {
    var l = base; var rules = l.currentRules; mutate(&rules)
    l.rulesHistory.append(RulesChange(effectiveAt: date, rules: rules)); return l
}

// MARK: - Expected output shape (mirrors Report, but Codable)

struct ExpectedBeer: Codable {
    let id: UUID, number: Int, createdAt: Date, costMiles: Double, coveredByCreditMiles: Double, principalMiles: Double
    let interestAccruedMiles: Double, paidMiles: Double, principalRemainingMiles: Double, interestRemainingMiles: Double
    let writtenOffMiles: Double, paidAt: Date?, nextInterestAt: Date?
    init(_ s: BeerStatement) {
        id = s.id; number = s.number; createdAt = s.createdAt; costMiles = s.costMiles; coveredByCreditMiles = s.coveredByCreditMiles
        principalMiles = s.principalMiles; interestAccruedMiles = s.interestAccruedMiles; paidMiles = s.paidMiles
        principalRemainingMiles = s.principalRemainingMiles; interestRemainingMiles = s.interestRemainingMiles
        writtenOffMiles = s.writtenOffMiles; paidAt = s.paidAt; nextInterestAt = s.nextInterestAt
    }
}
struct ExpectedRun: Codable {
    let id: UUID, debtPaidMiles: Double, creditEarnedMiles: Double, discardedMiles: Double, ignored: Bool
    init(_ s: RunStatement) { id = s.id; debtPaidMiles = s.debtPaidMiles; creditEarnedMiles = s.creditEarnedMiles; discardedMiles = s.discardedMiles; ignored = s.ignored }
}
struct ExpectedBalance: Codable {
    let state: String, debtMiles: Double, principalMiles: Double, interestMiles: Double, creditMiles: Double, creditBeers: Double
    init(_ b: Balance) {
        state = { switch b.state { case .debt: "debt"; case .credit: "credit"; case .even: "even" } }()
        debtMiles = b.debtMiles; principalMiles = b.principalMiles; interestMiles = b.interestMiles; creditMiles = b.creditMiles; creditBeers = b.creditBeers
    }
}
struct Expected: Codable {
    let balance: ExpectedBalance, beers: [ExpectedBeer], runs: [ExpectedRun], nextInterestAt: Date?, creditExpiringThisWeekMiles: Double
    init(_ r: Report) { balance = .init(r.balance); beers = r.beers.map(ExpectedBeer.init); runs = r.runs.map(ExpectedRun.init); nextInterestAt = r.nextInterestAt; creditExpiringThisWeekMiles = r.creditExpiringThisWeekMiles }
}
struct Case: Codable { let name: String, now: Date, ledger: Ledger, expected: Expected }
struct Fixtures: Codable { let version: Int, tolerance: Double, note: String, cases: [Case] }

var cases: [Case] = []
func add(_ name: String, _ l: Ledger, at now: Date) {
    cases.append(Case(name: name, now: now, ledger: l, expected: Expected(BalanceEngine.report(for: l, at: now))))
}
func add(_ name: String, _ l: Ledger, at nows: [(String, Date)]) {
    for (suffix, now) in nows { add("\(name) @ \(suffix)", l, at: now) }
}

// MARK: - Scenarios (mirror BalanceEngineTests)

add("fresh ledger is even", ledger(), at: at(hour))
add("one beer is one mile of debt", ledger(beers: [beer(t0)]), at: at(hour))
add("beers add up and are numbered in order", ledger(beers: [beer(at(2 * hour)), beer(t0), beer(at(hour))]), at: at(3 * hour))
do { var r = Rules.default; r.milesPerBeer = 2; add("miles per beer sets the principal", ledger(rules: r, beers: [beer(t0)]), at: at(hour)) }
add("events after now do not exist yet", ledger(beers: [beer(at(day))]), at: t0)
add("no interest during grace", ledger(beers: [beer(t0)]), at: at(day - 1))
add("interest posts daily after grace", ledger(beers: [beer(t0)]), at: [("1d", at(day)), ("2d", at(2 * day)), ("5d", at(5 * day))])
do { var r = Rules.default; r.interestPeriod = .weekly; add("weekly period waits a full week", ledger(rules: r, beers: [beer(t0)]), at: [("6d", at(6 * day)), ("7d", at(week))]) }
do { var r = Rules.default; r.gracePeriod = 0; add("no grace still waits one period", ledger(rules: r, beers: [beer(t0)]), at: [("1h", at(hour)), ("1d", at(day))]) }
do { var r = Rules.default; r.gracePeriod = 7 * day; add("long grace delays the first posting", ledger(rules: r, beers: [beer(t0)]), at: [("6d", at(6 * day)), ("7d", at(7 * day)), ("8d", at(8 * day))]) }
do { var r = Rules.default; r.interestRate = 0; add("interest off means no growth", ledger(rules: r, beers: [beer(t0)]), at: at(30 * day)) }
add("interest only accrues on unpaid debt", ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(hour))]), at: at(10 * day))
add("run pays debt", ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(2 * hour))]), at: at(3 * hour))
add("partial repayment", ledger(beers: [beer(t0)], runs: [run(0.4, endedAt: at(2 * hour))]), at: at(3 * hour))
add("oldest beer is paid first", ledger(beers: [beer(at(2 * hour)), beer(t0), beer(at(hour))], runs: [run(1.5, endedAt: at(3 * hour))]), at: at(4 * hour))
add("repayment clears interest before principal", ledger(beers: [beer(t0)], runs: [run(0.5, endedAt: at(day + hour))]), at: [("1d2h", at(day + 2 * hour)), ("2d", at(2 * day))])
add("excess run becomes credit", ledger(rules: noDecay, beers: [beer(t0)], runs: [run(3, endedAt: at(hour))]), at: at(2 * hour))
add("credit is capped", ledger(rules: noDecay, runs: [run(5, endedAt: t0)]), at: at(hour))
do { var r = noDecay; r.milesPerBeer = 2; add("credit cap is in beers at current miles per beer", ledger(rules: r, runs: [run(10, endedAt: t0)]), at: at(hour)) }
add("credit decays ten percent a week", ledger(runs: [run(2, endedAt: t0)]), at: [("0", t0), ("1w", at(week)), ("2w", at(2 * week))])
add("credit decay can be turned off", ledger(rules: noDecay, runs: [run(2, endedAt: t0)]), at: at(10 * week))
add("beer spends credit first", ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(2, endedAt: t0)]), at: at(2 * hour))
add("partial credit then debt", ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(0.4, endedAt: t0)]), at: at(2 * hour))
add("crossing from credit into debt", ledger(rules: noDecay, beers: [beer(at(hour)), beer(at(2 * hour))], runs: [run(1, endedAt: t0)]), at: [("30m", at(30 * 60)), ("90m", at(90 * 60)), ("3h", at(3 * hour))])
add("crossing from debt into credit", ledger(rules: noDecay, beers: [beer(t0)], runs: [run(2, endedAt: at(hour))]), at: [("30m", at(30 * 60)), ("2h", at(2 * hour))])
add("tiny credit reads as even", ledger(rules: noDecay, runs: [run(0.04, endedAt: t0)]), at: at(hour))
add("remnant under 0.05 written off by run", ledger(beers: [beer(t0)], runs: [run(0.97, endedAt: at(hour))]), at: at(2 * hour))
add("remnant under 0.05 written off by credit", ledger(rules: noDecay, beers: [beer(at(hour))], runs: [run(0.97, endedAt: t0)]), at: at(2 * hour))
add("remnant over 0.05 is real debt", ledger(beers: [beer(t0)], runs: [run(0.9, endedAt: at(hour))]), at: at(2 * hour))
add("changing miles per beer does not reprice old beers", withChange(ledger(beers: [beer(t0), beer(at(2 * hour))]), at: at(hour)) { $0.milesPerBeer = 2 }, at: at(3 * hour))
add("turning interest off keeps past interest", withChange(ledger(beers: [beer(t0)]), at: at(2 * day + hour)) { $0.interestRate = 0 }, at: [("2d", at(2 * day)), ("30d", at(30 * day))])
do { var r = Rules.default; r.interestRate = 0
     add("turning interest on accrues from then", withChange(ledger(rules: r, beers: [beer(t0)]), at: at(2 * day + hour)) { $0.interestRate = 0.10 }, at: [("2d2h", at(2 * day + 2 * hour)), ("3d", at(3 * day))]) }
add("changing rate applies to future postings only", withChange(ledger(beers: [beer(t0)]), at: at(day + hour)) { $0.interestRate = 0.20 }, at: [("1d1h", at(day + hour)), ("2d", at(2 * day))])
add("changing period reschedules from the last posting", withChange(ledger(beers: [beer(t0)]), at: at(2 * day + hour)) { $0.interestPeriod = .weekly }, at: [("8d", at(8 * day)), ("9d", at(9 * day))])
do { var r = Rules.default; r.gracePeriod = 7 * day
     add("shortening grace posts at the change not before", withChange(ledger(rules: r, beers: [beer(t0)]), at: at(3 * day)) { $0.gracePeriod = day }, at: [("3d-1s", at(3 * day - 1)), ("3d", at(3 * day)), ("4d", at(4 * day))]) }
add("credit cap change applies forward", withChange(ledger(rules: noDecay, runs: [run(5, endedAt: t0), run(5, endedAt: at(2 * hour))]), at: at(hour)) { $0.maximumCreditBeers = 5 }, at: at(3 * hour))
add("runs before the books opened are ignored", ledger(runs: [run(5, endedAt: at(-hour))]), at: at(hour))
add("late imported run lands at its own time", ledger(beers: [beer(t0)], runs: [run(1, endedAt: at(hour), importedAt: at(5 * day))]), at: at(6 * day))
add("a backdated beer is paid by the run that followed it", ledger(rules: noDecay, beers: [beer(t0, recordedAt: at(2 * day))], runs: [run(2, endedAt: at(day))]), at: at(2 * day))
add("a beer from before the books opened still counts", ledger(rules: noDecay, beers: [beer(at(-2 * day))], runs: [run(3, endedAt: at(hour))]), at: [("0", t0), ("2h", at(2 * hour))])
add("a day is always 86400 seconds", ledger(openedAt: at(49 * day), beers: [beer(at(49 * day))]), at: [("+1d-1s", at(50 * day - 1)), ("+1d", at(50 * day))])
add("a busy fortnight", ledger(
    beers: [beer(t0), beer(at(2 * hour)), beer(at(day + 3 * hour)), beer(at(3 * day)), beer(at(6 * day + 5 * hour)), beer(at(9 * day))],
    runs: [run(1.5, endedAt: at(day + 8 * hour)), run(4.2, endedAt: at(4 * day)), run(0.8, endedAt: at(8 * day + 6 * hour)), run(6, endedAt: at(11 * day))]
), at: [("5d", at(5 * day)), ("10d", at(10 * day)), ("14d", at(14 * day))])

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let fixtures = Fixtures(
    version: 1,
    tolerance: 1e-6,
    note: "Generated by beer-debt-ios/scripts/fixtures.sh from the Swift BalanceEngine. Ledger JSON is the app's on-disk format. Compare doubles with |a-b| <= tolerance; dates are ISO 8601 UTC whole seconds.",
    cases: cases
)
let data = try! encoder.encode(fixtures)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/engine-fixtures/cases.json"
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(cases.count) cases to \(out)")
