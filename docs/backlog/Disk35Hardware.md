# Backlog: the 3.5 controller at the hardware level

Status: **not started; planned 2026-11-12, not to be built yet.** The compatible card is built (see
[Apple2.md](../Apple2.md#debugging), "The 3.5 disk controller"). This plan is for a second mode that runs Apple's own
EPROM on an emulated card, for full fidelity: real timing, the diagnostics, the start-up handshake and the IIgs paths.

## Why

The compatible card (`Apple2Disk35Card`, with the SDK's `Disk35.rom.asm`) answers every SmartPort and ProDOS call in
C#, following what the decoded EPROM does. It differs from Apple's card where the card's own processor matters:
- every call finishes at once;
- FORMAT clears the disk rather than writing tracks;
- tags are not kept;
- CONTROL $0C-$13 (code in the card's RAM) and command $0B (the format list) are not there;
- there are no diagnostics, and no UniDisk 3.5 on the SmartPort bus.

Running Apple's code closes every one of those gaps at once. The cost is a SWIM and Sony drive mechanisms.

## What there is

- **The dump:** `341-0438-A.bin`, 32 KB, CRC32 `c73ff25b`, SHA-1 `440c3f84176c7b9f542da0b6ddf4fb13ec326c46`, SHA-256
  `084587835c1d2c92…2dc172`. It is in `superdrive-roms` under `RETROCORE_CACHE` (or `RETROCORE_SUPERDRIVE_ROMS`),
  from the Apple II Documentation Project mirror (`Interface Cards/Disk Drive Controllers/Apple II 3.5 Disk Controller
  Card/ROM Images`). It is never committed.
- **The source:** [`Roms/Disk35/Disk35Controller.asm`](../../src/Retrocore.Machines.Apple2/Roms/Disk35/Disk35Controller.asm)
  and its parts assemble byte-identically to the dump (`Apple2Disk35Tests.SourceMatchesTheChip`). Every routine is
  named and documented, so a hardware mode can be debugged against the source.
- **References:** MAME's `src/devices/bus/a2bus/a2superdrive.cpp` (the card), `src/devices/machine/swim1.cpp` (the
  SWIM) and `src/devices/machine/applefdintf.cpp` (the drives' interface); the SWIM chip's specification; Apple's
  Macintosh `SonyEqu.a` for register names.
- **Already in Retrocore:**
  - the W65C02 core (`Retrocore.Cpu.M6502`, `ProcessorVariant.Wdc65C02`);
  - `Disk35Disk`'s block images and their track, side and sector layout (`Locate`);
  - the Disk II's bit-level drive model, a pattern for a rotating disk.

## The hardware

**The card's 65C02** runs at the 15.6672 MHz crystal / 7.66, about 2.046 MHz, unsynchronized with the host. Its map:

| Card address | What |
| --- | --- |
| $0000-$7FFF | 32 KB of static RAM |
| $0A00-$0A0F | The SWIM, over RAM: IWM switches at reset, ISM registers (write $0-$7, read $8-$F) once switched |
| $0A40, $0A41 | Head select: side 0, side 1 (any access) |
| $0A80, $0A81 | The diagnostic LED on, off |
| $8000-$FFFF | The EPROM |

The vectors are NMI and RESET $D11D, and IRQ $F931. $FFF8-$FFF9 is the checksum word.

**The host's view**, from the same RAM:

| Host address | Card RAM |
| --- | --- |
| $Cn00-$CnFF | $7B00-$7BFF, read only (writes are ignored) |
| $C800-$CBFF | One 1 KB bank of $0000-$3FFF: bank b is b × $400, latched by any access to $C080+$n0+b |
| $CC00-$CFFF | $7C00-$7FFF |

The card takes the $C800 space ($CFFF releases it, as for any card). MAME resets only the SWIM on the bus's reset; the
65C02 keeps running.

**What the host code needs.**
- **Bank 0 is the mailbox:** the card's page zero, seen at $C800.
- **Bank 2 holds the host's scratch:** the busy flag at $CA00 and page zero $40-$51 saved at $CA02. That RAM sits
  under the card's I/O page, so only the host sees it.
- **Bank 0's $CA00-$CBFF is host code:** the card's $0200-$03FF, copied from $8200.

The handshake (from `Disk35Host.asm` and `Disk35Card.asm`):
1. The host waits for $C800 bit 7 (the card is idle). It writes $C801 = $FF, then its $43-$4B to $C802-$C80A, then
   the command (SmartPort command & $1F) to $C800.
2. The card's main loop sees the command and runs it.
3. If there is data, the card puts a buffer code in $01: card address / $200, so host bank = code >> 1 and
   half = code & 1. It then waits for the host to OR in $F0.
4. A result is $01 = 0 with the error in $56. The card then sets $00 = $FF.

Data moves 512 bytes through the window: the host copies with `(dp),Y`, or on a IIgs with `[dp],Y` in native mode at
full speed. On a IIgs WRITEBLOCK, the card starts writing as each page arrives, paced through $C804 ($C0, $C1, $D0).
The other card commands are $0C (boot read), $3D (diagnostics) and $7E/$7F (the host is not / is a IIgs). The card
writes the host type to $7C09.

**The slot page's waits.** The host spins on branches to themselves, and the card releases them by rewriting their
offsets:

| Branch | Offset byte | Released by |
| --- | --- | --- |
| `BVS` at $Cn0B (boot) | $7B0C | $16 |
| `BEQ` at $Cn17 (diagnostics) | $7B18 | 0 |
| `BVC` at $Cn21 (calls) | $7B22 | 0 |

While the self-test runs, only $Cn00-$Cn22 are valid. $Cn23-$CnFF still hold old RAM, random at power-on, including
$CnFB-$CnFF. A failed self-test writes `JMP $FF59` at $Cn00, $Cn0D and $Cn23, zeroes $7B05 (breaking the
signature), and blinks the LED: one long flash and one short.

**The drives.** The SWIM's phase lines, `SEL35` and head select carry the Sony drive's commands and status senses:
- step direction, step, motor on/off, eject;
- disk in place, write protect, tachometer, ready, two sides, high density (FDHD), and disk switched.

The firmware tells an Apple 3.5 Drive (kind 1) from an FDHD (kind 3) by sense 5. It finds the drives at cold start in
FINDDRIVES ($D362), and UniDisk 3.5s on the SmartPort bus in BUSINIT ($F8BA).

**The media the firmware reads.**
- **GCR:** 400K (kind 2) and 800K (kinds 4 and 6, by interleave). Five speed zones: 12, 11, 10, 9 and 8 sectors per
  track for tracks 0-15, 16-31, 32-47, 48-63 and 64-79. Each sector is 524 bytes: 12 tag bytes and 512 of data.
- **MFM:** 720K (kind 8) and 1440K (kinds $0A and $0C), 9 or 18 sectors per track. The SWIM's clock halves for GCR
  (HDSEL, the ISM mode register's bit 5).

The card caches a track (18 slots at $1000-$33FF) and reads ahead after a miss.

**Timing the firmware waits on:**
- DELAY1MS ($F73C) is about 2,030 cycles;
- the motor waits 500 ms the first time after a disk is found, 100 ms after that;
- the ready wait gives up after about 1.2 s, and an eject waits up to about 2 s;
- POLLDRIVES runs about every 1.4 s when idle;
- the self-test takes about 0.25 s, almost all of it the EPROM checksum.

## Shape in the code base

- **`Apple2Disk35Card` stays the compatible card.** A new card (working name `Apple2SuperDriveCard`) holds the 65C02,
  its RAM, the EPROM and the SWIM.
- **One per machine, or several:** decide when building.
- **The bus needs a per-card $C800 space:** today only the IIe's internal ROM claims $C800-$CFFF. A card that owns
  $C800 needs Apple's rule: selected by an access to its $Cn page, released by $CFFF.
- **The card's CPU steps from `Apple2Bus.Tick`,** about 2.046 card cycles per host cycle, kept as a fractional
  accumulator so the two clocks drift as they do on the real card.
- **The SWIM** (IWM and ISM) is a device of its own, and so are the Sony mechanisms. Their tracks are made from a
  `Disk35Disk`'s blocks, encoded GCR or MFM with the address and data fields the firmware expects. Writes decode back
  into blocks, so the same images serve both cards.
- **Launch and the Retro Devices view:** a `disk35Firmware` option (or `disk35: { slot, mode }`) picks the mode, and
  `romDirectory` / `RETROCORE_SUPERDRIVE_ROMS` gives the dump. Without the dump, the hardware mode is refused with a
  message naming the file.

## Phases

1. **The card's computer.** The 65C02, RAM, EPROM, I/O page, host window and bank latch, and the $C800 claim. Stub
   the SWIM so the self-test's checks pass. Done when the self-test passes and the slot page shows the SmartPort
   signature with its waits released. With no drives, a ProDOS STATUS of unit 0 answers through Apple's own code.
2. **The SWIM, IWM and ISM.** Mode switching, the parameter RAM, the FIFO, the phase register and the error
   register, checked against the self-test's SWIM test and MAME's model.
3. **The drives' senses and commands.** Drive detection, motor, step, eject and the senses, until FINDDRIVES finds two
   FDHDs and a STATUS reports them as Apple's DIB does.
4. **Reading.** GCR tracks with the speed zones and the tachometer, then MFM, from `Disk35Disk`. Done when ProDOS 8
   boots A2DeskTop's 800K image through Apple's firmware.
5. **Writing and formatting.** Writes back into the blocks; FORMAT's track writes and verifies.
6. **Tests and the debugger:**
   - run `Apple2Disk35Tests`' call scenarios against both modes, and keep a table of what differs;
   - a debugger thread or memory view for the card's CPU (its memory areas are the card's RAM and EPROM);
   - the diagnostics end to end (Control-D at boot).

## Open questions

- READ ($08) on Apple's card copies its data from $0E00 though the sector was read into $0C00 (`READWRITE`, $DE50).
  Is that a bug in the firmware, or a misreading? Running the code will tell.
- CONTROL $0C (poke) takes its value from $0C04, which looks like an off-by-one in the firmware.
- READWRITE's media check indexes MEDIAKIND by a leftover Y, effectively drive 1's.
- Should the hardware mode support UniDisk 3.5s on the bus (`BUSCALL`, $F812)? That is a second processor per drive.
- A IIgs is not a Retrocore machine yet, so its paths ($C036 speed, `[dp],Y` transfers) would be tested only once one
  is.

## Not part of this

Writing changed disks back to their image files is a gap both cards share with the Disk II. It belongs with the
media work in [Media.md](Media.md).
