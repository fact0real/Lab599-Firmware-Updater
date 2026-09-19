# Lab599 TimeSync reverse-engineering review

Analysis date: 2026-09-18. Target release: Lab599 Updater & Time Sync 1.3.

## Scope and confidence

The complete application-specific control flow of both supplied TimeSync executables was statically traced: startup, port enumeration, UI events, clock sampling, byte construction, serial setup, both writes, response acceptance, errors and cleanup. The serial and date runtime functions called by that flow were also traced to their OS imports. Full disassemblies, import maps, string addresses, extracted application code and a reproducible extraction script are in `reverse-engineering/timesync/`.

This is a functional reconstruction, not recovery of the author's original source, comments, symbol names or build project. The binaries are native executables, with runtime patterns consistent with PureBasic (UTF-16 strings, PB runtime identifiers and serial/gadget wrappers); they are not .NET programs. Generic GUI, allocator and C runtime internals are preserved in the disassembly rather than rewritten as application source. Neither original executable was run. No physical radio was accessed; hardware compatibility and actual on-air timing remain unverified.

## Input identity

| File in `../Lab599-TRX-TimeSync-EN` | Format | SHA-256 |
| --- | --- | --- |
| `TRX-TimeSync(x64)` | Stripped ELF64, x86-64, GTK UI | `caf87b58dbd7052b8284d992a0525827d1e7d041c1797db417b8fae7be53e9c0` |
| `TRX-TimeSync(x64).exe` | Native PE32+, x86-64, Windows GUI | `aa6686c21747ec06297be6d8e9dd07597516d231221a85fc93f48a059f4c4fb0` |

The supplied `Readme-EN.txt` explicitly tells the operator to turn on with POWER, connect CAT-USB, select a port and click Synchronize. It does not ask for bootloader mode. It describes TX-500 series support without specifying a minimum firmware version.

## Complete application behavior

1. Initialize the GUI, strings, date and serial runtime; create two zeroed 17-byte working buffers.
2. Create a small `TimeSync` window (300 × 60), a port selector and a `Synchronize` button.
3. Enumerate integer suffixes **0 through 99 inclusive**. Linux probes `/dev/ttyUSB0`…`/dev/ttyUSB99`; Windows probes `COM0`…`COM99`. Each candidate is opened at 9600/8N1 with the no-handshake selector. Add openable ports to the list and immediately close them. This tests whether a port opens; it does **not** identify a Lab599 radio.
4. Wait for window events. The close event performs runtime cleanup and exits. Clicking Synchronize disables the port selector and button.
5. Open the selected port. On failure, show `ERROR!` / `Can't open the serial port: <port>` and re-enable controls.
6. Read the computer's **local** date/time once. Format only its hour, minute and second using `%hh:%ii:%ss`.
7. Build `TM` + the eight time characters + `;`. Convert each UTF-16 character to its one-byte ASCII value in the transmit buffer. Write **exactly 11 bytes**. There is no NUL, CR or LF on the wire.
8. Sleep **100 milliseconds**.
9. Convert `TM;` into the byte buffer and write **exactly 3 bytes**.
10. Sleep another **100 milliseconds**, then inspect the number of pending input bytes **once**.
11. Unless that count is **exactly 11**, show `Can't read TRX!: <port>`, close the port and re-enable controls.
12. Read 11 bytes, form a string from **only the first two**, and compare it to `TM`. If equal, show `Info` / `Synchronization completed!`; otherwise show the read error. Close the port and re-enable controls in either case.

There is no firmware upload, BL20 header, `OK` acknowledgement, date setting, timezone setting, automatic retry, background periodic synchronization, NTP transaction or radio model/version query in this application flow. System-clock network synchronization, if enabled by the operating system, is outside this utility.

A structured reconstruction of this entire application flow is in `reverse-engineering/timesync/original-logic.pseudocode`.

## Wire protocol

| Item | Recovered value |
| --- | --- |
| Radio state | Normally powered on, per supplied README |
| Serial speed | 9600 baud (`0x2580`) |
| Framing | 8 data bits, no parity, 1 stop bit |
| Handshake argument | 0 / no handshake |
| Set command | ASCII `TMhh:mm:ss;` (11 bytes) |
| Read command | ASCII `TM;` (3 bytes) |
| Expected read length | 11 bytes |
| Original reply acceptance | Exactly 11 pending bytes; first two read bytes are ASCII `TM` |
| Inferred time reply grammar | `TMhh:mm:ss;`, based on symmetric command and 11-byte reply size |
| Time basis | Computer local time; no UTC conversion in the original application |
| Resolution | Whole seconds; no fractional seconds in the command |
| Delays | 100 ms after set; 100 ms after query before checking input |

