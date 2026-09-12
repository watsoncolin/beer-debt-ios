#!/bin/sh
# Xcode Cloud post-clone hook.
#
# BeerDebt.xcodeproj is generated from project.yml via XcodeGen (see CLAUDE.md).
# Regenerate it here so Xcode Cloud always builds the current project rather than
# a possibly-stale committed copy. Homebrew is available on the build machine.
set -e

brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "ci_post_clone: regenerated BeerDebt.xcodeproj"
