# Beer Debt — Claude Code guide

iPhone app: drink beer → owe miles; run → pay it back; ignore it → interest.
Read `docs/spec.md` first (what to build, acceptance criteria) and
`docs/decisions.md` second (accounting rules and platform choices, plus open
questions). This file is the *how*.

## Build / regenerate

The Xcode project is generated from `project.yml` via XcodeGen. After adding,
removing, or moving files, regenerate:

```sh
xcodegen generate
```

Build and test from the command line:

```sh
xcodegen generate
xcodebuild -project BeerDebt.xcodeproj -scheme BeerDebt \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).

## Screenshots / manual testing on the simulator

`scripts/screenshots.sh [udid|booted]` installs the current simulator build,
seeds demo ledgers (debt and credit states), and screenshots every screen into
`docs/screenshots/`. It relies on the DEBUG-only launch argument
`-debugScreen ledger|runs|settings|beerAdded|beerDetail|debtFree` handled in
`RootView` / `HomeView` / `LedgerView`, and on writing `ledger.json` straight into the app container.
Keep the seed shapes in that script in sync with `Ledger`'s JSON.

## Conventions

- SwiftUI, iOS 17+, Swift 6 language mode with approachable concurrency.
  `@Observable` + `@MainActor` on stateful services (`LedgerStore`,
  `HealthKitService`). Everything under `Engine/` and `Models/` is a plain
  `Sendable` value type.
- Bundle ID `me.colinwatson.beerdebt`, team `M7PCWQ7WYN` (matches pourcraft-ios
  and strumbuddy-ios).
- **No third-party dependencies.** Don't add packages without a reason.
- The `.xcodeproj` is committed but generated — never hand-edit it; change
  `project.yml` and regenerate.
- The engine is pure. `BalanceEngine.calculateBalance(beers:runs:rules:at:)`
  takes no clocks and does no I/O. `now` is always injected. Tests use fixed
  `Date(timeIntervalSince1970:)` instants, never `.now`.
- Events are append-only and immutable, with one exception: a beer's
  `createdAt` may be corrected through `LedgerStore.updateBeerDate`, which
  clamps it to the last 30 days (it may predate `booksOpenedAt`; runs may
  not), and an accidental beer may be removed
  with `LedgerStore.removeBeer`. `BeerEntry` is id + `createdAt` (+
  `recordedAt`, when it was logged),
  `RunEntry` (HealthKit workout UUID for dedup, meters), and `RulesChange`
  (rules effective from an instant). The `Ledger` holds all three plus
  `booksOpenedAt`. Never store a derived balance; always replay via
  `BalanceEngine.report(for:at:)`, which returns the `Balance` plus per-beer
  and per-run statements the Ledger screen renders.
- Rules changes are forward-only (decisions.md §B). Don't snapshot rules onto
  events and don't recompute history when rules change; append a
  `RulesChange` through `LedgerStore.updateRules`.
- Event timestamps are floored to whole seconds (`Date.flooredToSecond`) so
  the JSON round-trips exactly.
- HealthKit is read-only and running-workouts-only. Don't add read types
  without updating `NSHealthShareUsageDescription`.
- Product copy lives in spec §18–§19; keep the finance-vocabulary tone
  (principal, interest, credit, "books are clean", "your tab").

## Release

App Store Connect app ID `6811380824`, bundle `me.colinwatson.beerdebt`.
Ships via Xcode Cloud → TestFlight on push to `main`; see `docs/release.md`
for the workflow definition, versioning, and the one-time Xcode setup. Bump
`MARKETING_VERSION` in `project.yml` for a new release; Xcode Cloud sets the
build number.

## Android

A sister repo (`beer-debt-android`) is planned. The cross-platform contract is
`docs/spec.md` + the engine's test cases. When adding engine tests, write them
as data (events, rules, `now`, expected balance) so they can be exported as
JSON fixtures and run against the Kotlin engine.

## Release assets

App icon and store screenshots are generated from the shared `~/app-utils` repo
(github.com/watsoncolin/app-utils), per-app config under `apps/beerdebt/` (not
created yet). Don't commit generated icons here until that exists.

## Map

- `App/` — `BeerDebtApp` + `RootView` (single `NavigationStack`, no tab bar).
- `Engine/` — `BalanceEngine` (replay), `Balance` (output).
- `Models/` — `BeerEntry`, `RunEntry`, `Rules` (+ `InterestTerms`, `CompoundingPeriod`).
- `Persistence/` — `LedgerStore` (observable owner of the JSON ledger file).
- `Health/` — `HealthKitService` (authorization, anchored workout query) and
  `HealthSync` (connect, sync-on-active, drops pre-books runs, debt-free
  celebration trigger).
- `Features/` — `Home`, `Ledger`, `Settings`, `Onboarding`. Beer feedback and
  transaction detail are sheets.
- `Theme/` — palette, `Backdrop`, `GoldButtonStyle`, `Pill`, and `Format`
  (all number/date formatting; keep it out of views).
