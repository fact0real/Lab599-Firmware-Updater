# TX-500 updater protocol review

Reviewed on 2026-09-18. This report corrects the original macOS updater's
incorrect assumption that every payload byte requires an `OK` reply.

## Confirmed defect in version 1.0

The macOS v1.0 implementation called `SendAndConfirm` for the 16-byte header
and again for each payload byte. The official utilities only expect two `OK`
replies: one after the header and one after the entire payload.

With a bootloader that follows the recovered protocol, the old implementation
sends 17 bytes in total, then waits for a reply that is not due yet. This is
consistent with the radio reporting `The firmware is not sent` and the old
app reporting a five-second timeout with progress still at zero.

The actual saved v1.0 source was compiled into a regression harness using a
macOS pseudo-terminal. It reproduced this failure: exactly 17 bytes arrived,
then the old transfer function failed. The real radio was not accessed during
this investigation. The original failed attempt had no diagnostic log, so its
exact on-wire trace cannot be recovered from the screenshot alone.

## Binary evidence

All addresses below are virtual addresses in the supplied unmodified binaries.
These observations come from disassembly of control flow and system calls,
not just executable string matching.

| Operation | Linux 1.0.1 | Windows x64 1.0.2 |
| --- | --- | --- |
| Serial speed | `0x40d925`: `0xe100` = 57600 | `0x14000129a`: 57600 |
| Initial settle delay | `0x40d9b8`: 100 ms | `0x1400012e0`: 100 ms |
| Header | `0x40da3d`–`0x40da50`: write 16 bytes | `0x140001338`–`0x140001347`: write 16 bytes |
| Header reply | `0x40daf7`–`0x40db31`: read two bytes; compare `4F 4B` | `0x1400013e5`–`0x140001409`: same |
| Payload size | file size minus 16 at `0x40dbd0` | file size minus 16 at `0x140001454` |
| Payload writes | `0x40dbfc`–`0x40dc29`: read/write one byte | `0x1400014db`–`0x1400014fa`: read/write one byte |
| Payload pacing | `0x40dc77` calls `0x40dfb0` to check the TX queue | No per-byte RX/ACK call in the payload loop |
| Final reply | `0x40dc91`–`0x40dd5f`: wait/read/check `OK` | `0x140001477`–`0x140001595`: wait/read/check `OK` |

In particular, Linux helper `0x40dfb0` calls `ioctl(..., 0x5411, ...)`,
which is Linux `TIOCOUTQ`: the number of bytes remaining in the host's output
queue. Helper `0x40df70` instead uses `0x541b`, the input-byte count. The old
analysis confused output-queue draining with an acknowledgement from the radio.

The Windows equivalents are also distinct: `0x140002580` returns
`COMSTAT.cbOutQue`; `0x1400024e0` returns `COMSTAT.cbInQue`. Both use
`ClearCommError`, but read different structure fields. The payload loop uses
`WriteFile`; it does not wait for a radio response after each byte.

## Correct sequence in version 1.1

1. Validate that the file has a BL20 header and a non-empty payload. This is a
   format check, not proof of model compatibility or authenticity.
2. Open the explicitly selected serial port. Request exclusive access, configure
   and read back 57600 baud / 8 data bits / no parity / 1 stop bit / no flow
   control. Wait 100 ms and discard stale input before starting.
3. Send the original first 16 file bytes, wait for the host output queue to
   empty, then require exactly `OK` within five seconds.
4. Send every remaining file byte once, in order, unchanged. Match the Linux
   byte-write/output-queue pacing. Do not read or wait for per-byte replies.
5. After the last byte and output-queue drain, require the final `OK` within
   five seconds. Only this reply permits a success result.
6. Close the port. No reset, erase command, transformation, or automatic retry
   is added to the recovered transfer.

macOS constants are taken from its headers, not copied from Linux numeric
ioctl values. Write and queue deadlines use a monotonic clock. Interrupted and
temporarily unavailable writes are retried; partial writes are counted. The
app distinguishes header, payload and final-acknowledgement failures and logs
submitted byte counts. Submitted bytes mean bytes accepted by the host serial
driver, not flash memory independently read back from the radio.

The app disables file/port changes and normal close/quit while transmitting,
and requests prevention of idle system sleep. It never opens the serial port
merely to enumerate ports or select a firmware file.

## Firmware identity

The local `mtrx1.30.00.fw` is 246,384 bytes. It was compared byte-for-byte with
the file downloaded directly from the [official TX-500 Discovery firmware
link](https://downloads.lab599.com/TX500/mtrx1.30.00.fw), as listed on
[Lab599 Downloads](https://lab599.com/downloads). Both SHA-256 hashes are:

```
2162fed7d27987507c8b412f3d38478c0a670a906a0c747578d7c975ad5a04ea
```

The file was neither decrypted nor changed. Matching this download does not
establish that it is appropriate for a different radio model such as TX-500MP.

Source executable SHA-256 hashes:

```
Linux 1.0.1:
58e92d226c53f5bb1aeff2ecac19afd2842d8322d3a71baa453c5b83ade1faf3
Windows x64 1.0.2:
bc2fd4bb17dae13ca35b1840d184da4156e2bf040b5d116d7c378c73bc3fb895
```

## Verification and remaining limit

`tests/TransferTests.m` connects the actual transfer implementation to a
radio-side emulator through a real macOS pseudo-terminal. It tests the entire
local firmware with only two replies, exact byte preservation, fragmented
responses, header rejection/timeout, missing final confirmation, disconnection,
backpressure and malformed files. It also checks serial settings and that no
payload is sent before the header is accepted.

These tests exercise the macOS serial code and reproduce the recovered host
protocol. They do not simulate flash memory, bootloader internals, USB adapter
timing or hardware faults. A successful physical update and reboot remain
unverified until the user performs them on the radio.

Rebuild and run tests from this directory with `sh build-updater.sh --test`.
Build without rerunning tests with `sh build-updater.sh`. The application
contains both arm64 and x86_64 binaries targeting macOS 11 or newer. Its local
ad-hoc signature is not Apple notarization or Lab599 certification.
