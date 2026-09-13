# Beer Debt

## Product Summary

Beer Debt is a deliberately simple iPhone app that creates an accountability economy between drinking beer and running.

The core rule:

**Drink beer → owe miles.  
Run miles → pay for beer.  
Ignore debt → it grows.  
Bank too much credit → it fades.**

The app is meant to be funny, lightweight, and slightly punitive. It is not a general fitness tracker, calorie tracker, sobriety app, or health dashboard.

The MVP should focus exclusively on:

**Beer ↔ running miles**

The underlying model may eventually support arbitrary vices/rewards, but do not generalize the UI or architecture unnecessarily for MVP.

---

# 1. Core Experience

The app has a balance.

The balance can exist in one of three states:

### Credit

The user has run more miles than required and has prepaid for future beers.

Example:

**🍺 2.4 BEERS BANKED**

Credit is capped and decays over time so users cannot accumulate an effectively permanent beer allowance.

### Even

The user owes nothing and has no meaningful credit.

Example:

**BOOKS ARE CLEAN**

### Debt

The user has consumed more beer than their available credit covers.

Example:

**7.3 MI OWED**

Debt accrues interest after a configurable grace period.

Running automatically pays down debt.

---

# 2. Default Rules

Start with these defaults but make them configurable in Settings.

| Setting | Default |
|---|---:|
| Miles per beer | 1.0 mi |
| Maximum beer credit | 3 beers |
| Credit decay | 10% / week |
| Debt grace period | 24 hours |
| Debt interest | 10% / week |
| Running source | Apple Health |
| Debt repayment | Oldest debt first |

Exact interest/decay implementation should be deterministic and calculated from stored events rather than requiring background timers.

---

# 3. Adding a Beer

The primary user action is a large:

**🍺 + BEER**

button.

Tapping it immediately records one beer.

Do not require additional confirmation for the normal case.

If the user has credit, consume credit first.

Example:

Current credit:

**2.0 beers**

Tap + Beer:

**1.0 beer banked**

If the user has no credit:

Current balance:

**0**

Tap + Beer:

**1.0 mi owed**

If partially covered:

Current credit:

**0.4 beers**

Tap + Beer:

0.4 beer is covered by credit and the remaining 0.6 creates debt equivalent to:

**0.6 mi owed**

The transaction should be recorded with a timestamp.

---

# 4. Running

Running is imported from Apple Health / HealthKit.

The user cannot manually enter repayment miles.

This is intentional: the app should keep the user honest.

Only actual running workouts should count. Do not use general walking/running distance because normal daily walking should not accidentally repay beer debt.

For each imported workout store enough information to prevent the same HealthKit workout from being applied twice.

Example:

**🏃 3.2 mi**
Sep 12 · 7:31 AM  
Applied to Beer Debt

Running should be applied in this order:

1. Pay outstanding debt.
2. If debt reaches zero, convert remaining running distance into beer credit.
3. Stop earning credit once the configured credit cap is reached.
4. Excess running beyond the cap disappears; do not maintain hidden/unlimited credit.

Example:

Debt = 1.0 mi

User runs = 3.0 mi

Miles per beer = 1.0

Result:

- 1.0 mi pays debt
- remaining 2.0 mi becomes 2 beers of credit

---

# 5. Debt Model

Beer debt should retain enough information to know when the debt originated.

Conceptually:

```text
BeerDebt
- id
- createdAt
- originalMiles
- remainingPrincipal
```

Interest begins after the configured grace period.

Example:

Beer added Monday at 8 PM.

Grace period = 24 hours.

No interest until Tuesday at 8 PM.

After that, outstanding debt accrues according to the configured interest rules.

Interest should only apply to unpaid debt.

Do not mutate balances every hour/day with background jobs.

Instead, calculate the effective current debt from:

- creation timestamp
- repayment events
- configured interest rules
- current time

Persist transactions/events rather than repeatedly updating a derived balance.

The implementation should remain deterministic so rebuilding the ledger produces the same balance.

---

# 6. Debt Repayment

Runs pay the oldest outstanding beer debt first: FIFO.

Example:

```text
Beer #39    1.00 mi
Beer #40    1.10 mi
Beer #41    1.21 mi
```

A 2.5-mile run should completely pay Beer #39, completely or partially pay Beer #40 depending on calculated interest, and then continue to Beer #41 if mileage remains.

