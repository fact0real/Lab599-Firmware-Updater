# Lab599 Utility 2.0 validation record

Date: 2026-09-19. Version 2.0, build 6. macOS 12+; universal Intel/Apple Silicon.

## Completed

- Full firmware suite: all 15 checks passed, including the complete supplied 246384-byte firmware and byte-for-byte payload comparison. Existing transfer engine was retained.
- Time Sync suite: formatting/timezone/midnight fixtures and all simulated serial cases passed. Existing clock engine was retained.
- New-module suite: exact independent command/file fixtures; all five CAT IDs and rejection/recovery/cancellation; complete Settings and Memory reads, writes and read-back; malformed, short, extra, fragmented, absent and disconnected responses; cancellation; mismatch detection; invalid arguments/files; bounded serial reads and port release. Passed.
- Standalone universal build with warnings treated as errors: passed.
- Xcode Release build for arm64 and x86_64: passed. Xcode emitted environment/simulator-service diagnostics in the restricted environment; the macOS target completed successfully.
- Bundle metadata, both architectures and strict ad-hoc signature verification: passed.
- Native UI checked interactively with no radio connected: five operation selectors, Settings file loading and SHA-256 display, CAT disabled without a port, Time Sync preview, 100-row Memory bank creation/editing, saving a 600-byte file, unsaved replacement/exit dialogs. The saved memory sample was inspected independently for exact little-endian frequency, USB/off bytes and 99 empty records.
- A stale frequency editor after replacing a bank was found during UI testing, corrected, rebuilt and retested. Table values are read-only; editing occurs through the row editor.

## Logs

- [Full protocol regression and build](utility-2.0-tests.log)
- [Final new-module tests, including transport checks](new-modules-2.0-tests.log)
- [Final standalone build](build-utility-2.0.log)
- [Final Xcode build](xcode-utility-2.0.log)

Final executable SHA-256: `bab5bd5430c3d87760321c0dfee983f3fa43333f81ea68c538bd05b1b6bc4b7a`.

## Limits

No physical radio or physical serial device was accessed. Manufacturer binaries were analyzed statically. Original Settings ACK contents and ignored reply framing are not established; emulated reply prefixes are fixtures, not hardware captures. See [configuration analysis](../CONFIGURATION-REVIEW.md).

This host's PTY driver accepts TIOCEXCL but does not prevent a second non-root open. A separate minimal PTY probe reproduced this behavior. The test reports it explicitly; physical-driver exclusivity is unverified. Production code requests exclusive access and the UI permits only one operation at a time.

Memory DTR/RTS assertions are required in the application, but disabled in the PTY emulator. Real USB timing, modem signals, model/firmware compatibility and persistence after a radio restart remain unverified. No Apple notarization or Developer ID signature is claimed.

Synthetic UI backup files remain in the development workspace and are excluded from the release ZIP. They are test data, not backups intended for restoration to a radio.
