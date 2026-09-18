# Lab599 Firmware Updater 1.2 for macOS

Developed by **EP2AES (factoreal)**  
GitHub: [https://github.com/fact0real/Lab599-Firmware-Updater](https://github.com/fact0real/Lab599-Firmware-Updater)  
Contact: `EP2AES@asis.sh`

A native macOS utility for updating Lab599 transceivers (**TX-500 Discovery** and **TX-500MP**) via CAT-USB serial connection.

## New in Version 1.2

1. **Xcode Project (`Lab599-Updater.xcodeproj`)**:
   - Full Xcode project ready to open and build in Xcode or via `xcodebuild`.
   - Supports native Universal Binary compilation (`arm64` and `x86_64`) for macOS Monterey (12.0) and newer.
2. **Branding & Identity**:
   - Renamed from `TX500FirmwareUpdater` to `Lab599-Firmware-Updater`.
   - Bundled with high-resolution macOS application icon (`AppIcon.icns`).
   - About Window featuring author details (**EP2AES**), callsign, and GitHub repository link.
3. **Multi-Radio Compatibility**:
   - Universal support for all Lab599 transceivers using the official BL20 bootloader protocol (TX-500 Discovery, TX-500MP, and HAM-Bands patches).
4. **Direct Online Firmware Check & Download**:
   - "Download from Lab599..." button queries `https://lab599.com/downloads` directly.
   - Categorizes releases by radio model (TX-500 Discovery, TX-500MP).
   - Displays changelogs, version numbers, file sizes, and download links.
   - Automatically downloads, verifies BL20 signatures and SHA-256 hashes, and selects the firmware for instant flashing.
   - Includes an offline fallback catalog if internet connectivity is unavailable.

## How to Build

### Option A: Using Xcode
Open `Lab599-Updater.xcodeproj` in Xcode, select the `Lab599-Firmware-Updater` scheme, and choose **Product > Build** (`Cmd+B`) or **Run** (`Cmd+R`).

Or via command line:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Lab599-Updater.xcodeproj -scheme Lab599-Firmware-Updater -configuration Release build
```

### Option B: Using the build script
```sh
sh build-updater.sh
```
This builds a Universal Binary `Lab599-Firmware-Updater.app` in the current folder.

## How to Update Your Transceiver

1. **Enter Bootloader Mode**:
   - Power off your Lab599 transceiver.
   - While holding the **third top function key**, turn on the transceiver by pressing **POWER**.
   - The screen will display: **"The loader is waiting..."**.
2. **Connect**:
   - Connect the CAT-USB cable to your Mac and the transceiver.
   - Ensure the radio has stable external DC power connected.
   - Close any other software using the CAT serial port (WSJT-X, flrig, MacLoggerDX, etc.).
3. **Run Lab599 Firmware Updater**:
   - Open `Lab599-Firmware-Updater.app`.
   - Select your radio CAT serial port from the dropdown (e.g., `/dev/cu.usbserial-...`).
   - Select your firmware:
     - Click **Download from Lab599...** to fetch the latest official firmware directly from the official website.
     - Or click **Choose .fw...** to manually select a local `.fw` file.
4. **Flash**:
   - Click **Update Firmware**, review the confirmation prompt, and click **Start Update**.
   - Keep your Mac awake and do NOT disconnect power or cables during transmission.
   - Wait for **"Firmware transfer complete"** and the final radio confirmation.
   - Turn off the transceiver, power it back on, and verify the displayed firmware version.
