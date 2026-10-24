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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Skald</string>
	<key>CFBundleExecutable</key><string>Skald</string>
	<key>CFBundleIdentifier</key><string>dev.local.skald</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Skald</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Xcode's synchronized group copies loose resources flat into Contents/Resources; mirror that.
find Skald/Resources -type f \( -name '*.json' -o -name '*.scm' \) -exec cp {} "$APP/Contents/Resources/" \;

codesign --force --sign - --entitlements Skald/Resources/Skald.entitlements "$APP" > "$OUT/codesign.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/codesign.log" || true
[ "$rc" -eq 0 ] || { echo "codesign failed ($rc)"; exit 1; }
echo "Built $APP"
