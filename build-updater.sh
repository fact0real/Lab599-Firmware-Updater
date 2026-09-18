#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

APP_NAME="Lab599-Firmware-Updater.app"
BIN_NAME="Lab599-Firmware-Updater"

mkdir -p build "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources"
test -s assets/AppIcon.icns || { echo "Missing app icon. Run sh build-icon.sh first." >&2; exit 1; }

if [ "${1:-}" = "--test" ]; then
    FW_PATH="../mtrx1.30.00.fw"
    [ -f "$FW_PATH" ] || FW_PATH="mtrx1.30.00.fw"
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        tests/TransferTests.m TX500Transfer.m -o build/TransferTests
    echo "Running simulated transfer tests with $FW_PATH..."
    ./build/TransferTests "$FW_PATH"
fi

echo "Compiling universal binary for $BIN_NAME (arm64 & x86_64)..."
clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
    -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -framework Cocoa -framework UniformTypeIdentifiers \
    Lab599FirmwareUpdater.m Lab599FirmwareCatalog.m TX500Transfer.m \
    -o "build/$BIN_NAME"

/bin/cp "build/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
/bin/cp Info.plist "$APP_NAME/Contents/Info.plist"
/bin/cp assets/AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
plutil -lint "$APP_NAME/Contents/Info.plist"
echo "Built $APP_NAME successfully with architectures:"
lipo -archs "$APP_NAME/Contents/MacOS/$BIN_NAME"
