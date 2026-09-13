# Beer Debt — decisions

Review notes on `spec.md` against the concept art (`concept.png`), plus the
accounting and platform decisions the code follows. Numbered items marked
**OPEN** need a call from Colin before the engine is finalised; everything else
is decided and the code should match it.

## A. Spec vs. concept art

### 1. Interest rate and period — DECIDED (2026-09-12)

The spec's default table says **10% / week**. But every worked example in the
spec and every number in the concept art implies **10% / day, compounded
daily, after a 24 h grace period**:

| Source | Numbers | Implied rule |
|---|---|---|
| spec §6 FIFO example | Beer #39 1.00 · #40 1.10 · #41 1.21 | 1.1ⁿ steps |
| art screen 3 "Your Debt" | #42 1.46 mi at 5 days old | 1.1⁴ = 1.4641 → four daily steps after 24 h grace |
| art screen 2 "Add Beer" | +1.10 in 1 day · +1.21 in 2 · +1.61 in 5 | 1.1ⁿ steps |
| art screen 5 Settings | "Interest Rate 10%" + "Interest Frequency: Daily" | daily compounding |

**Decision:** default is **10%, compounded daily**. Both the rate and the
frequency (daily / weekly) are exposed in Settings. Changes are forward-only
(see §B). A cap on the interest multiplier is a possible later addition, not MVP.

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

### 3b. Theme, revisited (2026-09-12)

Colin's call after seeing the art's Runs screen: one dark forest palette on
every screen, Settings included, instead of the art's light Ledger/Settings.
The Ledger became two screens to match the art: "Your Debt" (active/paid
beers) off the Home balance and "Runs" (range picker + bar chart + run cards)
off the Home runs card.

### 4. "Interest Frequency" row

Only in the art, not the spec. Kept — it is the compounding period from #1.

## B. Accounting rules (the engine)

These are the rules `BalanceEngine` implements and the tests in
`BeerDebtTests/BalanceEngineTests.swift` pin down. They are chosen so a full
replay of the ledger is deterministic and independent of *when* events were
imported.

- **Units.** Runs are stored in meters (HealthKit and Health Connect native).
  The engine works in miles. Display is miles.
- **The ledger is three event streams:** rules changes, beers, runs. Beers sit
  on the timeline at `createdAt`; runs at `endedAt` (a run pays debt when it
  finishes); rules changes at `effectiveAt`. Same-instant order is rules, then
  beers, then runs. A run that HealthKit delivers late is applied at its own
  time, so a delayed sync produces the same balance as a prompt one.
- **Replay.** Fold the merged timeline in order. Before applying each event,
  bring every open debt and the credit pool forward to that event's time
  (interest postings, decay). After the last event, bring everything forward
  to `now`. Events after `now` don't exist yet.
- **Debt interest** posts in discrete steps on the full outstanding amount
  (principal + earlier interest), which is what 1.1ⁿ means. The first posting
  is at `createdAt + max(grace, period)`: interest can post neither before the
  grace period ends nor before a full period has elapsed. With the defaults
  (24 h grace, daily) that is exactly 24 h. Later postings are one period
  apart. Principal and interest are tracked separately for display.
- **Repayment** is FIFO by `createdAt`. Within one debt a payment clears
  accrued **interest first, then principal** (standard loan accounting; it
  only affects the principal/interest split, not the total).
- **Credit** is one pool in miles. Leftover run miles after all debt is paid go
  into it, capped at `maximumCreditBeers × milesPerBeer`; anything over the cap
  is discarded, never hidden. Decay is continuous:
  `credit(t) = credit(t₀) · (1 − decayPerWeek)^((t − t₀) / 1 week)`.
- **A beer spends credit first.** Cost = miles-per-beer in force at
  `createdAt`. Whatever credit doesn't cover opens a debt for the remainder.
- **Rules changes are forward-only.** Colin's call (2026-09-12): "changes
  don't affect historical values, forward only so the economy doesn't
  change." Concretely:
  - Miles per beer: applies to beers added after the change. Old beers keep
    their principal. Credit is stored in miles, so its *beer* value shifts
    with the new rate (2 mi is 2 beers at 1.0, 1 beer at 2.0).
  - Interest rate: applies to every posting after the change, on existing
    debts too. Posted interest is never recalculated. Turning interest off
    freezes existing debts at their current amount; turning it back on resumes
    from the change.
  - Frequency and grace: each open debt's *next* posting is rescheduled as
    `lastPosting + newPeriod` (or `createdAt + max(newGrace, newPeriod)` if it
    has never posted), but never earlier than the change itself. A debt that is
    already past a newly shortened grace posts once at the change instant.
  - Credit cap and decay: policy on the pool; the new values apply from the
    change forward.