**Evidence boundary:** The original utility proves reply length and prefix, but does not parse the other nine bytes. The strict `TMhh:mm:ss;` reply grammar used by the new implementation is inferred from that shape and the setter, not observed on physical hardware. If a radio returns another 11-byte `TM` response shape, 1.3 deliberately reports an unconfirmed sync and logs the response rather than claiming success. The firmware engine remains independent.

Example for computer local time 16:04:56:

```text
Host -> radio: 54 4D 31 36 3A 30 34 3A 35 36 3B   TM16:04:56;
               [100 ms]
Host -> radio: 54 4D 3B                           TM;
Radio -> host: 54 4D 31 36 3A 30 34 3A 35 36 3B   TM16:04:56;  [inferred shape]
```

## Cross-platform evidence map

Addresses are virtual addresses in the supplied binaries, not file offsets. PE addresses use preferred image base `0x140000000`; subtract it for RVAs. `linux-application.txt` and `windows-application.txt` contain every instruction in the application ranges.

| Behavior | Linux | Windows |
| --- | --- | --- |
| Application/UI/event loop | `0x406d30–0x407416` | `0x140001050–0x14000180e` |
| Probe suffix 0 through 99 | `0x406e8c–0x406fa6` | `0x1400011e7–0x14000131b` |
| Selected-port serial arguments | `0x40706f–0x40708d` | `0x140001451–0x140001486` |
| Local time sampled | `0x4070b1`, callee `0x40c920` | `0x1400014a6`, callee `0x140005424` |
| Format `%hh:%ii:%ss` | `0x4070c4–0x4070cb` | `0x1400014b9–0x1400014c0` |
| Concatenate `TM`, time, `;` | `0x4070e9–0x407122` | `0x1400014de–0x140001517` |
| Copy UTF-16 character to byte | `0x4071b8–0x40721a` | `0x1400015b0–0x140001613` |
| Set-command serial write | `0x407234` | `0x14000162d` |
| First 100 ms sleep | `0x407239–0x40723e` | `0x140001632–0x140001637` |
| Literal `TM;` loaded | `0x407243` | `0x14000163c` |
| Query serial write | `0x4072dc` | `0x1400016d5` |
| Second 100 ms sleep | `0x4072e1–0x4072e6` | `0x1400016da–0x1400016df` |
| Exact input count 11 | `0x4072ed–0x4072f6` | `0x1400016e6–0x1400016ef` |
| Read 11 bytes | `0x407366–0x407374` | `0x14000175c–0x14000176b` |
| Copy two bytes and compare to `TM` | `0x407391–0x4073f8` | `0x140001788–0x1400017ef` |
| Success dialog, then common close | `0x4073fe–0x407416` | `0x1400017f5–0x14000180e` |

Key literals:

| Literal | Linux VA | Windows VA |
| --- | --- | --- |
| `%hh:%ii:%ss` | `0x41b7c0` | `0x14003c060` |
| `TM;` | `0x41b898` | `0x14003c118` |
| `TM` | `0x41b8aa` | `0x14003c12a` |
| `;` | `0x41b8b0` | `0x14003c130` |

## Runtime details relevant to correctness

- Linux `0x4075d0` is the serial-open wrapper. `0x2580` maps to termios `B9600` (`0x0d`); the 8-bit selection contributes `CS8`. Stop-bit float is `1.0`. The zero parity/handshake arguments avoid parity and hardware-flow branches. It opens nonblocking, requests exclusive access through ioctl `0x540c` (`TIOCEXCL`), flushes input, then calls `tcsetattr`. The resulting Linux control flags include `CLOCAL|CREAD|CS8|B9600`. The input flags contain `IGNPAR`; output and local flags are zero.
- Linux pending input at `0x407580` calls ioctl `0x541b` (`FIONREAD`), not the output-queue query used by the firmware updater. The direct read wrapper is `0x407a10`; write wrapper `0x407b10` calls `write` at `0x407b43`; close wrapper is `0x407a60`. The application does not check the read/write byte-count returns.
- Windows serial-open wrapper `0x14000194c` calls `CreateFileW` with read/write access and share mode zero, `SetupComm` with both requested queues set to 16, `GetCommState`, `SetCommState` and `SetCommTimeouts`. It assigns baud=9600, ByteSize=8, Parity=0 and one stop bit. The zero-handshake branch clears CTS/RTS hardware-handshake bits. **Some DCB flags are inherited from `GetCommState`**, so the new implementation explicitly clearing all flow control is stronger than the original Windows wrapper. Windows write timeout fields are multiplier=100 and constant=10 milliseconds; read timeout fields are zero. The application calls `ClearCommError` to inspect `cbInQue` before reading 11 bytes. Read wrapper `0x140001b68`; write wrapper `0x140001bc8`; close wrapper `0x1400018d0`.
- Linux clock wrapper `0x40c920` calls `time`, then `localtime_r` at `0x40c93e`, and reconstructs the local calendar tuple. The runtime uses `timegm` to encode that tuple and `gmtime_r` when formatting it. This representation does **not** make the application use UTC: the input tuple was explicitly local time. Windows corroborates this directly with `GetLocalTime` at `0x14000542d`.
- Linux string equality at `0x414460` turns a zero string-comparison result into boolean true. Thus the success branch really does accept only the first two characters `TM`; it does not compare the returned clock to the set value.

