#!/bin/sh

# Uploads dSYMs to Sentry after a successful Xcode Cloud archive, so crash and
# app-hang stack traces arrive symbolicated instead of as raw offsets like
# "BeerDebt +0x14cc94". Same script as Pourcraft and Pawfect Edit.
#
# Requires these environment variables, added as build variables on the Xcode
# Cloud workflow (App Store Connect → Xcode Cloud → workflow → Edit →
# Environment; mark the token as secret):
#   SENTRY_AUTH_TOKEN  - a Sentry Organization Token, or a Personal Token with
#                        the project:write and org:read scopes.
#                        NOTE: add this variable through App Store Connect on
#                        the web. Xcode's own environment-variable editor
#                        rejects the ~195-char org token with "Failed to save
#                        ... due to invalid value"; the web UI saves it fine.
#   SENTRY_ORG         - pawfect-edit
#   SENTRY_PROJECT     - beer-debt-ios
#
# A failed or skipped upload logs loudly but never fails the build.

echo "--- Sentry dSYM upload ---"

if [ "$CI_XCODEBUILD_EXIT_CODE" != "0" ]; then
    echo "Skipping: xcodebuild exited with ${CI_XCODEBUILD_EXIT_CODE}"
    exit 0
fi

if [ -z "$CI_ARCHIVE_PATH" ]; then
    echo "Skipping: not an archive build (CI_ARCHIVE_PATH is unset)"
    exit 0
fi

if [ -z "$SENTRY_AUTH_TOKEN" ] || [ -z "$SENTRY_ORG" ] || [ -z "$SENTRY_PROJECT" ]; then
    echo "⚠️  Skipping: SENTRY_AUTH_TOKEN, SENTRY_ORG or SENTRY_PROJECT is not set"
    echo "⚠️  Stack traces for this build will NOT be symbolicated."
    exit 0
fi

DSYM_PATH="${CI_ARCHIVE_PATH}/dSYMs"

if [ ! -d "$DSYM_PATH" ]; then
    echo "⚠️  Skipping: no dSYMs directory at ${DSYM_PATH}"
    echo "⚠️  Check that DEBUG_INFORMATION_FORMAT is 'dwarf-with-dsym' for this configuration."
    exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "Installing sentry-cli..."
    if ! brew install getsentry/tools/sentry-cli; then
        echo "⚠️  Could not install sentry-cli - dSYMs not uploaded."
        exit 0
    fi
fi

echo "Uploading dSYMs from ${DSYM_PATH}"

if sentry-cli debug-files upload "$DSYM_PATH"; then
    echo "✅ dSYM upload complete"
else
    echo "⚠️  dSYM upload failed - stack traces for this build will NOT be symbolicated."
fi

exit 0