- **Correcting a beer's date** (added 2026-09-12). A beer you forgot to log
  can be dated back from the Beer Added sheet or the beer's detail, up to 30
  days and no later than now. It *may* predate `booksOpenedAt`: on day one
  you can own up to last night's beers. (The first version clamped to the
  books, which on a fresh install disabled every day but today.) Runs from
  before the books opened still never count, so an old beer can only be paid
  by running done since install.
  `BeerEntry.recordedAt` keeps when it was actually logged, so the ledger can
  show "Logged …" on backdated beers. The next replay simply treats the beer
  as having happened then, which can re-route an earlier run from credit to
  paying it. That is the one deliberate exception to "history never changes":
  it is correcting the record, not changing the rules.
- **Deleting a beer** (added 2026-09-12). An accidental tap can be removed
  from the Beer Added sheet (no confirmation; it was seconds ago), or from
  The Ledger by swipe or the detail's Delete button (confirmed). The entry is
  removed outright, not tombstoned. On the next replay any run that paid for
  it flows to the other beers or to credit.
- **Precision.** Event timestamps are whole seconds so the JSON round-trips
  exactly and a relaunch replays to the identical balance. "Daily" and
  "weekly" are fixed lengths (86,400 s / 604,800 s), not calendar units, so
  postings drift an hour across a DST change rather than jumping.
- **State.** `debt` if anything is outstanding; otherwise `credit` if the pool
  is ≥ 0.05 beers; otherwise `even`.

### 5. Running streaks — DECIDED (2026-09-12)

Colin approved the recommendations in the streak review:

- **Forward-only start.** `Rules.streakProtection` decodes as off for
  ledgers written before the feature and the store appends a rules change
  turning it on at upgrade. New ledgers start with it on. Protection is
  therefore never applied to postings from before the upgrade.
- **Weekly compounding.** A weekly posting that lands on a protected day is
  skipped whole. No prorating.
- **Same-day retroactivity.** The streak is recomputed from the runs at
  every replay, so an evening run removes the interest that posted that
  morning. The owed number can go down during the day without a repayment;
  that is the intended "run today to cancel today's interest" feel.
- **Feedback.** No "run logged" sheet on every run. One celebration sheet
  when day two activates protection; every other streak day gets a line in
  the existing run notification.
- **Threshold.** One mile less one metre, so 1.00 mi on a watch qualifies.
- **Calendar days.** `BalanceEngine.report(for:at:calendar:)` takes the
  calendar; the app passes the device's, tests and fixtures pin UTC. A user
  who changes time zones can see a day regroup; accepted for MVP.

## C. HealthKit

- Read types: workouts + `distanceWalkingRunning` (needed to read a workout's
  distance). Nothing else, nothing written.
- Only `HKWorkoutActivityType.running`. Distance from
  `workout.statistics(for: distanceWalkingRunning)?.sumQuantity()`, falling back
  to `totalDistance`.
- Dedup key is `HKWorkout.uuid`; import is idempotent. Sync via
  `HKAnchoredObjectQuery` with a persisted anchor whenever the app becomes active.
- **Books open at zero — DECIDED (2026-09-12).** Only workouts that *end
  after first launch* (`Ledger.booksOpenedAt`) count. `HealthSync` drops
  earlier ones before they reach the ledger, and the engine ignores any that
  slip through. Otherwise a new user's last week of runs would instantly bank
  the maximum credit.
- **Deleting a workout in Health takes the run off the books** (fixed
  2026-09-12 after Colin hit it: a manually added workout stayed counted after
  he deleted it). The anchored query reports deletions; `HealthSync` removes
  the matching runs and the next replay puts whatever they paid back on the
  tab. If the app is closed, a notification says where the tab stands now.
- **Background delivery and notifications** (added 2026-09-12, spec §22).
  With the `healthkit.background-delivery` entitlement and an observer query
  registered at every launch (`BeerDebtApp.init`, so background launches
  count), iOS wakes the app when a running workout is saved; the sync applies
  it and, if the app isn't in the foreground and the user opted in, posts a
  local notification: what the run paid and where the tab stands. Foreground
  syncs update the UI instead. A debt-free celebration earned in the
  background is stashed in UserDefaults and shown on the next open. No push
  server: everything is local.