The exact accounting implementation can differ if a simpler event-ledger approach produces equivalent behavior.

The important user-visible behavior is:

**oldest beer debt disappears first.**

---

# 7. Beer Credit

When the user runs without debt, miles become beer credit.

Credit should be represented to the user primarily in beers rather than miles.

Example:

**🍺 2.5 BEERS BANKED**

Internally it may be easier to keep everything in miles.

Given:

```text
milesPerBeer = 1
creditMiles = 2.5
```

display:

```text
2.5 beers
```

If:

```text
milesPerBeer = 0.5
creditMiles = 1.0
```

display:

```text
2 beers
```

---

# 8. Credit Cap

Users cannot bank unlimited running.

Default:

**Maximum credit = 3 beers**

If the user already has 3 beers banked and runs another 5 miles, the additional mileage does not create additional credit.

This is intentional.

The app is aimed at someone who drinks somewhat regularly and wants a fun accountability mechanism.

It is not designed to reward a high-mileage runner with months of prepaid beer.

---

# 9. Credit Decay

Unused beer credit should gradually lose value.

Default:

**10% per week**

This prevents someone from accumulating credit and sitting on it indefinitely.

The calculation should be timestamp-based and deterministic, just like debt interest.

Do not require scheduled background execution for correctness.

The UI can communicate this as:

**2.4 beers banked**

*Credit slowly expires.*

Potential future UI:

**Run or drink soon — 0.2 beer credit expires this week.**

Do not build elaborate notifications for MVP unless trivial.

---

# 10. Home Screen

This is the primary product.

Keep it extremely simple.

### Debt state

```text
BEER DEBT

7.3 MI
OWED

6.5 principal
0.73 a day

[ 🍺 + BEER ]

🏃 3.2 mi paid this week

Your tab is getting expensive.
```

The second figure is the **rate**, not the running total: what one compounding
period adds to the open tab at the rate in force, which is the outstanding
amount times the interest rate. It carries the period's own words, so a weekly
setting reads "a week". Interest-to-date is a number that barely moves once it
is there; what standing still costs is the thing the product is about, and it
is what a run prevents.

While today is interest-protected by a running streak (§25) the figure is
struck through and lit with the flame, so it reads as what the streak just
saved. The condition is *today* being protected, not merely having a streak
alive: a streak carried from yesterday pauses nothing until today has its
mile, and showing the charge live is exactly the nudge the streak card
underneath then spells out.

The standing totals (principal, interest to date) move to **Your Debt**, in a
panel above the list, next to the beers they came from.

### Credit state

```text
BEER DEBT

🍺 2.4
BEERS BANKED

[ 🍺 + BEER ]

🏃 5.7 mi run this week

You've earned a couple.
```

### Even state

```text
BEER DEBT

0

BOOKS ARE CLEAN

[ 🍺 + BEER ]

Drink now. Run later.
```

The balance should visually dominate the screen.

Do not clutter the home screen with charts, calories, streaks, health metrics, etc.

---

# 11. Add Beer Feedback

After adding a beer, show brief feedback.

Example:

```text
🍺

Beer added!

That's +1.0 mi
(for now...)

If you don't run it off,
interest starts tomorrow.
```

This could be a sheet, animation, toast, or transient overlay.

Do not make the user dismiss multiple screens every time they drink.

Adding a beer should remain fast enough to do from a bar.

---

# 12. The Ledger

Secondary screen:

**The Ledger**

Show chronological beer and running transactions.

Examples:

```text
TODAY

🍺 Beer
+1.0 mi debt
8:13 PM

🏃 Run
-3.2 mi debt
7:21 AM
Apple Health


YESTERDAY

🍺 Beer
PAID
9:42 PM
```

A totals panel sits above the list: total owed, then principal, interest to
date, and the per-period rate. In credit it reads banked beers, the miles
behind them, and what expires this week; on clean books, just that.

Individual beer debts can optionally expose:

- original principal
- accrued interest
- current amount
- age
- paid / unpaid status

Keep this secondary to the main balance.

---

# 13. Settings

MVP settings:

### Miles per Beer

Default:

**1 beer = 1.0 mile**

Allow reasonable presets and/or custom entry.

Examples:

- 0.5 mi
- 1.0 mi
- 2.0 mi
- Custom

### Debt Interest

Default:

**10% weekly**

