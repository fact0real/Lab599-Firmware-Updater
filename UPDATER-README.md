# Lab599 Utility 2.0 — build and package guide

The app combines Firmware Update, Time Sync, CAT Test, Settings and Memory. See [README](README.md) and [the Persian guide](QUICKSTART-FA.md) for operation.

## Standalone build

Requires macOS and Apple Command Line Tools (or Xcode). No third-party application libraries are needed.

```sh
sh build-updater.sh
```

Output: `Lab599 Utility.app`, macOS 12+, universal Intel and Apple Silicon, ad-hoc signed. `assets/AppIcon.icns` is included; `build-icon.sh` can regenerate it. The historical script/project filenames are retained deliberately.

## Xcode

Open `Lab599-Updater.xcodeproj`, select **Lab599 Utility**, and build. Command-line equivalent:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Lab599-Updater.xcodeproj -scheme 'Lab599 Utility' \
  -configuration Release -derivedDataPath build/xcode-utility \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build
```

Version 2.0, build 6. Product/executable: `Lab599 Utility`. Existing bundle ID: `local.lab599.firmware-updater`.

## Test

```sh
sh build-updater.sh --test
```

This runs firmware, clock and new-module suites before building. Place the supplied `mtrx1.30.00.fw` in this folder or its parent for the complete firmware test. The suite transmits it only to an emulated radio through a pseudo-terminal.

To test the new modules independently:

```sh
mkdir -p build
clang -O2 -Wall -Wextra -Wno-unused-parameter -Werror -fobjc-arc \
  -mmacosx-version-min=12.0 -framework Foundation \
  tests/UtilityTests.m Lab599SerialPort.m TX500CATTest.m TX500Configuration.m \
  -o build/UtilityTests
./build/UtilityTests
```

PTYs exercise wire commands, complete banks, fragmented replies, invalid replies/files, timeouts, disconnection, cancellation and read-back mismatches. This host's PTY driver accepts `TIOCEXCL` without blocking a second open; the tests disclose this limitation. Physical-driver exclusivity and Memory DTR/RTS behavior require hardware testing.

## Source organization

- `Lab599Utility.m`: main window, shared operation lock, firmware/time flows and menus.
- `Lab599ToolsController.m`: CAT/Settings/Memory views and file operations.
- `Lab599SerialPort.m`: bounded serial I/O and cancellation for new modules.
- `TX500CATTest.m`: original identification test and error classes.
- `TX500Configuration.m`: Settings/Memory encoding, transfer and verification.
- `TX500Transfer.m`, `TX500TimeSync.m`, `Lab599FirmwareCatalog.m`: existing functions.

New features can add a controller panel and a separate protocol module while keeping the single-operation lock. No arbitrary CAT-command console is included in 2.0.

## Distribution

The release ZIP contains the app, build sources, Xcode project, assets, tests, guides, reverse-engineering evidence and validation logs. Original vendor executables/firmware, build intermediates and developer-specific Xcode state are excluded. The adjacent `.sha256` file checks the ZIP's integrity; it is not an Apple signature or notarization.
