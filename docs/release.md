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

Created 2026-09-12. Nothing in the listing (screenshots, description,
privacy) is filled in yet; those are needed for external TestFlight and
App Review, not for internal TestFlight.

## Xcode Cloud workflow

Copied from Pawfect Edit's `Default` workflow:

- **Start condition:** push to `main` (exact match), auto-cancel superseded
  builds.
- **Environment:** Xcode "Latest Release", macOS "Latest Release", clean build.
- **Actions:** `Test - iOS` (scheme `BeerDebt`, one iPhone simulator, required
  to pass) then `Archive - iOS` (scheme `BeerDebt`, TestFlight and App Store
  eligible, required to pass). Pawfect Edit has only the archive; the test
  action is the one addition, because the engine tests are the product.
- **Post-action:** the archive lands in TestFlight automatically. Add
  internal testers under TestFlight in App Store Connect.

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

After that, the workflow can be edited from Xcode, App Store Connect, or
the API (App Store Connect API key `S66786J7HF`, issuer in App Store Connect
→ Users and Access → Integrations).