## Weaknesses of the original utility

- Opens and configures many candidate ports during discovery, without radio identification.
- Fixed 100 ms response snapshot can reject delayed or fragmented replies.
- Requires exactly 11 pending bytes, so extra CAT notifications also cause failure.
- Ignores serial write/read return counts.
- Accepts any 11-byte reply starting with `TM`, including invalid clock fields or unchanged time.
- Offers no UTC selection, timestamp preview or diagnostic log.

## New macOS implementation

`TX500TimeSync.h/.m` implements a separate engine; `TX500Transfer.h/.m` was not changed. Firmware remains 57600/8N1 with the original two-ACK BL20 sequence.

Time Sync preserves the 9600/8N1 set/query transaction and 100 ms inter-command pause. Deliberate improvements:

- Enumerate macOS serial-device paths without opening them; open only the selected port.
- Explicitly configure and read back 9600/8N1 with hardware and software flow control disabled. Request exclusive access. Close on every exit after successful open.
- Format an ASCII 24-hour time independently of locale and calendar. Mac local time is the default; UTC is an explicit alternative. Sample the system clock after opening/configuring the port.
- Handle partial writes and bound writes/output drain to 2 seconds per command.
- Discard pre-query input so an already-arrived set-command echo cannot satisfy verification.
- Accumulate fragmented input until the semicolon within a 2-second response deadline. Bound total input to 1024 bytes and frame length to 128 bytes. Skip unrelated complete CAT frames and leading CR/LF. Reject malformed `TM` replies and `?;`.
- Require a syntactically valid time and a read-back within 2 seconds of the sent clock plus elapsed monotonic time, including midnight wrap. This tolerance accommodates whole-second resolution and scheduling; it is not a claim of NTP-grade or subsecond accuracy.
- A sent command followed by failed verification is shown as **unconfirmed**, because the clock might already have changed. No automatic re-send or reset command.
- Run serial work off the UI thread. Both operations share a busy guard; mode selection and port controls are locked during a transaction. Quit/window-close guards and sleep prevention cover both operations.

There is no transaction identifier in the recovered protocol. Clearing stale input reduces false confirmation, but a delayed physical command echo cannot be cryptographically distinguished from a radio reply. This is ordinary CAT read-back verification, not device authentication.

## Validation

`sh build-updater.sh --test` passed on macOS with warnings treated as errors:

- All **15 existing firmware checks**, including byte-for-byte transfer of the supplied 246,384-byte `mtrx1.30.00.fw`, fragmented acknowledgements, header/final rejections, timeouts, cable loss and bounded output backpressure.
- **12 TimeSync pseudo-terminal scenarios**: exact response, delayed fragmented response, unrelated CAT frames/CRLF, wrong clock, invalid time fields, query echo, command rejection, silence, truncated response, stale set echo, disconnect and oversized unterminated frame. Each checks exact outbound bytes, actual termios settings, inter-command delay and absence of extra writes.
- Deterministic fixtures: UTC, +03:30 and +12:45 offsets, negative offset, midnight wrap, malformed frames, tolerance boundaries, missing port and invalid timing values.
- The standalone build and Xcode Release build both succeeded. The release binary contains both `arm64` and `x86_64`. Its ad-hoc signature and Info.plist validate. Minimum deployment target is macOS 12.0.
- UI inspected in the running app: both operation views, local Tehran clock, UTC selection, loading the supplied firmware with hash validation, and disabled action buttons when no serial port is available.

Build/test output is preserved in `validation/validation-1.3.log`; the final TimeSync rebuild and rerun are in `validation/timesync-final-1.3.log`. Xcode build output is in `validation/xcode-validation-1.3.log`.

No USB serial port or physical radio was opened during validation. Hardware read-back shape, minimum compatible radio firmware and actual timing on a real cable remain to be checked on a TX-500-series radio.

## Reproduce the evidence

```sh
python3 reverse-engineering/timesync/reconstruct.py
sh build-updater.sh --test
```

The extractor uses only Python's standard library and `objdump`. It computes file hashes, reads ELF relocation and PE import tables, labels OS calls, maps strings to file and virtual addresses, and preserves the full and application-only disassemblies. It never executes the inputs.
