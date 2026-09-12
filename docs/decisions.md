# Beer Debt — decisions

Review notes on `spec.md` against the concept art (`concept.png`), plus the
accounting and platform decisions the code follows. Numbered items marked
**OPEN** need a call from Colin before the engine is finalised; everything else
is decided and the code should match it.

## A. Spec vs. concept art

### 1. Interest rate and period — OPEN

The spec's default table says **10% / week**. But every worked example in the
spec and every number in the concept art implies **10% / day, compounded
daily, after a 24 h grace period**:

| Source | Numbers | Implied rule |
|---|---|---|
| spec §6 FIFO example | Beer #39 1.00 · #40 1.10 · #41 1.21 | 1.1ⁿ steps |
| art screen 3 "Your Debt" | #42 1.46 mi at 5 days old | 1.1⁴ = 1.4641 → four daily steps after 24 h grace |
| art screen 2 "Add Beer" | +1.10 in 1 day · +1.21 in 2 · +1.61 in 5 | 1.1ⁿ steps |
| art screen 5 Settings | "Interest Rate 10%" + "Interest Frequency: Daily" | daily compounding |

Recommendation: keep the art's model. Interest is a **rate + compounding period**
(`InterestTerms`), both exposed in Settings, and the default is **10% daily**.
Weekly interest is invisible inside the product's core loop (drink Saturday, run
Sunday); daily makes the "this beer is getting expensive" joke land within days.
It is harsh over a month (a 1 mi beer left 30 days ≈ 15 mi), so a later cap on
the interest multiplier (e.g. 3×) is worth considering, but not for MVP.

Code currently defaults to the spec table (weekly). Flip `Rules.interest.period`
to `.daily` once decided.

### 2. Screen count

The art shows eight screens; the spec's MVP is three plus onboarding (§20). Mapping:

| Art | MVP treatment |
|---|---|
| 1 Home | Home (spec §10) |
| 2 Add Beer | Sheet / transient overlay on Home (spec §11) |
| 3 Your Debt (Active / Paid) | The Ledger, "Beers" segment |
| 4 Runs (week / month / all-time + chart) | The Ledger, "Runs" segment; the chart is optional polish |
| 5 Settings | Settings |
| 6 Debt Free | Home's celebration state when debt hits zero, not a separate screen |
| 7 Home Screen widget | Out of scope (§21). Engine is a pure type so a widget extension can share it later via an App Group |
| 8 Lock Screen notification | Out of scope (§21) |

### 3. Missing from the art

The art never shows the **credit** state ("2.4 BEERS BANKED") or the **even**
state ("BOOKS ARE CLEAN"), and its Settings screen lacks **Maximum Credit** and
**Credit Decay**. The spec requires all four; the code includes them. Home
follows the art's debt layout and swaps the big number + caption per state
using the copy in spec §10 / §19.

### 4. "Interest Frequency" row

Only in the art, not the spec. Kept — it is the compounding period from #1.

## B. Accounting rules (the engine)

These are the rules `BalanceEngine` implements. They are chosen so a full replay
of the ledger is deterministic and order-independent of *when* events were
imported.

- **Units.** Runs are stored in meters (HealthKit and Health Connect native).
  The engine works in miles. Display is miles.
- **Timeline.** Beers sit on the timeline at `createdAt`; runs at `endedAt`
  (a run pays debt when it finishes). A run that HealthKit delivers late is
  applied at its own time, so a delayed sync produces the same balance as a
  prompt one.
- **Replay.** Fold the merged timeline in order. Before applying each event,
  bring every open debt and the credit pool forward to that event's time
  (interest steps, decay). After the last event, bring everything forward to
  `now`.
- **Debt interest** is discrete: outstanding amount steps up by `rate` at
  `createdAt + grace + k·period` for k = 1, 2, …. Interest compounds on the
  full outstanding amount (principal + earlier interest), matching 1.1ⁿ.
  Principal and interest are tracked separately for display.
- **Repayment** is FIFO by `createdAt`. Within one debt, a payment clears
  accrued **interest first, then principal** (standard loan accounting; it only
  affects the principal/interest split, not the total).
- **Credit** is one pool in miles. Leftover run miles after all debt is paid go
  into it, capped at `maximumCreditBeers × rules.milesPerBeer`; anything over
  the cap is discarded, never hidden. Decay is continuous:
  `credit(t) = credit(t₀) · (1 − decayPerWeek)^((t − t₀) / 1 week)`.
- **A beer spends credit first.** Cost = the beer's snapshotted `milesPerBeer`.
  Whatever credit doesn't cover opens a debt for the remainder.
- **Settings snapshots.** `milesPerBeer` and the interest terms are copied onto
  each `BeerEntry` at creation, so changing them never rewrites existing debt
  (spec §16). The credit cap and decay rate are policy on the pool and use the
  current rules.
- **State.** `debt` if any debt is outstanding; otherwise `credit` if the pool
  ≥ 0.05 beers; otherwise `even`.

## C. HealthKit

- Read types: workouts + `distanceWalkingRunning` (needed to read a workout's
  distance). Nothing else, nothing written.
- Only `HKWorkoutActivityType.running`. Distance from
  `workout.statistics(for: distanceWalkingRunning)?.sumQuantity()`, falling back
  to `totalDistance`.
- Dedup key is `HKWorkout.uuid`; import is idempotent. Sync via
  `HKAnchoredObjectQuery` with a persisted anchor whenever the app becomes active.
- **Books open at zero — OPEN.** Only workouts that *end after first launch*
  count. Otherwise a new user's last week of runs would instantly bank the
  maximum credit. The alternative (import the last N days so you start with a
  few beers banked) is friendlier but muddles the accountability story.
- Two sources logging the same run (Watch + Strava) is not handled in MVP.

## D. Platform

- **iOS 17.0 minimum** (earlier apps used 16). Buys `@Observable`; nothing else
  in the app needs it. One-line change in `project.yml` if reach matters.
- **Swift 6 language mode** with approachable concurrency. The engine is value
  types; services are `@MainActor`.
- **Persistence:** a single Codable JSON file (`ledger.json`) in Application
  Support, written atomically. The data set is tiny, replay is the source of
  truth, there are no migrations to manage, and the same shape ports straight
  to Android. SwiftData is deliberately not used.
- **No dependencies.**
- **Android:** sister repo `beer-debt-android` (Kotlin + Compose + Health
  Connect), mirroring `pourcraft-ios` / `pourcraft-android`. The shared contract
  is `spec.md` plus the engine's test cases exported as JSON fixtures
  (`docs/engine-fixtures/`, to be created with the engine).
