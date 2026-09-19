#!/usr/bin/env bash
# Put the Mac back after a promote: restore the real library, return to Production.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GROUP="$HOME/Library/Group Containers/group.com.timultuoustimes.levelselect/Library/Application Support"
ASIDE="$GROUP/_promote-aside"

step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

step "1/3 Is the Mac app closed?"
if ps -Ao command= | grep -v CoreSimulator | grep -v grep | grep -q "LevelSelect.app/Contents/MacOS"; then
  echo "LevelSelect is running. Quit it first." >&2; exit 1
fi
echo "Not running."

step "2/3 Restore the real library"
[ -f "$ASIDE/default.store" ] || { echo "Nothing parked at $ASIDE." >&2; exit 1; }
rm -f "$GROUP"/default.store*            # the throwaway seeding store
mv "$ASIDE"/default.store* "$GROUP"/
rmdir "$ASIDE" 2>/dev/null || true
COUNT=$(sqlite3 "$GROUP/default.store" "select count(*) from ZGAME where ZDELETEDAT is null;")
echo "Restored: $COUNT games"

step "3/3 Build the PRODUCTION Mac app"
cd "$ROOT/native/LevelSelect"
xcodebuild -project LevelSelect.xcodeproj -scheme LevelSelect \
  -configuration Debug -destination 'platform=macOS' \
  LS_CK_ENV=Production -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData"/LevelSelect-*/Build/Products/Debug -maxdepth 1 -name "LevelSelect.app" | head -1)
ENV=$(codesign -d --entitlements :- "$APP" 2>/dev/null | grep -o 'icloud-container-environment</key><string>[A-Za-z]*' | sed 's/.*>//')
echo "Container environment: $ENV"
[ "$ENV" = "Production" ] || { echo "Expected Production — do NOT open it." >&2; exit 1; }
echo "Safe to open. The phones can take the V5 build once you confirm sync is clean."
