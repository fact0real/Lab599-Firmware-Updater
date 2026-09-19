#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

APP_NAME="Lab599 Utility.app"
BIN_NAME="Lab599 Utility"

mkdir -p build "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources"
test -s Resources/AppIcon.icns || test -s assets/AppIcon.icns || { echo "Missing app icon. Run sh build-icon.sh first." >&2; exit 1; }

if [ "${1:-}" = "--test" ]; then
    FW_PATH="../mtrx1.30.00.fw"
    [ -f "$FW_PATH" ] || FW_PATH="mtrx1.30.00.fw"
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        -IHeaders -ISources \
        tests/TransferTests.m Sources/TX500Transfer.m -o build/TransferTests
    echo "Running simulated transfer tests with $FW_PATH..."
    ./build/TransferTests "$FW_PATH"
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        -IHeaders -ISources \
        tests/TimeSyncTests.m Sources/TX500TimeSync.m -o build/TimeSyncTests
    ./build/TimeSyncTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Foundation \
        -IHeaders -ISources \
        tests/UtilityTests.m Sources/Lab599SerialPort.m Sources/TX500CATTest.m Sources/TX500Configuration.m Sources/TX500ProfilesAndBackup.m -o build/UtilityTests
    ./build/UtilityTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Cocoa \
        -IHeaders -ISources \
        tests/DriverAndDocsTests.m Sources/Lab599DriverController.m Sources/Lab599DocsController.m Sources/Lab599FirmwareCatalog.m Sources/TX500Transfer.m -o build/DriverAndDocsTests
    ./build/DriverAndDocsTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Cocoa \
        -IHeaders -ISources \
        tests/TelemetryTests.m Sources/TX500TelemetryEngine.m Sources/Lab599SerialPort.m -o build/TelemetryTests
    ./build/TelemetryTests
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Cocoa \
        -IHeaders -ISources \
        tests/FeedbackTests.m Sources/Lab599FeedbackController.m -o build/FeedbackTests
    ./build/FeedbackTests
fi

echo "Compiling universal binary for $BIN_NAME (arm64 & x86_64)..."
clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
    -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -framework Cocoa -framework UniformTypeIdentifiers \
    -IHeaders -ISources \
    Sources/Lab599Utility.m Sources/Lab599FirmwareCatalog.m Sources/TX500Transfer.m Sources/TX500TimeSync.m Sources/Lab599SerialPort.m Sources/TX500CATTest.m Sources/TX500Configuration.m Sources/TX500ProfilesAndBackup.m Sources/Lab599ToolsController.m Sources/Lab599DriverController.m Sources/Lab599DocsController.m Sources/TXGaugeView.m Sources/TX500TelemetryEngine.m Sources/Lab599TelemetryController.m Sources/Lab599FeedbackController.m \
    -o "build/$BIN_NAME"

/bin/cp "build/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
/bin/cp Resources/Info.plist "$APP_NAME/Contents/Info.plist"
/bin/cp Resources/AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"
/bin/cp Resources/tx500_radio.png "$APP_NAME/Contents/Resources/tx500_radio.png"
/bin/cp Resources/tx500_mp.png "$APP_NAME/Contents/Resources/tx500_mp.png"
/bin/cp Resources/tx500_pro.png "$APP_NAME/Contents/Resources/tx500_pro.png"
/bin/cp Resources/tx500_pro_altai.png "$APP_NAME/Contents/Resources/tx500_pro_altai.png"
/bin/mkdir -p "$APP_NAME/Contents/Resources/ftdi"
/bin/cp -R Resources/ftdi/ "$APP_NAME/Contents/Resources/ftdi/"
xattr -cr "$APP_NAME" Resources/ftdi 2>/dev/null || true

codesign --force --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
plutil -lint "$APP_NAME/Contents/Info.plist"
echo "Built $APP_NAME successfully with architectures:"
lipo -archs "$APP_NAME/Contents/MacOS/$BIN_NAME"
