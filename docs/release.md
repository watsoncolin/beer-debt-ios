# Release pipeline

Beer Debt ships through **Xcode Cloud → TestFlight**, the same shape as
Pawfect Edit and StrumBuddy.

## App Store Connect

| | |
|---|---|
| App | Beer Debt, App Store Connect ID `6811380824` |
| Bundle ID | `me.colinwatson.beerdebt` (registered with HealthKit; identifier record `T27HZ5CR5R`) |
| Team | `M7PCWQ7WYN` |
| SKU | `me.colinwatson.beerdebt` |
| Primary language | English (U.S.) |
| First version | 1.0 (matches `MARKETING_VERSION` in `project.yml`) |

Created 2026-09-12. Listing filled the same day, mostly through the API:
URLs, seven 6.9" screenshots (composed in `~/app-utils`, see CLAUDE.md),
description / subtitle / keywords / promo text, copyright, categories
(Health & Fitness, Lifestyle), age rating 17+ (alcohol references), content
rights, App Privacy "Data Not Collected" (published), price Free, all 175
territories, build attached, review notes with HealthKit test steps.

Submitted for App Review on 2026-09-12 (build 10, automatic release after
approval). The review contact needed a phone number the API wouldn't accept
a blank for, so Colin filled it in the web UI before pressing Add for Review.

## Xcode Cloud workflow

Copied from Pawfect Edit's `Default` workflow (compared setting by setting on
2026-09-12). Its Sentry environment variables are the one part not carried
over yet; see "Sentry" below:

- **Start condition:** push to `main` (exact match), auto-cancel superseded
  builds.
- **Environment:** Xcode "Latest Release", macOS "Latest Release", clean build.
- **Actions:** `Archive - iOS` (scheme `BeerDebt`, TestFlight and App Store
  eligible, required to pass). Same as Pawfect Edit. Xcode's own default left
  the distribution audience unset (archive only, nothing to TestFlight); it was
  patched via the API on 2026-09-12.
- **Not yet:** a `Test - iOS` action. The API's test-destination lookup isn't
  available to our key, so add it from Xcode if wanted: Product → Xcode Cloud →
  Manage Workflows… → Default → Actions → + Test → Recommended iPhones,
  required to pass. Until then, run the tests locally before pushing to `main`.
- **Post-action:** `TestFlight Internal Testing - iOS`, artifact
  `Archive - iOS`, group **Internal** (same as Pawfect Edit). The Internal
  group (`6463027e-d811-4508-9041-c1b10ed71b4d`) is an internal group with
  access to all builds and feedback on; Colin is its tester. Add more team
  members from TestFlight → Internal → Invite Testers.

`ci_scripts/ci_post_clone.sh` installs XcodeGen and regenerates
`BeerDebt.xcodeproj` from `project.yml` before the build, so a stale
committed project can never ship. `ci_scripts/ci_post_xcodebuild.sh` uploads
the archive's dSYMs to Sentry (see below); it skips, loudly, when the
variables aren't set, and never fails the build.

## Sentry

Project `beer-debt-ios` in the `pawfect-edit` org (created 2026-09-13), the
sister of `beer-debt-android`. The app sends crashes, fully blocking app
hangs, and hand-reported Health/store errors; nothing that identifies the
user (`BeerDebt/Telemetry/`). The DSN lives in `Telemetry.swift` (a public
ingest address, not a secret). For symbolicated traces the Xcode Cloud
workflow needs three environment variables, added in App Store Connect →
Xcode Cloud → Default → Edit → Environment (the web UI; Xcode's own editor
rejects the long token): `SENTRY_AUTH_TOKEN` (secret; an org token with
`project:write` and `org:read`), `SENTRY_ORG=pawfect-edit`,
`SENTRY_PROJECT=beer-debt-ios`.

App Privacy in App Store Connect has to change before the first Sentry build
is submitted: **Crash Data**, **Other Diagnostic Data**, and **Device ID**
(the SDK's random installation id, used for release health), each collected
for App Functionality, not linked to the user, not used for tracking. Build
23 (1.0, in review since 2026-09-13) predates Sentry and is covered by "Data
Not Collected".

### Versioning

- `MARKETING_VERSION` in `project.yml` is the App Store version. Bump it by
  hand when starting a new release.
- Builds 24–27 never reached TestFlight: 24 and 25 were superseded, 26 was
  cancelled by 27, and 27 failed for want of a committed `Package.resolved`
  (the first build with a package). Build 28 is the first with Sentry.
- The build number is set by Xcode Cloud (`CI_BUILD_NUMBER`) at archive time;
  `CURRENT_PROJECT_VERSION` in `project.yml` only matters for local builds.

### Signing

Automatic, with Xcode Cloud's managed signing. The HealthKit entitlement is
in `BeerDebt/Resources/BeerDebt.entitlements`; the App ID already carries the
capability.

### HealthKit purpose strings

App Store Connect rejects the upload (ITMS-90683) unless **both**
`NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are in
`Info.plist`, even though the app only reads. Both are set; the update string
says plainly that nothing is written. Builds 2 and 3 failed on this.

### Entitlements

`BeerDebt.entitlements` carries HealthKit,
`com.apple.developer.healthkit.background-delivery` (added 2026-09-12 for
run notifications; build 13 confirmed managed signing handles it), and the
App Group `group.me.colinwatson.beerdebt` shared with the widget extension
(`me.colinwatson.beerdebt.widget`, App ID `F9X9Z3V5MJ`, App Groups capability
enabled on both App IDs via the API). Xcode Cloud's managed signing
registered the group and produced profiles for both targets on its own
(build 14); no local Xcode step was needed.

### Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`, so TestFlight
builds don't wait on the encryption questionnaire.

## One-time setup that has to happen in Xcode

App Store Connect's Xcode Cloud page only offers "Open Xcode": the product
and first workflow can only be created from Xcode (the API has no create
endpoint for products). In Xcode with `BeerDebt.xcodeproj` open:

1. **Product → Xcode Cloud → Create Workflow…**
2. Product: **BeerDebt**. Next.
3. Review the suggested workflow. Next.
4. Grant access: GitHub is already connected with all-repositories access,
   so this step just confirms `watsoncolin/beer-debt-ios`.
5. **Complete**. Skip the "start build now" prompt or let it run.

Done 2026-09-12. Product `0B85EC3A-FCC0-4087-9177-ED5D4DA84425`, workflow
`Default` (`BD7D47C2-1E73-4C9E-83AC-74361E8D713C`). The workflow can be edited
from Xcode, App Store Connect, or the API (App Store Connect API key
`S66786J7HF`, issuer in App Store Connect → Users and Access → Integrations).
