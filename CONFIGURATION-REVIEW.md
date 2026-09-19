# Settings and Memory reconstruction for Lab599 Utility 2.0

Reviewed 2026-09-19. This report reconstructs the supplied utilities' application logic, file formats, serial transactions and exposed controls. It distinguishes binary evidence from added checks and from unknown response semantics. It does not claim to recover the manufacturer's original source or the meaning of all radio settings.

## Inputs

| Utility | Supplied files | Evidence |
| --- | --- | --- |
| Settings 1.0 | Windows x64 and x86 PE executables | [Hashes](reverse-engineering/settings/SHA256SUMS.txt), [x64](reverse-engineering/settings/x64-disassembly.txt), [x86](reverse-engineering/settings/x86-disassembly.txt) |
| Memory 1.03 | Windows x64 and x86 PE executables, Linux x86-64 ELF | [Hashes](reverse-engineering/memory/SHA256SUMS.txt), [x64](reverse-engineering/memory/x64-disassembly.txt), [x86](reverse-engineering/memory/x86-disassembly.txt), [Linux](reverse-engineering/memory/linux-disassembly.txt) |

No Linux Settings executable is present in the supplied folder. The Linux Memory file is named `Lab599-TRXMem-v1-03-x64` but embeds a **TRXMem 1.02** window label at `0x426dce`; the Windows label is 1.03. The core serial/file behavior described below agrees across the inspected Memory builds.

Analysis used disassembly of control flow and imported serial/file APIs, not just string matching. `reverse-engineering/extract.py` extracts and annotates PE32, PE32+ and ELF evidence using the helper in `reverse-engineering/timesync/reconstruct.py`. Original vendor executables were not executed.

## Settings file and protocol

A `.set` file is exactly **1024 raw bytes**, with no header, model identifier, schema, checksum or field names exposed by the tool. Byte index 0 maps to address 1000; index 1023 maps to 2023. The application reads/saves the entire block. It offers no individual-setting editor.

Serial configuration: **9600, 8N1, no handshake**, 16-byte input/output queues in the original. After opening, it waits 100 ms and drains stale input.

| Operation | Recovered transaction |
| --- | --- |
| Read byte i | ASCII `XL` + decimal(1000+i) + `;` — always 7 bytes |
| Read response | Exactly 6 bytes; parse decimal digits at zero-based offsets 2, 3, 4 and store the low byte |
| Write byte i | ASCII `XS` + decimal(1000+i) + one literal space + unsigned decimal value + `;` |
| Write response | Wait for exactly 4 pending bytes, read and discard all 4 |

Examples: `XL1000;`, `XL2023;`, `XS1000 0;`, `XS2023 255;`. **The value is decimal without zero padding.** A space separates address and value. There is no hexadecimal conversion, colon, binary byte payload or per-block write command.

Each original reply wait polls about once per millisecond, with a 500-iteration limit. Its response check compares the pending byte count to the exact expected length. For reads it concatenates bytes 2–4 and invokes the runtime decimal conversion; it does not establish a required two-byte prefix or final byte. For writes it never checks acknowledgement content.

Consequently, the actual acknowledgement vocabulary and ignored framing bytes cannot be established from these executables alone. Tests use synthetic `XLddd;` / `XS0;` responses as fixtures; these are **not captured radio replies**. The replacement validates exactly six bytes and three numeric digits in range 0–255 for reads, and the original four-byte length for write responses. It does not invent an ACK code. It reads back all 1024 bytes after writing before reporting success.

### Settings evidence map

