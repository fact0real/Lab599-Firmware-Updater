# TestCAT 1.1 reconstruction for Lab599 Utility 2.0

Reviewed 2026-09-19. Scope: the complete application-level identification loop, serial setup, stop behavior and error classification of both supplied Windows executables. Proprietary runtime/framework code was followed where necessary to identify API calls; this is not recovery of the original source project.

## Inputs and method

`Lab599-TRX-TestCAT-1.1-EN` contains Windows x64 and x86 executables. Static PE disassembly, imports, UTF-16 literals and control-flow comparison were used; vendor executables were not run. [Hashes](reverse-engineering/testcat/SHA256SUMS.txt), [x64 application evidence](reverse-engineering/testcat/x64-application.txt), [x86 application evidence](reverse-engineering/testcat/x86-application.txt) and full disassembly are included.

| File | SHA-256 |
| --- | --- |
| TestCAT1.1(x64).exe | `55ff40c0287408c508bcc5f91873ef380459afce4ecc41ecd7768dc45ce711f1` |
| TestCAT1.1(x86).exe | `652e8c9fca3b8dcdcfc0a11c36a215e9b4cca790d2230535f3fef25330a58862` |

## Recovered behavior

The original enumerates COM0 through COM99 by trying to open ports. START opens the selected port at 9600 baud, 8 data bits, no parity, one stop bit and no flow control; its queue sizes are 16 input / 1024 output. The background worker sends ASCII `ID;`, sleeps 100 ms, inspects the current input byte count, and classifies the reply. It repeats until STOP forcibly terminates the worker and closes the port.

| Code | Original condition |
| --- | --- |
| 000 / OK | Exactly six bytes matching `ID019;`, `ID500;`, `ID501;`, `ID502;` or `ID505;` |
| 001 | Serial handle absent from the runtime's registered-port table |
| 002 | No pending input after the sleep |
| 003 | A nonzero pending byte count other than six |
| 004 | Six bytes that fail all five accepted comparisons |

`ID503;` is **not** accepted by this binary. The identifier list is reproduced without inventing model names for those codes. Original error 001 checks a registered handle, not the physical cable's health. The original non-six-byte branch reads the entire pending count into a fixed buffer; the replacement bounds reads.

## Evidence map

Addresses are virtual addresses in the original images; offsets from UTF-16 strings are not wire offsets.

| Fact | Windows x64 evidence |
| --- | --- |
| Open/configure | `0x14004362f`–`0x1400436b7` |
| Worker | `0x140043860`–`0x140043d2e` |
| Build and write ID; | `0x1400438cd`–`0x140043930`; wrapper `0x140001928` → WriteFile at `0x140001966` |
| Sleep 100 ms | `0x140043935`–`0x14004393f` |
| Input byte count | `0x14004394e`; wrapper `0x1400015e0` → ClearCommError at `0x14000160d` |
| Require six bytes / read | `0x140043956` / `0x14004397b` |
| ID019; branch | `0x140043987`–`0x140043a82` |
| ID50[0,5,1,2]; branches | `0x140043a88`–`0x140043c47` |
| OK / unknown ID | `0x140043c4c` / `0x140043c67` |
| No reply / wrong length / invalid handle | `0x140043c99` / `0x140043cdc` / `0x140043cf7` |
| Stop thread | `0x1400437f0` → wrapper `0x140001564` → TerminateThread at `0x140001580` |

The x86 worker starts near `0x436540`, writes at `0x4365d6`, delays at `0x4365db`, and reconstructs the same accepted ID branches from `0x43664c` through `0x4367b6`.

## Replacement behavior

`TX500CATTest.m` preserves the command and five accepted replies. It adds Test Once, continuous counts, response timing, bounded input, logged failures and cooperative cancellation. It gives fragmented or delayed replies up to one second while retaining a minimum 100 ms response window. This is deliberately more tolerant than the original one-shot pending-count check. Stale input is discarded before each query; non-timeout I/O errors end the run with an explicit connection error.

The GUI's shared busy guard prevents overlap with firmware, clock, settings or memory operations. Port enumeration does not open every detected device. The test sends only `ID;`; it does not set frequency, key the transmitter, or implement a general CAT conformance suite.

## Validation and limits

`tests/UtilityTests.m` independently checks all accepted IDs, rejects ID503, distinguishes empty/short/extra/unrecognized replies, verifies error recovery and cancellation, and exercises fragmented replies over a PTY configured for 9600/8N1/no flow control. See [validation](validation/RELEASE-2.0.md). No physical radio was accessed. PTY timing cannot establish USB-adapter timing or hardware compatibility.
