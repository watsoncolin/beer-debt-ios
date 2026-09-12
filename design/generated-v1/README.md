# Beer Debt asset handoff — v1

Created 2026-09-12 from the Beer Debt App Idea conversation and `docs/concept.png`, using built-in image generation. Exact prompts are in `PROMPTS.md`.

## Assets

| File | Dimensions | Use |
| --- | --- | --- |
| `icons/beer-trail-1024.png` | 1024 × 1024, opaque | Recommended app/store icon: winding trail integrated into beer mug |
| `icons/classic-mug-1024.png` | 1024 × 1024, opaque | Alternative closest to original concept |
| `icons/*-master.png` | 1254 × 1254, opaque | Original generation masters |
| `illustrations/home-backdrop.png` | 846 × 1859, opaque | Full-screen mountain and trail backdrop |
| `illustrations/debt-free-trophy.png` | 1254 × 1254, alpha | Debt-free celebration overlay |

## Integration

Assets are staged here so the concurrent MVP implementation can adopt them without source-file conflicts. Existing app icon and Swift files have not been replaced. These files are not wired into the app or committed.

- App icon: choose one 1024 export and pass it through the shared `~/app-utils/apps/beerdebt/` release-asset workflow described in `CLAUDE.md`. That app config does not exist yet. Exports have square corners, full backgrounds, and no alpha; retain system corner masking.
- Background: import as `HomeBackdrop` in the asset catalog. `BeerDebt/Theme/Theme.swift` already loads that name and applies 0.6 opacity. Use aspect-fill and confirm crop/contrast on supported devices. Generated background is 846 px wide; assess on a physical device before release.
- Trophy: import as `DebtFreeTrophy` with original rendering and fit scaling, approximately 180–240 pt wide. Transparency is present; inspect the textured edges over the actual forest background.
- Keep text, balance values, buttons and celebration copy native. None is baked into the artwork.

## Validation

Visually reviewed all four generated images. Verified PNG dimensions and alpha metadata with macOS `sips`: both store-icon exports are exactly 1024 × 1024 with no alpha; trophy has alpha. Original master files preserved. No app build was needed because no app source or live catalog was changed. Store upload and in-app rendering have not been tested.

Palette follows existing Theme values: forest #14201D / #1E2E2A, gold #F5BA42, cream #F6F0E4. Artwork uses tonal variations.