| Fact | Windows x64 VA |
| --- | --- |
| Load exact 1024 bytes | size check `0x1400017b4`, byte loop `0x1400017f0`–`0x14000182b` |
| Save raw bytes | loop `0x140001d26`–`0x140001d62`, WriteByte wrapper `0x140010f40` |
| Write serial setup / delay | `0x140001fea`–`0x14000204b` / `0x14000206d` |
| Loop 0–1023 | `0x1400020b8`, comparison with `0x3ff` |
| XS / address+1000 / value | `0x1400020dc` / `0x14000211a` / `0x14000218d` |
| Decimal unsigned-byte conversion | wrapper `0x140010070`, `%u` format at `0x1400176e8` |
| Literal space / semicolon | UTF-16 literals `0x14001903c` / `0x140019040` |
| Write and wait for four bytes | `0x1400022bb`, polling `0x1400022cb`–`0x14000231e`, read `0x140002498`–`0x1400024ac` |
| Read setup / settle / loop | `0x140002a0f` / `0x140002a92` / `0x140002add` |
| XL / address / semicolon | `0x140002b01` / `0x140002b3f` / `0x140002b5a` |
| Send seven, wait/read six | `0x140002c4e`–`0x140002c62`, `0x140002c72`–`0x140002cd3`, `0x140002e3f`–`0x140002e53` |
| Parse offsets 2–4 / store | `0x140002e6e`–`0x140002f14`, decimal conversion at `0x140002f1b`, byte store `0x140002f33` |

The x86 build corroborates the size check at `0x4014fd`, full byte loops near `0x401548`/`0x401830`, 9600 setup at `0x4019cd`/`0x402004`, and XS/XL construction near `0x401a6a`/`0x4020a1`.

## Memory file format

A `.mem` file is exactly **600 bytes**: 100 records numbered 00–99, each six bytes:

| Record offset | Size | Meaning |
| --- | --- | --- |
| 0 | 4 | Unsigned frequency in Hz, little-endian |
| 4 | 1 | ASCII mode code |
| 5 | 1 | ASCII preamplifier/attenuator code |

Modes: `1` LSB, `2` USB, `3` CW, `4` FM, `5` AM, `7` CWR. The original DIG choice also encodes `2`, so it reads back as USB. PreAtt: `0` off, `1` PRE, `2` ATT. These are ASCII bytes, not numeric byte values 0–7. Frequency zero denotes an empty channel. Active frequency editing is restricted to 100000–56000000 Hz inclusive in the original GUI.

For example, 7100000 Hz, LSB, ATT begins `60 56 6c 00 31 32`. The new decoder preserves unused bytes in empty file records for file round trips; sending an empty channel uses the original canonical empty encoding (`frequency=0`, mode/pre=`0`). Unknown active modes/pre values and out-of-range active frequencies are rejected instead of silently mislabelled.

## Memory serial protocol

Serial configuration: **9600, 8N1, no flow control**, original queues 64/64. Unlike Settings/TestCAT, Memory explicitly asserts **DTR and RTS**. It then waits 100 ms and drains input. These are manually set modem-control lines, not RTS/CTS hardware flow control.

Read channel i: `MR00` + two-digit channel number + `;`, always 7 ASCII bytes. Example: `MR0099;`. The original waits for exactly **50 bytes**, polling in 1 ms steps up to about 1000 iterations. It reads the 11-digit frequency at zero-based offsets **6–16**, the mode at **17**, and PreAtt at **18**. It does not interpret or validate the other reply bytes.

Write channel i is exactly **50 ASCII bytes**:

```text
MW00 + channel(2) + frequency(11) + mode(1) + PreAtt(1)
     + 22 literal ASCII zeros + 8 literal spaces + semicolon
```

Channel and frequency are zero padded. All 100 channels are sent, including empty slots. The original **does not read a write acknowledgement**: it waits until the host output queue is empty before proceeding. Output-queue draining does not prove that the radio applied the command.

The replacement preserves this command, drains each write, adds 100 ms spacing, and then reads all 100 channels to compare frequency, mode and PreAtt. Empty-channel comparison ignores unused mode/pre bytes. It does not fabricate an ACK or claim to verify fields the utility never exposes.

The 31-byte fixed suffix is important: the original tool overwrites additional command fields with zeros/spaces. Neither the `.mem` file nor this implementation preserves unknown extensions, channel names or every byte of a 50-byte radio response. The write confirmation and guide disclose this behavior.

### Memory evidence map

