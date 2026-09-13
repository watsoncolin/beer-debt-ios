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
`-debugScreen ledger|runs|settings|streak|beerAdded|beerDetail|debtFree|streakActivated` handled in
`RootView` / `HomeView` / `LedgerView`, and on writing `ledger.json` straight into the app container.
Keep the seed shapes in that script in sync with `Ledger`'s JSON.

## Conventions

- SwiftUI, iOS 17+, Swift 6 language mode with approachable concurrency.
  `@Observable` + `@MainActor` on stateful services (`LedgerStore`,
  `HealthKitService`). Everything under `Engine/` and `Models/` is a plain
  `Sendable` value type.
- Bundle ID `me.colinwatson.beerdebt`, team `M7PCWQ7WYN` (matches pourcraft-ios
  and strumbuddy-ios).
- **One third-party dependency: Sentry**, crash reporting only. `Telemetry/`
  is the one door (Pourcraft convention): no user identification, no replay,
  no tracing; hand-reported errors carry a context block keyed by domain
  (`health`, `store`), reported once at the source. `TelemetryPolicy` keeps
  it out of test runs and tags debug builds `development`. Don't add other
  packages without a reason; the widget links nothing third-party.
- The `.xcodeproj` is committed but generated — never hand-edit it; change
  `project.yml` and regenerate. `Package.resolved` (under
  `project.xcworkspace/xcshareddata/swiftpm/`) is committed too: Xcode Cloud
  disables automatic resolution and fails without it. While Xcode has the
  project open, an `xcodebuild -resolvePackageDependencies` from the shell
  writes a file Xcode deletes moments later; resolve in a `git worktree` (or
  with the project closed) when it needs regenerating.
- The engine is pure. `BalanceEngine.report(for:at:)` takes a `Ledger` and an
  instant, no clocks, no I/O. `now` is always injected. Tests use fixed
  `Date(timeIntervalSince1970:)` instants, never `.now`.
- Events are append-only and immutable, with one exception: a beer's
  `createdAt` may be corrected through `LedgerStore.updateBeerDate`, which
  clamps it to the last 30 days (it may predate `booksOpenedAt`; runs may
  not), an accidental beer may be removed with `LedgerStore.removeBeer`, and a
  run may be taken off the books with `LedgerStore.deleteRun` (its workout ID
  lands in `Ledger.excludedWorkoutIDs` so it is never re-imported), and the
  books can be opened earlier with `LedgerStore.reopenBooks` (Settings ›
  About; earlier only, a year at most; `HealthSync.reopenBooks` then drops
  the anchor and re-reads Health so older runs come in). `BeerEntry` is id + `createdAt` (+
  `recordedAt`, when it was logged),
  `RunEntry` (HealthKit workout UUID for dedup, meters), and `RulesChange`
  (rules effective from an instant). The `Ledger` holds all three plus
  `booksOpenedAt`. Never store a derived balance; always replay via
  `BalanceEngine.report(for:at:)`, which returns the `Balance` plus per-beer
  and per-run statements the Ledger screen renders.
- `BalanceEngine.report(for:at:calendar:)`: the calendar decides streak days.
  Views use the device calendar (the default); tests and `scripts/fixtures.swift`
  pin UTC so numbers never depend on the machine.
- Rules changes are forward-only (decisions.md §B). Don't snapshot rules onto
  events and don't recompute history when rules change; append a
  `RulesChange` through `LedgerStore.updateRules`.
- Event timestamps are floored to whole seconds (`Date.flooredToSecond`) so
  the JSON round-trips exactly.
- HealthKit is read-only and running-workouts-only. Don't add read types
  without updating `NSHealthShareUsageDescription`. Notifications are local
  only (`UserNotifications`), posted only when the app is not in the
  foreground and the user turned them on.
- Product copy lives in spec §18–§19; keep the finance-vocabulary tone
  (principal, interest, credit, "books are clean", "your tab").

## Widget

