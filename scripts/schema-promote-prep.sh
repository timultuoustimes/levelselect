#!/usr/bin/env bash
# Prepare the Mac for a CloudKit schema promote — the risky half, automated.
#
# Seeding must run on a DEVELOPMENT build, because only the Development
# environment creates fields from writes. But a Development build opens the
# REAL library and syncs it into the Development database, which is the
# entanglement that cost 2026-09-02 an hour. So the real store is copied, then
# moved aside, and the Development build gets an empty store of its own.
#
#   scripts/schema-promote-prep.sh     → back up, move aside, build Development
#   scripts/schema-promote-done.sh     → restore the real store, build Production
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GROUP="$HOME/Library/Group Containers/group.com.timultuoustimes.levelselect/Library/Application Support"
STAMP=$(date +%Y-%m-%d-%H%M)
BACKUP="$HOME/LevelSelect-store-backups/pre-promote-$STAMP"
ASIDE="$GROUP/_promote-aside"

step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

step "1/4 Is the Mac app closed?"
if ps -Ao command= | grep -v CoreSimulator | grep -v grep | grep -q "LevelSelect.app/Contents/MacOS"; then
  echo "LevelSelect is running. Quit it first — a live app re-uploads whatever it holds." >&2
  exit 1
fi
echo "Not running."

step "2/4 Back up the real library BY COPY"
mkdir -p "$BACKUP"
cp -p "$GROUP"/default.store* "$BACKUP"/ 2>/dev/null || true
COUNT=$(sqlite3 "$BACKUP/default.store" "select count(*) from ZGAME where ZDELETEDAT is null;" 2>/dev/null || echo "?")
echo "$BACKUP  ($COUNT games)"
[ "$COUNT" = "?" ] && { echo "Could not verify the backup. Stopping." >&2; exit 1; }

step "3/4 Move the real store aside"
mkdir -p "$ASIDE"
mv "$GROUP"/default.store* "$ASIDE"/ 2>/dev/null || true
echo "Parked at $ASIDE — the Development build will make its own empty store."

step "4/4 Build the DEVELOPMENT Mac app"
cd "$ROOT/native/LevelSelect"
xcodebuild -project LevelSelect.xcodeproj -scheme LevelSelect \
  -configuration Debug -destination 'platform=macOS' \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData"/LevelSelect-*/Build/Products/Debug -maxdepth 1 -name "LevelSelect.app" | head -1)
ENV=$(codesign -d --entitlements :- "$APP" 2>/dev/null | grep -o 'icloud-container-environment</key><string>[A-Za-z]*' | sed 's/.*>//')
echo "Container environment: $ENV"
[ "$ENV" = "Development" ] || { echo "Expected Development. Stopping." >&2; exit 1; }

cat <<NEXT

Ready. Now, in order:

  1. open "$APP"
  2. Settings → Seed CloudKit schema
  3. CloudKit Console → Development → confirm BOTH:
       • record type  CD_Memory
       • field        CD_GameImage.memory
  4. Deploy Schema Changes → Production
  5. Settings → Purge seed records
  6. Quit LevelSelect
  7. scripts/schema-promote-done.sh

NEXT
