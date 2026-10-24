#!/bin/zsh
# Dev loop: builds Skald (Debug) into DerivedData/xcode, quits any running copy,
# and launches the build-folder copy. For the installed app use Scripts/install.sh.
# Usage: Scripts/run.sh [--no-launch]
set -euo pipefail
cd "$(dirname "$0")/.."

LOG=DerivedData/xcode/build.log
mkdir -p DerivedData/xcode
xcodebuild build -project Skald.xcodeproj -scheme Skald -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./DerivedData/xcode > "$LOG" 2>&1 && rc=0 || rc=$?
grep -E "error:|warning: .*/Skald/[A-Z]" "$LOG" | grep -v "Vendor/" || true
if [ "$rc" -ne 0 ]; then
  echo "xcodebuild failed ($rc); see $LOG"
  exit "$rc"
fi
APP=DerivedData/xcode/Build/Products/Debug/Skald.app
echo "Built $APP"
[ "${1:-}" = "--no-launch" ] && exit 0

# Ask a running copy to quit politely (it prompts for unsaved changes), then launch.
if pgrep -xq Skald; then
  osascript -e 'tell application id "dev.local.skald" to quit' >/dev/null 2>&1 || true
  for _ in {1..40}; do pgrep -xq Skald || break; sleep 0.25; done
fi
open "$APP"
echo "Launched Skald"