`BeerDebtWidget/` is a WidgetKit extension (bundle
`me.colinwatson.beerdebt.widget`) that shares `Engine/`, `Models/`,
`Theme/Format.swift`, and `Theme/Theme.swift` as sources and reads
`ledger.json` from the App Group container via `LedgerFile`. Keep the widget
free of app-only types. `BalanceWidgetViews.swift` is also compiled into the
app so `-debugScreen widgets` can render the faces for screenshots, and so
`BalanceTimeline` (the pure entry/refresh schedule) can be unit-tested.
Widget faces go stale unless something asks WidgetKit to reload:
`LedgerStore.refreshWidgets()` is called on every save, on app active, and
after **every** successful sync, including one that imports nothing. Don't
make that last call conditional on the ledger changing; a declined reload is
otherwise permanent. Keep the timeline horizon in hours, not a day. Both
targets carry the `group.me.colinwatson.beerdebt` entitlement; Xcode Cloud's
managed signing registered the group itself (the API can't).

## Release

App Store Connect app ID `6811380824`, bundle `me.colinwatson.beerdebt`.
Ships via Xcode Cloud → TestFlight on push to `main`; see `docs/release.md`
for the workflow definition, versioning, and the one-time Xcode setup. Bump
`MARKETING_VERSION` in `project.yml` for a new release; Xcode Cloud sets the
build number.

## Website

`index.html`, `support.html`, `privacy.html`, and `.nojekyll` at the repo root
are the GitHub Pages site (source: `main`, `/`), same layout as strumbuddy-ios.
They reference the icon and `docs/screenshots/home-debt.png` by repo path.
App Store Connect's privacy-policy and support URLs point at the privacy and
support pages; the privacy page is what App Review reads for HealthKit use,
so keep the Apple Health section accurate when Health usage changes.

## Android

The sister repo is `~/beer-debt-android` (github.com/watsoncolin/beer-debt-android).
This repo leads; features are built and validated here first, then ported.
The cross-platform contract is `docs/spec.md` + `docs/engine-fixtures/cases.json`,
generated from the Swift engine by `scripts/fixtures.sh` (64 scenarios mirroring
`BalanceEngineTests`; pure `swiftc`, no simulator). **After any engine or model
change: run `scripts/fixtures.sh`, commit the JSON, and copy it to
`~/beer-debt-android/engine/src/test/resources/cases.json`.** The Kotlin
engine's test fails loudly if the numbers drift. Add new scenarios to
`scripts/fixtures.swift` alongside new Swift tests.

## Art

Originals live in `docs/art/` (generated with Codex, 2026-09-12): the app icon
(mug with a trail, Colin's pick), the plain mug, the transparent trophy mug,
the portrait trail-and-mountains scene, a transparent cut-out of the trail
mug, and a foam-only layer (for a future Icon Composer layered icon; the
matching body layer still needs a clean transparent render). The asset
catalog holds resized copies: `AppIcon` light (1024, opaque green), dark and
tinted variants (transparent / grayscale-transparent, generated from the
cut-out by a PIL one-off), `BrandMark` (transparent trail mug, 600, used on
onboarding and Beer Added), `DebtFreeTrophy` (600), `HomeBackdrop` (original
size, single scale), and the streak set (2026-09-12, prompts in
`design/streak-assets-v1/PROMPTS.md`): `StreakFlame`, `StreakFlameUnlit`,
`StreakActivated` (600 each; `StreakFlame` falls back to the SF Symbol when
an asset is missing). `Backdrop`
in `Theme.swift` draws the scene under a scrim tuned so cream text stays
legible over the sunset band; if the art changes, re-check `home-debt` in
`scripts/screenshots.sh`. The launch screen is `LaunchScreen.storyboard`
(same image, aspect-filled, flat 45% scrim) because the plist launch screen
can't scale an image.

Store screenshots: capture raws with `scripts/screenshots.sh <iPhone 16 Pro Max
udid> <dir>` (native 6.9", 1320×2868), copy them to
`~/app-utils/apps/beerdebt/raw/01..07.png`, then in `~/app-utils` run
`npm run shots:compose apps/beerdebt/config.mjs`. Captions and the gold theme
are in that config. Upload to App Store Connect goes through the API into the
`APP_IPHONE_67` screenshot set (that is the 6.9" slot; there is no `_69`).

## Map

- `App/` — `BeerDebtApp` owns `LedgerStore` and `HealthSync` (created in
  `init` so HealthKit background launches register the observer) and hands
  them to `RootView` (single `NavigationStack`, no tab bar) via the environment.
- `Engine/` — `BalanceEngine` (replay; skips interest postings on protected
  streak days), `Balance` (output, incl. `Report.streak` and
  `RunStatement.streakDayNumber`), `StreakEngine` (pure: runs → calendar days →
  `StreakStatus`; spec §25, decisions §B.5).
- `Models/` — `BeerEntry`, `RunEntry`, `Rules` (+ `CompoundingPeriod`), `Ledger` (+ `RulesChange`).
- `Persistence/` — `LedgerStore` (observable owner of the JSON ledger file).
- `Telemetry/` — `Telemetry` (Sentry start + `report`), `TelemetryPolicy`.
- `Health/` — `HealthKitService` (authorization, anchored workout query with
  deletions, background delivery + observer query), `HealthSync` (connect,
  sync on active and on background wake, drops pre-books runs, removes deleted
  workouts, debt-free celebration, notification trigger, owns `WeeklySummary`),
  `RunNotifier` (local notification permission + the pure copy builder),
  `WeeklySummary` (schedule + pure copy for the weekly recap).
- `Models/LedgerFile.swift` — the shared on-disk location and codecs, used by
  both the store and the widget.
- `Features/` — `Home`, `Ledger/DebtView` ("Your Debt": active/paid beers,
  reached by tapping the Home balance), `Runs/RunsView` (range picker, Swift
  Charts bar chart, run cards; reached from the Home runs card), `Settings`,
  `Onboarding`, `Streak` (`StreakCard` on Home, `StreakView` "Your Streak",
  `StreakActivatedSheet`, `StreakFlame` + `StreakCopy` shared words),
  `Shared/WidgetPreviewScreen` (DEBUG). Beer feedback, beer detail, debt
  free, and streak activated are sheets.
- `Theme/` — palette, `Backdrop`, `GoldButtonStyle`, `Pill`, `Format`
  (all number/date formatting; keep it out of views), and the app-wide dark
  treatment: `RootView` forces `.preferredColorScheme(.dark)`, every
  secondary screen uses `.forestScreen()` (forest gradient under a
  plain-style List) with `.cardRow()` / `.listRowBackground(Theme.card)`
  rows, and `Theme.applyAppearance()` styles segmented controls as a cream
  pill on a dark track. Don't introduce light backgrounds.
