#!/bin/zsh
# Builds Skald (Release) and installs it into ~/Applications/Skald.app, no admin rights
# needed, then relaunches from there. Launch Services is pointed at the installed copy so
# Finder's "Open With" and default-app bindings use it rather than the build folder.
# Usage: Scripts/install.sh [--debug]     (--debug installs the Debug configuration)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=Release
[ "${1:-}" = "--debug" ] && CONFIGURATION=Debug
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Skald.app"
BUILT="DerivedData/xcode/Build/Products/$CONFIGURATION/Skald.app"
LOG="DerivedData/xcode/install-build.log"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

mkdir -p DerivedData/xcode "$DEST_DIR"
xcodebuild build -project Skald.xcodeproj -scheme Skald -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' -derivedDataPath ./DerivedData/xcode > "$LOG" 2>&1 && rc=0 || rc=$?
grep -E "error:|warning: .*/Skald/[A-Z]" "$LOG" | grep -v "Vendor/" || true
if [ "$rc" -ne 0 ]; then
  echo "xcodebuild failed ($rc); see $LOG"; exit "$rc"
fi
echo "Built $BUILT ($CONFIGURATION)"

# Ask a running copy to quit politely (it prompts for unsaved changes).
if pgrep -xq Skald || pgrep -qf "Skald.app/Contents/MacOS/Skald"; then
  osascript -e 'tell application id "dev.local.skald" to quit' >/dev/null 2>&1 || true
  for _ in {1..40}; do pgrep -xq Skald || break; sleep 0.25; done
fi

# Replace the installed bundle in place; rsync keeps the copy consistent and removes
# files that no longer exist in the new build.
rsync -a --delete "$BUILT/" "$DEST/"
echo "Installed $DEST"

# Prefer the installed copy; forget the build-folder copies so they do not compete.
"$LSREGISTER" -u "$PWD/DerivedData/xcode/Build/Products/Debug/Skald.app" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$PWD/DerivedData/xcode/Build/Products/Release/Skald.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

[ "${SKALD_NO_LAUNCH:-}" = "1" ] && exit 0
open "$DEST"
echo "Launched $DEST"
