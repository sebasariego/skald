#!/bin/zsh
# Builds Quill.app with swiftc alone (no xcodebuild), for environments where the
# Xcode build service cannot run. Output: DerivedData/cli/Quill.app
# Usage: Scripts/build-cli.sh [-O]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=DerivedData/cli
APP="$OUT/Quill.app"
OPT="${1:--Onone}"
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
mkdir -p "$OUT/ModuleCache" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(${(f)"$(find Quill -name '*.swift' | sort)"})
OBJECTS=(${(f)"$(Scripts/compile-c-sources.sh "$OUT/obj")"})
C_FLAGS=()
if [ -d Quill/Vendor/TreeSitter/include ]; then
  C_FLAGS=(-I Quill/Vendor/TreeSitter/include -I Quill/Vendor/Grammars/include)
fi

swiftc "${SOURCES[@]}" "${OBJECTS[@]}" "${C_FLAGS[@]}" \
  -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -swift-version 5 -strict-concurrency=targeted \
  -module-name Quill -module-cache-path "$OUT/ModuleCache" \
  -parse-as-library "$OPT" -g -Xfrontend -disable-sandbox \
  -o "$APP/Contents/MacOS/Quill" > "$OUT/build.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/build.log" || true
[ "$rc" -eq 0 ] || { echo "swiftc failed ($rc)"; exit 1; }

test -x "$APP/Contents/MacOS/Quill"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Quill</string>
	<key>CFBundleExecutable</key><string>Quill</string>
	<key>CFBundleIdentifier</key><string>dev.local.quill</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Quill</string>
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
find Quill/Resources -type f \( -name '*.json' -o -name '*.scm' \) -exec cp {} "$APP/Contents/Resources/" \;

codesign --force --sign - --entitlements Quill/Resources/Quill.entitlements "$APP" > "$OUT/codesign.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/codesign.log" || true
[ "$rc" -eq 0 ] || { echo "codesign failed ($rc)"; exit 1; }
echo "Built $APP"
