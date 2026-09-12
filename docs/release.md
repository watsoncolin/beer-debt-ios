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

Left before "Add for Review": the review contact's phone number (the API
refuses to save the contact without it), and an on-device pass with a real
run. Submission itself can go through the API (`reviewSubmissions`) or the
button.

## Xcode Cloud workflow

Copied from Pawfect Edit's `Default` workflow (compared setting by setting on
2026-09-12; the only Pawfect-specific parts not copied are its Sentry
environment variables and post-xcodebuild dSYM upload, which Beer Debt has no
use for):

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
committed project can never ship. There is no post-xcodebuild script: unlike
Pawfect Edit there is no Sentry, and nothing to upload.

### Versioning

- `MARKETING_VERSION` in `project.yml` is the App Store version. Bump it by
  hand when starting a new release.
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