| Fact | Windows x64 VA | Linux x86-64 VA |
| --- | --- | --- |
| Set DTR / RTS | `0x14000137c` / `0x14000138e` → wrapper `0x1400048bc` | `0x40b868` / `0x40b87f` → `0x40f4a0` |
| Settle | after signals | `0x40b884` |
| Build MW command | `0x14000154d`–`0x14000170d` | `0x40b8e8`–`0x40bad2` |
| Frequency padding constant 100000000000 | near `0x1400013c9` | `0x40b9bd` |
| Mode mapping / PreAtt mapping | `0x140001000`–`0x14000119f` / `0x1400011a0`–`0x140001266` | corresponding MW string assembly |
| Drain output, not input | `0x140001454` → `0x140004aa0` | `0x40bbcf` → `0x40eec0` → ioctl `0x5411` (TIOCOUTQ) |
| Build MR command | `0x140001fbb`–`0x1400020bf` | `0x40c9b0`–`0x40cae4` |
| Expect 50 / timeout count | `0x1400020e9` | `0x40cb1e` / `0x40cb2b` |
| Read 50 bytes | `0x140001e89`–`0x140001e98` | `0x40cc23`–`0x40cc36` |
| Parse frequency | `0x140001ea8`–`0x140001f28` | `0x40cc51`–`0x40ccd0` |
| Mode / PreAtt reply offsets | `0x14000221d` / `0x14000224f` | `0x40cd90` / `0x40cdd2` |
| File size 600 | `0x140002e10` | `0x40aaf9` |
| Read 4-byte frequency, then two bytes | `0x140002f1a`, `0x140002f24`, `0x140002f2e` | same six-byte record layout |
| Save 4-byte frequency, then two bytes | `0x14000310a`, `0x140003159`, `0x1400031a8` | `0x40b1ba`, `0x40b21d`, `0x40b280` |
| Frequency GUI bounds | corroborated in Windows | `0x40be8b` (>99999), `0x40bedd` (<56000001) |

The x86 Windows file-size check is at `0x4033af`. Windows file wrappers confirm the four-byte and one-byte I/O widths (`0x1400129d0` / `0x140012a40` for writes), rather than relying on platform integer-size assumptions.

## Replacement safeguards and deliberate differences

`TX500Configuration.m` implements formats and transfers; `Lab599SerialPort.m` provides bounded I/O; `Lab599ToolsController.m` provides the views. Compared with the originals:

- Collect fragmented replies within a one-second deadline; cap reply buffers and reject oversized reads when observed together.
- Validate numeric payloads, file sizes, channel ranges and active codes before writing.
- Snapshot outgoing banks; never replace a local bank with an incomplete read.
- Request exclusive port access, verify serial settings, and share the GUI operation lock.
- Stop cooperatively, close the port and report how many writes may have affected the radio. Never automatically retry an ambiguous write.
- Require a concrete write confirmation, and verify every settings byte or exposed memory field after writing.
- Save files atomically and prompt before replacing or closing unsaved banks.

There is no protocol transaction ID or checksum. Ignored prefix/terminator bytes cannot authenticate a read; delayed unsolicited responses could still be ambiguous. Matching read-back improves detection but is not proof of physical persistence after a power cycle. Hardware captures are needed to strengthen framing without inventing rules.

## Validation and remaining work

Independent command/file fixtures and PTY emulators check both bank sizes, exact ordered addresses, all writes followed by full read-back, malformed/short/extra/fragmented replies, timeouts, cable-loss simulation, cancellation and mismatches. Original bytes are not sent to a physical radio. Memory tests disable DTR/RTS because PTYs cannot emulate those signals; production code requires the signal operation to succeed.

This host's PTY driver accepts TIOCEXCL but permits another non-root open, verified with an independent small PTY probe. Tests report that limitation instead of claiming physical exclusivity. Users must still close other CAT programs, including programs that opened the port earlier.

See [the validation record](validation/RELEASE-2.0.md). A first hardware check should capture read-only transactions and save existing banks before any write. Minimum firmware versions, actual ignored response bytes, USB-driver signals, persistence and cross-model compatibility remain unverified.
