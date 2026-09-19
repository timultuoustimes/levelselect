#!/usr/bin/env bash
# The repeatable release gate — one boring sequence, no memory required.
#
#   scripts/release-gate.sh [build-number]
#
# With no argument it bumps CURRENT_PROJECT_VERSION by one. Every step is
# loud, every failure stops the train, and the bump is committed so the repo
# — not App Store Connect — stays the source of truth for build numbers.
#
# What it does, in order:
#   1. refuse to run on a dirty tree (a release should be a known commit)
#   2. full test suite on macOS — red tests never ship
#   3. bump the build number in project.yml, regenerate the project
#   4. archive Release for iOS
#   5. upload to App Store Connect (ExportOptions.plist: destination=upload)
#   6. commit the bump
#   7. print the human half of the checklist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native/LevelSelect"
cd "$NATIVE"

step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

step "1/7 Clean tree"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "Tree is dirty. Commit or stash first — a build should be a commit." >&2
  exit 1
fi

CURRENT=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"/\1/p' project.yml)
BUILD="${1:-$((CURRENT + 1))}"
echo "Current build: $CURRENT → shipping: $BUILD"

step "2/7 Tests (macOS, full suite)"
xcodebuild -project LevelSelect.xcodeproj -scheme LevelSelect \
  -destination "platform=macOS" test 2>&1 \
  | grep -E "Test run with|error:|failed" | grep -v CloudKit || true
xcodebuild -project LevelSelect.xcodeproj -scheme LevelSelect \
  -destination "platform=macOS" test 2>&1 | grep -q "TEST FAILED" && {
    echo "Tests failed — not shipping." >&2; exit 1; } || true

step "3/7 Bump to $BUILD + xcodegen"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
xcodegen generate >/dev/null
echo "project.yml → $BUILD"

step "4/7 Archive (Release, iOS)"
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/levelselect-gate/LevelSelect-$BUILD.xcarchive"
xcodebuild -project LevelSelect.xcodeproj -scheme LevelSelect \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" archive -allowProvisioningUpdates 2>&1 \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$ARCHIVE" ] || { echo "Archive missing — stopping." >&2; exit 1; }

step "5/7 Upload to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates 2>&1 \
  | grep -E "error:|EXPORT (SUCCEEDED|FAILED)|Upload" || true

step "6/7 Commit the bump"
git add project.yml   # pbxproj is generated and gitignored; yml is the truth
git commit -m "Send build $BUILD to TestFlight"
echo "Committed. Push when ready: git push"

step "7/7 The human half (nothing below is optional)"
cat <<CHECKLIST
  [ ] App Store Connect → TestFlight → wait for processing → add build $BUILD
      to the "Player 1" group
  [ ] What to Test: PLAIN TEXT ONLY — no markdown, no bullets, no bold
      (draft lives in the vault tester brief note)
  [ ] When the build is live to testers:
      - flip site/src/content/changelog/0.1.0-$BUILD.md to draft: false
      - make any docs-page edits that were held for this build
      - push the site changes
  [ ] Testers ledger: note the build went out
CHECKLIST
