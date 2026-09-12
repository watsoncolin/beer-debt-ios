#!/bin/bash
# Regenerate docs/engine-fixtures/cases.json from the Swift engine.
# The engine and models are pure Foundation, so this compiles without Xcode's
# simulator: just swiftc. Run after any engine change; commit the result.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPD=$(mktemp -d)
cp "$ROOT/scripts/fixtures.swift" "$TMPD/main.swift"
swiftc -O \
  "$ROOT"/BeerDebt/Engine/*.swift \
  "$ROOT"/BeerDebt/Models/*.swift \
  "$TMPD/main.swift" -o "$TMPD/fixtures"
cd "$ROOT" && "$TMPD/fixtures" docs/engine-fixtures/cases.json
