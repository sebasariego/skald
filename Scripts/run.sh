#!/bin/zsh
# Builds Quill with xcodebuild (Debug) into DerivedData/xcode, quits any running copy,
# and launches the fresh build. Needs to run outside the Claude sandbox.
# Usage: Scripts/run.sh [--no-launch]
set -euo pipefail
cd "$(dirname "$0")/.."

LOG=DerivedData/xcode/build.log
mkdir -p DerivedData/xcode
xcodebuild build -project Quill.xcodeproj -scheme Quill -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./DerivedData/xcode > "$LOG" 2>&1 && rc=0 || rc=$?
grep -E "error:|warning: .*/Quill/[A-Z]" "$LOG" | grep -v "Vendor/" || true
if [ "$rc" -ne 0 ]; then
  echo "xcodebuild failed ($rc); see $LOG"
  exit "$rc"
fi
APP=DerivedData/xcode/Build/Products/Debug/Quill.app
echo "Built $APP"
[ "${1:-}" = "--no-launch" ] && exit 0

# Ask a running copy to quit politely (it prompts for unsaved changes), then launch.
if pgrep -xq Quill; then
  osascript -e 'tell application id "dev.local.quill" to quit' >/dev/null 2>&1 || true
  for _ in {1..40}; do pgrep -xq Quill || break; sleep 0.25; done
fi
open "$APP"
echo "Launched Quill"
