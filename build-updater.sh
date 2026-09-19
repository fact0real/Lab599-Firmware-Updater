#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

APP_NAME="Lab599 Utility.app"
BIN_NAME="Lab599 Utility"

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
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        tests/TimeSyncTests.m TX500TimeSync.m -o build/TimeSyncTests
    ./build/TimeSyncTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        tests/UtilityTests.m Lab599SerialPort.m TX500CATTest.m TX500Configuration.m -o build/UtilityTests
    ./build/UtilityTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Cocoa \
        tests/DriverAndDocsTests.m Lab599DriverController.m Lab599DocsController.m -o build/DriverAndDocsTests
    ./build/DriverAndDocsTests
fi

echo "Compiling universal binary for $BIN_NAME (arm64 & x86_64)..."
clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
    -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -framework Cocoa -framework UniformTypeIdentifiers \
    Lab599Utility.m Lab599FirmwareCatalog.m TX500Transfer.m TX500TimeSync.m Lab599SerialPort.m TX500CATTest.m TX500Configuration.m Lab599ToolsController.m Lab599DriverController.m Lab599DocsController.m \
    -o "build/$BIN_NAME"

/bin/cp "build/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
/bin/cp Info.plist "$APP_NAME/Contents/Info.plist"
/bin/cp assets/AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"
/bin/cp assets/tx500_radio.png "$APP_NAME/Contents/Resources/tx500_radio.png"
/bin/mkdir -p "$APP_NAME/Contents/Resources/ftdi"
/bin/cp -R assets/ftdi/ "$APP_NAME/Contents/Resources/ftdi/"
xattr -cr "$APP_NAME" assets/ftdi 2>/dev/null || true

codesign --force --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
plutil -lint "$APP_NAME/Contents/Info.plist"
echo "Built $APP_NAME successfully with architectures:"
lipo -archs "$APP_NAME/Contents/MacOS/$BIN_NAME"