Allow disabling interest.

### Grace Period

Default:

**24 hours**

Possible options:

- None
- 24 hours
- 48 hours
- 7 days

### Maximum Credit

Default:

**3 beers**

### Credit Decay

Default:

**10% weekly**

Allow disabling decay if desired.

### Apple Health

Display connection/authorization state.

Explain:

**Only running workouts count toward your balance.**

---

# 14. HealthKit Requirements

Use HealthKit to retrieve running workouts and associated distance.

The app needs permission to read the minimum required HealthKit data.

Do not request unnecessary health permissions.

Important requirements:

- Count running workouts only.
- Capture HealthKit workout identifiers to prevent duplicate processing.
- Handle HealthKit authorization denial gracefully.
- Sync newly available workouts when the app becomes active.
- Reconciliation should be idempotent.
- Distances should be normalized internally to a consistent unit.
- Display miles for MVP.

The balance should never accidentally change because the same workout was imported twice.

---

# 15. Local-First Architecture

MVP should be local-first.

Do not add:

- authentication
- Firebase
- backend APIs
- accounts
- cloud databases
- subscriptions

unless a technical requirement emerges that makes one necessary.

The app should work entirely on the user's iPhone.

Use local persistence appropriate to the selected iOS architecture.

HealthKit is the external source of truth for running workouts.

---

# 16. Ledger / Event Model

Prefer an event-driven model rather than storing only the current balance.

Potential events:

```text
BeerAdded
RunImported
SettingsChanged
```

Possible persisted models:

```text
BeerEntry
- id
- createdAt
- milesPerBeerAtCreation

RunEntry
- id
- healthKitWorkoutId
- startedAt
- distanceMiles
- importedAt

Settings
- milesPerBeer
- debtInterestRate
- debtGracePeriod
- maximumBeerCredit
- creditDecayRate
```

Important: consider whether settings changes should affect historical transactions.

Recommended behavior:

**Snapshot relevant rules at transaction creation when changing them retroactively would produce surprising results.**

For example, changing miles per beer from 1.0 to 2.0 should not suddenly double the debt from beers consumed last week.

The same principle should be considered for interest and decay rules.

Choose a deterministic implementation and document the behavior.

---

# 17. Balance Engine

Keep financial/accounting calculations isolated from UI code.

Something conceptually like:

```text
BalanceEngine
    calculateBalance(
        beers,
        runs,
        settings,
        at: Date
    ) -> Balance
```

Possible output:

```text
Balance
- state: credit | even | debt
- debtMiles
- principalMiles
- interestMiles
- creditMiles
- creditBeers
```

The balance engine should be pure enough to unit test extensively.

Tests are especially important for:

- partial debt repayment
- multiple beers
- FIFO repayment
- interest
- grace periods
- credit generation
- credit cap
- credit decay
- partial credit consumption
- crossing from credit → debt
- crossing from debt → credit
- settings changes
- duplicate HealthKit workouts
- time-zone/date edge cases

---

# 18. Design Direction

The app should feel like a ridiculously serious financial app for an unserious liability.

Think:

**personal finance app × running app × neighborhood bar**

Visual language can use:

- beer gold
- dark green
- cream
- bold typography
- subtle outdoors/running imagery
- financial terminology

Avoid making it look like a frat-house drinking app.

The humor should come primarily from treating beer mileage like legitimate financial debt.

Useful language:

**Beer Debt**

**The Ledger**

**Principal**

**Interest**

**Credit**

**Your tab**

**Books are clean**

**Debt free**

**You've earned one.**

**Your drinking is currently outpacing your running.**

**This beer is getting expensive.**

---

# 19. Working Product Copy

Tagline:

**Drink now. Run later.**

Alternate:

**Every beer has a price. Yours is measured in miles.**

Debt:

**7.3 MI OWED**

Credit:

**2.4 BEERS BANKED**

Zero:

**BOOKS ARE CLEAN**

Debt-free celebration:

**DEBT FREE**

**Nice work. Your tab is paid.**

---

# 20. MVP Screens

Build only:

1. **Home**
2. **The Ledger**
3. **Settings**
4. Minimal HealthKit onboarding/permission flow

Sheets/modals can handle adding beer feedback and transaction details.

Do not create a large tab-bar architecture unless it improves the implementation.

---

# 21. Explicitly Out of Scope

