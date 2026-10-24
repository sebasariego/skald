#!/bin/zsh
# Builds Skald.app with swiftc alone (no xcodebuild), for environments where the
# Xcode build service cannot run. Output: DerivedData/cli/Skald.app
# Usage: Scripts/build-cli.sh [-O]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=DerivedData/cli
APP="$OUT/Skald.app"
OPT="${1:--Onone}"
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
mkdir -p "$OUT/ModuleCache" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(${(f)"$(find Skald -name '*.swift' | sort)"})
OBJECTS=(${(f)"$(Scripts/compile-c-sources.sh "$OUT/obj")"})
C_FLAGS=()
if [ -d Skald/Vendor/TreeSitter/include ]; then
  C_FLAGS=(-I Skald/Vendor/TreeSitter/include -I Skald/Vendor/Grammars/include)
fi

swiftc "${SOURCES[@]}" "${OBJECTS[@]}" "${C_FLAGS[@]}" \
  -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -swift-version 5 -strict-concurrency=targeted \
  -module-name Skald -module-cache-path "$OUT/ModuleCache" \
  -parse-as-library "$OPT" -g -Xfrontend -disable-sandbox \
  -o "$APP/Contents/MacOS/Skald" > "$OUT/build.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/build.log" || true
[ "$rc" -eq 0 ] || { echo "swiftc failed ($rc)"; exit 1; }

test -x "$APP/Contents/MacOS/Skald"

# The real Info.plist with Xcode's build variables substituted.
sed -e 's/$(DEVELOPMENT_LANGUAGE)/en/' -e 's/$(EXECUTABLE_NAME)/Skald/' -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/dev.local.skald/' \
    -e 's/$(PRODUCT_NAME)/Skald/' -e 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/' -e 's/$(MARKETING_VERSION)/0.1.0/' \
    -e 's/$(CURRENT_PROJECT_VERSION)/1/' -e 's/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' Info.plist > "$APP/Contents/Info.plist"

# Xcode's synchronized group copies loose resources flat into Contents/Resources; mirror that.
find Skald/Resources -type f \( -name '*.json' -o -name '*.scm' \) -exec cp {} "$APP/Contents/Resources/" \;

codesign --force --sign - --entitlements Skald/Resources/Skald.entitlements "$APP" > "$OUT/codesign.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/codesign.log" || true
[ "$rc" -eq 0 ] || { echo "codesign failed ($rc)"; exit 1; }
echo "Built $APP"
