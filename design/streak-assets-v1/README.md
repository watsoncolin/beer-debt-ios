# Streak artwork

Three square transparent PNGs generated with built-in image_gen, matching the existing warm painted mug/trophy style. All are 1254 × 1254 with alpha; no text is baked into the images.

- `streak-flame-lit.png`: gold/orange upright flame with warm inner core and ember base.
- `streak-flame-unlit.png`: grey extinguished counterpart with a smoke curl.
- `streak-activated.png`: forest-green and cream running shoe, gold sole, heel flame and short celebration rays.

Suggested asset names: StreakFlameLit, StreakFlameUnlit, StreakActivated. Use original rendering and aspect-fit. Native copy and streak logic remain the coding agent's responsibility; the engineering handoff was read for context only.

The flames have matching square canvases and similar silhouette/width, but generation shifted the unlit body downward to accommodate smoke. They are not pixel-registered: adjust vertical placement when swapping if exact body alignment is required. Inspect at the intended 40 pt size in the app. The shoe should use similar presentation width to DebtFreeTrophy.

Validated PNG size and alpha metadata and visually inspected artwork. No app integration or simulator test performed. The rejected opaque-checkerboard unlit attempt is not included.
