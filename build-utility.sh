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
        tests/UtilityTests.m Sources/Lab599SerialPort.m Sources/TX500CATTest.m Sources/TX500Configuration.m Sources/TX500ProfilesAndBackup.m Sources/TX500SettingsModel.m -o build/UtilityTests
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
    clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
        -mmacosx-version-min=12.0 -framework Cocoa -framework UniformTypeIdentifiers \
        -IHeaders -ISources \
        tests/ScreenCaptureTests.m Sources/TX500ScreenModel.m Sources/TX500ScreenRenderer.m Sources/TX500ScreenCaptureController.m Sources/Lab599SerialPort.m -o build/ScreenCaptureTests
    ./build/ScreenCaptureTests
fi

# Auto-increment version and build number in Resources/Info.plist
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist 2>/dev/null || echo "13")
NEW_BUILD=$((CURRENT_BUILD + 1))

CURRENT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo "2.7")

MAJOR=$(echo "$CURRENT_VER" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VER" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VER" | cut -d. -f3)

if [ -n "$PATCH" ]; then
    NEW_PATCH=$((PATCH + 1))
    NEW_VER="${MAJOR}.${MINOR}.${NEW_PATCH}"
elif [ -n "$MINOR" ]; then
    NEW_MINOR=$((MINOR + 1))
    NEW_VER="${MAJOR}.${NEW_MINOR}"
else
    NEW_MAJOR=$((MAJOR + 1))
    NEW_VER="${NEW_MAJOR}.0"
fi

echo "==> Auto-incrementing version: $CURRENT_VER (Build $CURRENT_BUILD) -> $NEW_VER (Build $NEW_BUILD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VER" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" Resources/Info.plist

# Keep Xcode project settings in sync
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $NEW_VER;/g" Lab599-Utility.xcodeproj/project.pbxproj 2>/dev/null || true
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" Lab599-Utility.xcodeproj/project.pbxproj 2>/dev/null || true

echo "Compiling universal binary for $BIN_NAME $NEW_VER ($NEW_BUILD) (arm64 & x86_64)..."
clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
    -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -framework Cocoa -framework UniformTypeIdentifiers \
    -IHeaders -ISources \
    Sources/Lab599Utility.m Sources/Lab599FirmwareCatalog.m Sources/TX500Transfer.m Sources/TX500TimeSync.m Sources/Lab599SerialPort.m Sources/TX500CATTest.m Sources/TX500Configuration.m Sources/TX500ProfilesAndBackup.m Sources/TX500SettingsModel.m Sources/TX500ScreenModel.m Sources/TX500ScreenRenderer.m Sources/TX500ScreenCaptureController.m Sources/Lab599ToolsController.m Sources/Lab599DriverController.m Sources/Lab599DocsController.m Sources/TXGaugeView.m Sources/TX500TelemetryEngine.m Sources/Lab599TelemetryController.m Sources/Lab599FeedbackController.m \
    -o "build/$BIN_NAME"

/bin/cp "build/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
/bin/cp Resources/Info.plist "$APP_NAME/Contents/Info.plist"
/bin/cp Resources/AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"
/bin/cp Resources/tx500_radio.png "$APP_NAME/Contents/Resources/tx500_radio.png"
/bin/cp Resources/tx500_mp.png "$APP_NAME/Contents/Resources/tx500_mp.png"
/bin/cp Resources/tx500_pro.png "$APP_NAME/Contents/Resources/tx500_pro.png"
/bin/cp Resources/tx500_pro_altai.png "$APP_NAME/Contents/Resources/tx500_pro_altai.png"
/bin/cp Resources/lab599_logo.png "$APP_NAME/Contents/Resources/lab599_logo.png"
/bin/mkdir -p "$APP_NAME/Contents/Resources/ftdi"
/bin/cp -R Resources/ftdi/ "$APP_NAME/Contents/Resources/ftdi/"
xattr -cr "$APP_NAME" Resources/ftdi 2>/dev/null || true

codesign --force --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"
plutil -lint "$APP_NAME/Contents/Info.plist"
echo "Built $APP_NAME successfully with architectures:"
lipo -archs "$APP_NAME/Contents/MacOS/$BIN_NAME"

echo "==> Deploying $APP_NAME ($NEW_VER Build $NEW_BUILD) to /Applications/..."
/bin/rm -rf "/Applications/$APP_NAME"
/bin/cp -R "$APP_NAME" "/Applications/"
echo "==> Installed $APP_NAME successfully into /Applications/"
