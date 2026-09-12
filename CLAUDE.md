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
- Events are immutable and append-only. A `BeerEntry` snapshots `milesPerBeer`
  and the interest terms; a `RunEntry` keeps the HealthKit workout UUID for
  dedup. Never store a derived balance; always replay.
- HealthKit is read-only and running-workouts-only. Don't add read types
  without updating `NSHealthShareUsageDescription`.
- Product copy lives in spec §18–§19; keep the finance-vocabulary tone
  (principal, interest, credit, "books are clean", "your tab").

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
- `Health/` — `HealthKitService` (authorization, anchored workout query).
- `Features/` — `Home`, `Ledger`, `Settings`, `Onboarding`. Beer feedback and
  transaction detail are sheets.
- `Theme/` — palette.