Do NOT build these during the initial weekend MVP:

- Multiple vice types
- Food tracking
- Alcohol unit calculations
- Calorie calculations
- BAC estimation
- Social feed
- Friends
- Challenges
- Leaderboards
- Accounts
- Cloud sync
- Android
- Apple Watch app
- Strava
- Achievements
- Complex notifications
- AI
- Monetization
- Subscription infrastructure

These are future possibilities, not MVP requirements.

---

# 22. Future Possibilities

Do not implement yet, but avoid making them unnecessarily impossible:

### Other vice contracts

Examples:

```text
🍕 Pizza → running
🍩 Donut → running
🍺 Beer → cycling
```

The eventual abstraction could be:

**Vice → consequence**

But Beer Debt should remain opinionated for launch.

### Widgets

Home Screen / Lock Screen:

```text
🍺 BEER DEBT

7.3 mi owed

+0.6 mi interest
```

### Notifications

Examples:

**Your beer debt just grew. You're now at 7.8 mi.**

**Run 2.1 mi today before interest hits.**

### Apple Watch

Potential quick Beer button and balance complication.

Do not build for MVP.

---

# 23. MVP Acceptance Criteria

The MVP is successful when the following flow works reliably:

1. Fresh install.
2. User configures or accepts default rules.
3. User grants HealthKit access.
4. User taps **+ Beer**.
5. Balance becomes 1 mile of debt.
6. User adds more beers and debt increases correctly.
7. Time passes and interest is reflected correctly.
8. User records a legitimate running workout.
9. App imports that workout from HealthKit.
10. Running automatically pays debt.
11. Extra running becomes beer credit.
12. Credit cannot exceed its configured cap.
13. Credit diminishes correctly over time.
14. Drinking consumes existing credit before creating debt.
15. The same HealthKit workout can never be counted twice.
16. Killing/reopening the app produces exactly the same calculated balance.

If those sixteen things work and the UI feels fun, **ship the TestFlight build.**

---

# 24. Implementation Principle

When choosing between:

**more features**

and

**making + Beer → debt → interest → run → repayment feel delightful**

choose the second one.

This app succeeds or fails on that loop.

The weekend version should be small enough that the developer actually uses it at a bar Saturday night and sees their run automatically pay the tab Sunday morning.

# 25. Running Streaks

Added 2026-09-12 from the "Running Streaks" handoff. Rewards consistency
without touching what is owed.

- A **streak day** is a local calendar day with at least 1.0 mile of verified
  running (HealthKit / Health Connect; runs on the same day add up; a metre of
  GPS slack is allowed, so a watch that says 1.00 mi counts).
- Day one starts the streak. From day two on, each qualifying day is
  **interest-protected**: interest postings that fall on that day are
  skipped. Nothing already accrued is refunded, principal is untouched, credit
  decay continues, and runs still repay debt as before.
- A day under a mile ends the streak; the next qualifying day is day one
  again. No freezes, rest days, or manual fixes.
- Days follow the user's calendar, not 24-hour windows. The streak is
  derived from the runs on the books every time the ledger is replayed, so a
  late import or a deleted run simply changes the answer, including for
  earlier today (a run this evening removes the posting that landed this
  morning).
- Protection is a rule (`streakProtection`) so it switches on forward-only:
  ledgers from before the feature keep their history and turn it on at
  upgrade. Not user-tunable.
- Streaks live alongside debt and credit: they survive a zero balance, a
  credit balance, and a new beer.

**Copy.** The bank's voice, not a fitness app's: "5 day streak", "0% APR —
earned", "Interest paused", "Run 1+ mile tomorrow to unlock 0% APR", "Start a
streak". Never "You're crushing it".

**Screens.** A streak card on Home under the balance (no streak: quiet and
dashed; day one: lit, nothing earned yet; two or more: earned). Tapping it
opens **Your Streak**: the count, what it has earned, this calendar week as
seven circles, longest streak, total streak days, and the rule in four
lines. Beer Added mentions an earned streak. Run rows in Runs get a "Day N" tag once their streak
reached two days (a lone mile is tagged nothing). The run notification adds a streak line, and the moment day two
activates protection gets its own sheet (the running-shoe art), paired with
Debt Free.

**Out of scope for now:** streak on the widget and in the weekly summary,
reminders when a streak is at risk, any reward beyond the paused interest.
