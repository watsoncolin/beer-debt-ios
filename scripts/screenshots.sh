#!/bin/bash
# Seed a simulator's Beer Debt install with demo ledgers and screenshot every
# screen. Uses the DEBUG-only `-debugScreen` launch argument (see RootView).
#
#   scripts/screenshots.sh [<simulator-udid>|booted] [<output-dir>]
#
# Build the app for the simulator first (xcodebuild ... build, or run it once
# from Xcode). Re-run anytime; it re-seeds and re-installs.
set -euo pipefail

BUNDLE=me.colinwatson.beerdebt
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:-booted}"
OUT="${2:-$ROOT/docs/screenshots}"
mkdir -p "$OUT"

if [ "$UDID" = "booted" ]; then
  UDID=$(xcrun simctl list devices booted -j | python3 -c \
    "import json,sys; d=json.load(sys.stdin)['devices']; print(next((x['udid'] for r in d.values() for x in r), ''))")
fi
[ -z "$UDID" ] && { echo "No booted simulator. Boot one (or pass a UDID)."; exit 1; }

APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 6 -path "*BeerDebt-*/Build/Products/Debug-iphonesimulator/BeerDebt.app" | head -1)
[ -z "$APP" ] && { echo "No simulator build found. Build BeerDebt for the simulator first."; exit 1; }
xcrun simctl install "$UDID" "$APP"

# The ledger lives in the App Group container (shared with the widget).
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" group.me.colinwatson.beerdebt)
LEDGER="$CONTAINER/BeerDebt/ledger.json"
mkdir -p "$(dirname "$LEDGER")"

seed() { # seed <debt|credit|freeze|restday|fresh>
  if [ "$1" = "fresh" ]; then rm -f "$LEDGER"; return; fi
  python3 - "$LEDGER" "$1" <<'PY'
import json, sys, uuid
from datetime import datetime, timedelta, timezone
path, mode = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc).replace(microsecond=0)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")
H, D = timedelta(hours=1), timedelta(days=1)
rules = {"milesPerBeer": 1.0, "interestRate": 0.1, "interestPeriod": "daily",
         "gracePeriod": 86400.0, "maximumCreditBeers": 3.0, "creditDecayRatePerWeek": 0.1, "streakProtection": True}
# Runs at 07:00 local on given days back, so the streak reads as consecutive calendar days.
local = now.astimezone()
def morning(days_back, miles): return (local.replace(hour=7, minute=12, second=0) - days_back*D).astimezone(timezone.utc), miles
# Freeze applications are keyed to midday of the local day (spec §25.1).
freezes = []
if mode == "debt":
    # Six beers over the week, a three-day streak through this morning: in debt, interest paused.
    beers = [now - 6*D - H, now - 5*D - 2*H, now - 4*D - 3*H, now - 3*D - H, now - 2*D - 2*H, now - 6*H]
    runs = [morning(5, 1.0), morning(2, 1.1), morning(1, 1.2), morning(0, 1.0)]
elif mode == "freeze":
    # Six running days through yesterday earns a freeze, nothing yet today:
    # the "Use Freeze Today" offer, with a live streak and interest paused.
    beers = [now - 6*D - H, now - 5*D - 2*H, now - 4*D - 3*H, now - 3*D - H]
    runs = [morning(n, 1.0 + 0.1*n) for n in range(1, 7)]
elif mode == "restday":
    # Same, with the freeze already spent on today: the rest-day state.
    beers = [now - 6*D - H, now - 5*D - 2*H, now - 4*D - 3*H, now - 3*D - H]
    runs = [morning(n, 1.0 + 0.1*n) for n in range(1, 7)]
    freezes = [local.replace(hour=12, minute=0, second=0).astimezone(timezone.utc)]
else:
    # One beer long paid; runs three days running, nothing yet today: credit, streak alive.
    beers = [now - 6*D]
    runs = [morning(3, 1.0), morning(2, 1.2), morning(1, 2.4)]
ledger = {
  "version": 1,
  "booksOpenedAt": iso(now - 10*D),
  "rulesHistory": [{"effectiveAt": iso(now - 10*D), "rules": rules}],
  "beers": [{"id": str(uuid.uuid4()).upper(), "createdAt": iso(b)} for b in beers],
  "runs": [{"id": str(uuid.uuid4()).upper(), "healthKitWorkoutID": str(uuid.uuid4()).upper(),
            "startedAt": iso(e - timedelta(minutes=32)), "endedAt": iso(e), "distanceMeters": m * 1609.344,
            "importedAt": iso(e + H), "sourceName": "Apple Watch"} for e, m in runs],
  "freezeApplications": [{"id": str(uuid.uuid4()).upper(), "day": iso(d), "appliedAt": iso(d)} for d in freezes],
}
json.dump(ledger, open(path, "w"), indent=2)
PY
}

shoot() { # shoot <file> [debugScreen]
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [ -n "${2:-}" ]; then xcrun simctl launch "$UDID" "$BUNDLE" -debugScreen "$2" >/dev/null
  else xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; fi
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null 2>&1 && echo "✓ $1"
}

xcrun simctl spawn "$UDID" defaults write "$BUNDLE" onboardingComplete -bool false
seed fresh
shoot onboarding
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" onboardingComplete -bool true
seed debt
shoot home-debt
shoot beer-added beerAdded
shoot ledger ledger
shoot beer-detail beerDetail
shoot runs runs
shoot settings settings
shoot streak streak
shoot streak-activated streakActivated
shoot debt-free debtFree
seed freeze
shoot home-freeze
shoot streak-freeze streak
shoot freeze-earned freezeEarned
seed restday
shoot streak-restday streak
shoot home-restday
seed credit
shoot home-credit
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Screenshots in $OUT"
