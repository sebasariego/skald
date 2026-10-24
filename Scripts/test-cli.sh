#!/bin/zsh
# Compiles the app as a testable library plus QuillTests as an .xctest bundle,
# then runs it with the xctest runner. Mirrors the Xcode "QuillTests" target.
# Usage: Scripts/test-cli.sh [XCTest filter, e.g. QuillTests.LineEndingTests]
#        OPT=-O Scripts/test-cli.sh      # optimized build, for the performance tests
set -euo pipefail
cd "$(dirname "$0")/.."

OPT="${OPT:--Onone}"
OUT=DerivedData/cli-tests${OPT}
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
PLATFORM_DEV="$(dirname "$(dirname "$SDK")")"
PLATFORM_FRAMEWORKS="$PLATFORM_DEV/Library/Frameworks"
BUNDLE="$OUT/QuillTests.xctest"
mkdir -p "$OUT/ModuleCache" "$BUNDLE/Contents/MacOS"

APP_SOURCES=(${(f)"$(find Quill -name '*.swift' | sort)"})
TEST_SOURCES=(${(f)"$(find QuillTests -name '*.swift' | sort)"})
OBJECTS=(${(f)"$(Scripts/compile-c-sources.sh "DerivedData/cli/obj")"})
C_FLAGS=()
if [ -d Quill/Vendor/TreeSitter/include ]; then
  C_FLAGS=(-I Quill/Vendor/TreeSitter/include -I Quill/Vendor/Grammars/include)
fi

COMMON=(-sdk "$SDK" -target arm64-apple-macosx14.0 -swift-version 5 -strict-concurrency=targeted
        -module-cache-path "$OUT/ModuleCache" -Xfrontend -disable-sandbox -g "$OPT")
# Mirror Xcode: Debug builds define DEBUG, Release builds do not.
if [ "$OPT" = "-Onone" ]; then COMMON+=(-DDEBUG); fi

swiftc "${APP_SOURCES[@]}" "${OBJECTS[@]}" "${COMMON[@]}" "${C_FLAGS[@]}" \
  -module-name Quill -parse-as-library -enable-testing \
  -emit-library -emit-module -emit-module-path "$OUT/Quill.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/libQuill.dylib \
  -o "$OUT/libQuill.dylib" > "$OUT/build-lib.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/build-lib.log" || true
[ "$rc" -eq 0 ] || { echo "swiftc (library) failed ($rc)"; exit 1; }
test -f "$OUT/libQuill.dylib"

swiftc "${TEST_SOURCES[@]}" "${COMMON[@]}" "${C_FLAGS[@]}" \
  -module-name QuillTests -parse-as-library \
  -I "$OUT" -L "$OUT" -lQuill -F "$PLATFORM_FRAMEWORKS" \
  -I "$PLATFORM_DEV/usr/lib" -L "$PLATFORM_DEV/usr/lib" \
  -Xlinker -rpath -Xlinker "$PLATFORM_DEV/usr/lib" \
  -emit-library \
  -Xlinker -rpath -Xlinker "$PLATFORM_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$(cd "$OUT" && pwd)" \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  -o "$BUNDLE/Contents/MacOS/QuillTests" > "$OUT/build-tests.log" 2>&1 && rc=0 || rc=$?
grep -v xcrun_db "$OUT/build-tests.log" || true
[ "$rc" -eq 0 ] || { echo "swiftc (tests) failed ($rc)"; exit 1; }
test -f "$BUNDLE/Contents/MacOS/QuillTests"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>QuillTests</string>
	<key>CFBundleIdentifier</key><string>dev.local.quill.tests</string>
	<key>CFBundleName</key><string>QuillTests</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST

if [ $# -gt 0 ]; then
  xcrun xctest -XCTest "$1" "$BUNDLE" 2>&1 | grep -v xcrun_db
else
  xcrun xctest "$BUNDLE" 2>&1 | grep -v xcrun_db
fi