- **Deleting a run in the app** (added 2026-09-12). Swipe a run in The
  Ledger. It comes off the books (whatever it paid goes back on the tab) and
  its HealthKit workout ID goes into `Ledger.excludedWorkoutIDs`, so a
  re-sync from scratch (reinstall, anchor reset) can't bring it back. Two
  reasons: cleaning up runs deleted from Health before deletion handling
  existed, and choosing not to count a real run. Older ledger files without
  the field decode with an empty set.
- **Weekly summary** (added 2026-09-12): an opt-in local notification on a
  chosen weekday and time with the week's beers, miles run, and where the tab
  stands. The standing quoted is `BalanceEngine.report(for:at: fireDate)`,
  i.e. the exact balance at the moment it fires assuming nothing new happens;
  the next four occurrences are scheduled and rescheduled on every ledger
  change, so the copy stays right even if the app isn't opened for a while.
- **Widget** (added 2026-09-12, spec §22): Home Screen small/medium and Lock
  Screen rectangular/inline/circular, in a WidgetKit extension that compiles
  the engine, models, and `Format` in and replays `ledger.json` from the App
  Group container (`group.me.colinwatson.beerdebt`, registered by Xcode
  Cloud's managed signing; the store migrated the file there from
  Application Support). No interactive + Beer button yet: writes from the
  widget process would need file coordination with the app.
- **Widget freshness** (revised 2026-09-13): every timeline entry is a
  projection of the ledger as it stood when the timeline was built, so
  interest steps up on schedule but a run imported afterwards is invisible
  until WidgetKit is asked for a reload. Two halves keep that honest.
  `LedgerStore.refreshWidgets()` is called on every save *and* whenever the
  app becomes active *and* after every successful sync, including a sync that
  imports nothing: a reload asked for on a background wake can be declined,
  and the sync that would ask again finds the run already on the books, so
  it never saves and never asks. Without the unconditional retry a declined
  reload was permanent until the books changed again. `BalanceTimeline`
  (pure, tested, compiled into the app target) then bounds the fallback:
  hourly entries across a six-hour horizon, the next interest posting added
  only when it falls inside, and `.after(horizon)` rather than `.atEnd` so a
  posting days out can never become the last entry and push the rebuild out
  with it. Six hours is the worst-case staleness; it was a day.
- Two sources logging the same run (Watch + Strava) is not handled in MVP.

## D. Platform

- **iOS 17.0 minimum** (earlier apps used 16). Buys `@Observable`; nothing else
  in the app needs it. One-line change in `project.yml` if reach matters.
- **Swift 6 language mode** with approachable concurrency. The engine is value
  types; services are `@MainActor`.
- **Persistence:** a single Codable JSON file (`ledger.json`) in Application
  Support/BeerDebt, ISO 8601 dates, written atomically. An unreadable file is
  renamed `ledger-unreadable-<epoch>.json` and the books reopen, never
  silently deleted. The data set is tiny, replay is the source of
  truth, there are no migrations to manage, and the same shape ports straight
  to Android. SwiftData is deliberately not used.
- **A failed write is remembered** (added 2026-09-13): a disk write can fail
  for reasons the app doesn't control, and the failure is silent, because the
  in-memory books still look right until the next launch reads the file back.
  `LedgerStore.isPersisted` goes false when a save fails and `persist()`
  retries it, reporting whether the file now matches memory. The ledger is
  written whole, so one later save carries every event that was lost along
  the way. This is not an assertion: the environment misbehaving is not a bug
  in the app, and trapping would only turn lost data into a crash.
  Anything holding the sole means of rebuilding those events must call
  `persist()` before discarding it. The HealthKit anchor is the case that
  matters: it is the only record of which workouts have been read, so `sync()`
  advances it only once the runs it covers are on disk. Advancing it over a
  ledger that never reached the file lost the run for good, because HealthKit,
  asked from the newer anchor, never offers that workout again. Holding the
  anchor costs a re-read and nothing else, since the store dedups on workout
  id, and it makes every sync a retry point for any earlier failed write.
- **One dependency: Sentry** (added 2026-09-13, crash reporting only, the
  same policy as the Android app: no user identification, replay, or
  tracing). Everything else is Apple frameworks.
- **Android:** sister repo `beer-debt-android` (Kotlin + Compose + Health
  Connect), mirroring `pourcraft-ios` / `pourcraft-android`. The shared contract
  is `spec.md` plus the engine's test cases exported as JSON fixtures
  (`docs/engine-fixtures/`, to be created with the engine).
