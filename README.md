# Lab599 Utility 2.0 for macOS

A native macOS application combining firmware updates, clock synchronization, CAT connection testing, settings backups and a 100-channel memory editor for the Lab599 TX-500 series. Developed by **EP2AES (factoreal)**.

**macOS 12+ · Apple Silicon and Intel · English interface · Persian guide included**

[راهنمای فارسی](QUICKSTART-FA.md) · [Build instructions](UPDATER-README.md)

## Functions

| View | What it does | Radio mode |
| --- | --- | --- |
| Firmware Update | Select a local `.fw` file or use the existing Lab599 download catalog; transfer the BL20 header and payload with two acknowledgements | Bootloader, “The loader is waiting...” |
| Time Sync | Set Mac local time or UTC and check the returned radio clock | Normal operation, CAT 9600 |
| CAT Test | One identification check or continuous testing, with replies, response time and pass/fail counts | Normal operation, CAT 9600 |
| Settings | Read/save/open/restore the complete 1024-byte `.set` backup; read back and compare after writing | Normal operation, CAT 9600 |
| Memory | Read, edit, save, open and write 100 channels using the original 600-byte `.mem` format; read back and compare after writing | Normal operation, CAT 9600 |

Only one radio operation runs at a time. CAT, Settings and Memory have a cooperative Stop button; partial writes are reported explicitly. File editing works without a connected radio. Unsaved banks are protected by replacement/exit prompts.

Settings is a complete-block backup/restore tool, matching the supplied utility; it does not claim to identify individual setting fields. Memory exposes frequency, mode and preamplifier/attenuator. DIG uses the same stored code as USB. Writing memory replaces all 100 slots, including empty ones, and uses the original utility’s fixed values for the remaining command fields.

## Use

Open **Lab599 Utility.app**, connect CAT-USB and choose the serial port. Close other programs using that port. For Time Sync, CAT Test, Settings and Memory, turn the radio on normally and use 9600 baud. For firmware, follow the bootloader instructions displayed in the app and select firmware intended for your model.

Read and save the current settings/memory before restoring another bank. File size and format checks cannot identify which radio model or firmware created an untagged original backup. A failed or stopped write can leave part of the radio changed; success is reported only after the implemented read-back checks complete.

## Build and tests

With Apple Command Line Tools or Xcode installed:

```sh
sh build-updater.sh
```

The output is `Lab599 Utility.app`, a universal `arm64`/`x86_64` bundle. The local build is ad-hoc signed and is not Apple-notarized.

```sh
sh build-updater.sh --test
```

Tests use pseudo-terminals only. The firmware suite uses `mtrx1.30.00.fw` in this directory or its parent; that manufacturer file is not redistributed in the release ZIP. The new modules also have independently runnable tests; see [the build guide](UPDATER-README.md).

The Xcode project retains the filename `Lab599-Updater.xcodeproj`; its target and scheme are **Lab599 Utility**. The bundle identifier is retained for continuity with the earlier app.

## Reconstruction and validation

- [Firmware protocol review](PROTOCOL-REVIEW.md)
- [TimeSync review](TIMESYNC-REVIEW.md)
- [TestCAT 1.1 review](CAT-REVIEW.md)
- [Settings and Memory review](CONFIGURATION-REVIEW.md)
- [Validation record](validation/RELEASE-2.0.md)

Reports distinguish observed binary behavior, deliberate improvements, and unresolved details. Disassembly, binary hashes, extraction scripts and tests are included. This is a behavioral reconstruction, not recovery of the manufacturer's original source code. The supplied Settings folder contains Windows x86/x64 binaries only; Memory includes Windows and Linux binaries. The Memory Linux filename says 1.03 but its internal window label says 1.02.

**Real-radio validation remains outstanding.** Simulated responses prove the implementation against the reconstructed transactions, not compatibility with every model/firmware/USB driver. Settings acknowledgement contents and some reply framing remain unspecified by the original programs. Memory modem-control signals cannot be verified with pseudo-terminals.

## Project

Independent software, not an official Lab599 product. Existing repository: [fact0real/Lab599-Firmware-Updater](https://github.com/fact0real/Lab599-Firmware-Updater). Author: EP2AES; contact: `EP2AES@asis.sh`.

See the existing [LICENSE](LICENSE), which contains GNU GPL version 3. Manufacturer executables and firmware are not included in the new release package.
