#!/bin/zsh
# One-time migration of preferences from the app's previous identity (Quill, bundle id
# dev.local.quill) to Skald (dev.local.skald). Sandboxed apps keep their preferences in
# their own container, which the renamed app cannot read, so the copy happens here.
#
# Run this once, with Skald NOT running, after launching Skald at least once (so its
# container exists). Session bookmarks (open folder and tabs) cannot be migrated: they are
# security-scoped to the old bundle identifier. Reopen the folder once.
set -euo pipefail

OLD="$HOME/Library/Containers/dev.local.quill/Data/Library/Preferences/dev.local.quill.plist"
NEW_DIR="$HOME/Library/Containers/dev.local.skald/Data/Library/Preferences"
NEW="$NEW_DIR/dev.local.skald.plist"

if pgrep -xq Skald; then
  echo "Quit Skald first, then run this again."; exit 1
fi
if [ ! -f "$OLD" ]; then
  echo "No Quill preferences found at $OLD; nothing to migrate."; exit 0
fi
if [ ! -d "$NEW_DIR" ]; then
  echo "Skald has not created its container yet. Launch Skald once, quit it, and run this again."; exit 1
fi
if [ -f "$NEW" ] && defaults read "${NEW%.plist}" dev.local.skald.settings >/dev/null 2>&1; then
  echo "Skald already has settings; leaving them alone."; exit 0
fi

# Skald reads the Quill-era keys itself, so the plist can be imported as is.
defaults import "${NEW%.plist}" "$OLD"
echo "Copied Quill preferences into Skald's container. Launch Skald to pick them up."
