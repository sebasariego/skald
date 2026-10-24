#!/bin/zsh
# Compiles the vendored tree-sitter runtime and grammars into object files, skipping
# any object that is newer than its source. Prints the object paths, one per line.
# Usage: Scripts/compile-c-sources.sh <object dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OBJ_DIR="$1"
mkdir -p "$OBJ_DIR"
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
[ -d Skald/Vendor/TreeSitter/src ] || exit 0
for src in Skald/Vendor/TreeSitter/src/*.c $(find Skald/Vendor/Grammars -name '*.c' | sort); do
  obj="$OBJ_DIR/$(echo "$src" | tr '/' '_' | sed 's/\.c$/.o/')"
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
    clang -c -std=gnu11 -O2 -g -isysroot "$SDK" -target arm64-apple-macosx14.0 \
      -I Skald/Vendor/TreeSitter/include -I Skald/Vendor/TreeSitter/src \
      -Wno-unused-but-set-variable "$src" -o "$obj" 2>&1 | grep -v xcrun_db >&2 || true
    [ -f "$obj" ] || { echo "failed to compile $src" >&2; exit 1; }
  fi
  echo "$obj"
done
