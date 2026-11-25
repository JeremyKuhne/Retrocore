# The MITS Altair 8800

Retrocore's Altair 8800 is [`AltairMachine`](../src/Retrocore.Machines.Altair/AltairMachine.cs): a state-exact 8080,
RAM, the 88-2SIO serial board or the original 88-SIO with a terminal, the 88-ACR cassette interface, the 88-DCDD
floppy controller with 8-inch drives, MITS's boot PROMs, and the front panel's switches. It runs Altair BASIC, Disk
BASIC, Altair DOS and CP/M 2.2 from images you supply. This guide covers what it emulates and how to debug on it.
[The backlog](backlog/Altair8800.md) has what comes next: CP/M's sources, and a front panel view.

## The machine

| Part | Addresses or ports | Emulated |
| --- | --- | --- |
| RAM | `$0000` up | 1 to 64 KB (`RamKilobytes`, 64 by default). Addresses past it read `$FF`, as the S-100 bus's pull-ups leave them, and lose writes. |
| 88-2SIO | Ports `$10`-`$11` and `$12`-`$13` | Two MC6850 ACIAs. The terminal is on the first unless it is on the 88-SIO; the second has nothing connected. |
| 88-SIO | Ports `$00`-`$01` | When the terminal is on it (`Console`). |
| 88-ACR | Ports `$06`-`$07` | An 88-SIO at 300 baud with a cassette recorder (`CassetteInterface`, on by default). |
| 88-DCDD | Ports `$08`-`$0A` | The floppy controller and its Pertec FD-400 8-inch drives (`DiskDrives`, 0 to 16; none by default). |
| DBL PROM | `$FF00`-`$FFFF` | MITS's disk boot loader 4.1, from its SDK source, when fitted (`AltairRoms`). |
| MBL PROM | `$FE00`-`$FEFF` | MITS's multi-boot loader, which loads tapes, from its SDK source, when fitted. |
| Sense switches | Port `$FF` | The front panel's high 8 switches (`Switches`). |

Every other port reads `$FF` and ignores writes.

**CPU.** The 8080 runs at 2 MHz, a 500 ns state, with each machine cycle's bus access on the state the chip makes it
([`Retrocore.Cpu.I8080`](../src/Retrocore.Cpu.I8080)). The Altair has no ROM of its own: at power-on and RESET the
8080 starts at `$0000`, in whatever RAM holds. A PROM, when fitted, answers its addresses in place of RAM, and writes
there are lost.

**88-2SIO.** Each port is a Motorola MC6850 ACIA ([`Acia6850`](../src/Retrocore.Core/Machines/Chips/Acia6850.cs)):
control and status at the even port, data at the odd one. Power-on and RESET leave it held in master reset, with
its transmit register shown full, until a control write selects a clock divide, so software resets it (`$03`) and
sets its format (`$15` is divide by 16, 8 data bits, 1 stop bit) first, as Altair BASIC and CP/M's BIOSes do. A
written character moves into the shift register at once if it is idle, so TDRE comes back straight away, and
leaves after a character time at the baud rate (`BaudRate`, 9600 by default: 2,083 cycles). The lines always have
carrier and are clear to send, and characters never have framing or parity errors.

**88-SIO.** MITS's first serial board ([`AltairSio`](../src/Retrocore.Machines.Altair/AltairSio.cs)), a UART with
status and control at the even port and data at the odd one. Its ready bits are low when ready: status bit 0 is low
while a received character waits, and bit 7 is low while the transmitter can take one. Bit 4 is set when a
character arrived before the last was read and was lost; the other bits read 0. It needs no setting up, since its
format and baud rate are jumpers. Control bit 0 enables its input interrupt and bit 1 its output interrupt, and
RESET clears both.

**88-ACR.** The cassette interface is an 88-SIO at 300 baud with a modem
([`AltairCassette`](../src/Retrocore.Machines.Altair/AltairCassette.cs)); a tape is the bytes the modem carried, a
`.tap` file. The 88-ACR has no motor control, so a tape moves from the moment it goes in: it delivers a byte each
character time (66,666 cycles), whether or not the program reads it, and a byte not read before the next arrives is
lost, as on a real recorder. A tape that records takes each byte the program sends.

**88-DCDD.** MITS's floppy controller
([`AltairDiskController`](../src/Retrocore.Machines.Altair/AltairDiskController.cs)) drives up to 16 Pertec FD-400
8-inch drives ([`AltairDiskDrive`](../src/Retrocore.Machines.Altair/AltairDiskDrive.cs)) of hard-sectored disks: 77
tracks of 32 sectors of 137 bytes. Its timing is the one Mike Douglas's FDC+ board reproduces, in CPU cycles
([`AltairDiskTiming`](../src/Retrocore.Machines.Altair/AltairDiskTiming.cs)):

- **The disk turns all the time**, a sector every 5.2 ms. Sector True is asserted for 32 µs after each sector's pulse.
- **Reading.** A sector's bytes come one every 32 µs from 452 µs into it, each setting NRDA and holding the data port
  until the next replaces it, which MITS's loops that read two bytes a pass rely on. Reading the port clears NRDA,
  and the port keeps the last byte until another comes; an image holds nothing of the gap after a sector's 137.
  The controller assembles bytes from the sector's first one bit, so a sector that does not start with bit 7 set
  reads shifted, its bytes that many 4 µs bit times later, and a blank sector gives no bytes at all.
- **Writing.** A write enable in a sector's first 212 µs writes it, one after the sector's end (5.008 ms) writes the
  next, and one in between is forgotten. ENWD asks for each byte from 388 µs, a byte time apart, and the controller
  takes the data port's value at each, new or not; the first 137 become the sector. Head movement stays held off
  until the drive's trim erase ends, 452 µs into the next sector. A write-protected disk keeps its sectors, as the
  drive would refuse to write, and a disk taken out during a write keeps the bytes written so far.
- **The head.** A step holds off further steps for 10.5 ms, when track 0 follows it, allows one for 1 ms, then holds
  them off while the head settles, until 43.5 ms. A head loaded, or stepped, is settled 50 ms later, and the sector
  position shows only from the first sector to begin with it settled.
- **Selecting** a drive with no disk leaves the controller disabled, its status and position reading `$FF`.
  Selecting a drive unloads its head and disables the controller's interrupts. Status bit 5 shows the 8080's INTE,
  as the controller reads it from the bus.

The controller's sector interrupts are not modeled, as none of the software here uses them, nor is the FD-400's
wait for the index hole after a drive is selected: the sector position shows once the head has settled.

**Disk images** ([`AltairDisk`](../src/Retrocore.Media/Altair/AltairDisk.cs)) are SIMH's `.dsk` files: the
sectors in order, track by track, 337,568 bytes. Many archive images have 96 more bytes, which are kept, so an image
saves back byte for byte.

**Boot PROMs.** [`Dbl.asm`](../src/Retrocore.Machines.Altair/Roms/Dbl.asm) is MITS's disk boot loader 4.1: it
copies itself to `$2C00`, waits for drive 0, steps out to track 0, reads the disk from there into memory
from `$0000`, as many bytes as its sectors say, and runs it.
[`Mbl.asm`](../src/Retrocore.Machines.Altair/Roms/Mbl.asm) is the multi-boot loader, which loads a MITS tape from
the device that sense switches A11-A8 name, skipping its leader and checksum loader. Both are documented sources
that assemble byte-identically to the PROMs.

**Interrupts.** The serial boards' interrupt requests drive the 8080's INT line: on the 88-2SIO, a full receiver
with control bit 7 set, or an empty transmitter with bits 5-6 at `01`; on the 88-SIO and 88-ACR, as their control
bits enable. The Altair has no vectored interrupt board here, so the acknowledge
reads the floating bus's `$FF`, `RST 7`, and the handler is at `$0038`.

**Terminal.** An 80-by-24 glass teletype with the Lear Siegler ADM-3A's controls, the most common terminal on
Altairs: ^H left, ^J down, ^K up, ^L right, ^M to the first column, ^Z clear and home, ^^ home, and ESC `=` row
column, each plus `$20`, to place the cursor. Printable characters wrap after the 80th column, and the line after
the last scrolls the screen. Bit 7 is ignored, and other controls, ^I among them, do nothing. The characters are
8 by 8 in 8-by-10 cells, white on black. Typed keys go out one character time apart, and only into an empty
receive register, so typing ahead or pasting never overruns the serial port. With caps lock (`UpperCase`), typed
letters go out as capitals.

**Front panel.** [`AltairFrontPanel`](../src/Retrocore.Machines.Altair/AltairFrontPanel.cs) models the 16
switches and EXAMINE, EXAMINE NEXT, DEPOSIT and DEPOSIT NEXT, as an operator keyed programs in. The debugger's
RUN, stop, step and RESET stand in for the panel's own switches; the panel has no view in the extension yet.

## Altair BASIC

Altair BASIC is MITS's and Microsoft's, so it is not part of Retrocore. With a memory image, such as the
`4kbas32.bin`, `4kbas40.bin` and `8kbas.bin` in SIMH's `altsw.zip`, launch it as a program at `$0000` with caps lock
on, since BASIC takes only capitals:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "8K BASIC",
    "machine": "altair",
    "program": "${workspaceFolder}/8kbas.bin",
    "loadAddress": 0,
    "entryAddress": 0,
    "upperCase": true
}
```

BASIC asks for the memory size and the terminal width, where Return takes its defaults, all of RAM among them, and
which functions to keep. Answering 8K BASIC's first `MEMORY SIZE?` with `A` shows who wrote it, and it asks again.

BASIC picks its terminal by the sense switches:

| Version | 88-2SIO (`"console": "2sio"`) | 88-SIO (`"console": "sio"`) |
| --- | --- | --- |
| 4K BASIC 3.2 | A11 up: `"switches": 2048` | All down: `"switches": 0` |
| 4K BASIC 4.0, 8K BASIC 4.0 | All down: `"switches": 0` | A13 up: `"switches": 8192` |

The 4.0 BASICs read A15-A12 as the terminal's device number, where 0 is the 88-2SIO and 2 the 88-SIO.

### From MITS's tapes

MITS sold BASIC on cassette and paper tape. Loading one takes three steps:

1. The operator keys a 20-byte bootstrap in at `$0000` with the front panel.
2. The bootstrap reads the tape's checksum loader backwards into memory below the load address, skipping the
   leader (whose bytes are the load address's low byte), and jumps to it.
3. The checksum loader reads the rest of the tape in checksummed records, and starts BASIC.

As a source to launch with the tape in the 88-ACR:

```asm
.cpu I8080
        .org 0
Boot:   lxi h,$0FAE         ; the load address: see the table
Loop:   lxi sp,Stack        ; so each RET goes back to Loop
        in $06              ; the 88-ACR's status
        rrc                 ; bit 0 is low when a byte waits
        rc
        in $07
        cmp l               ; a leader byte?
        rz
        dcr l
        mov m,a             ; store it, backwards
        rnz
        pchl                ; run the checksum loader
Stack:  .word Loop
```

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "4K BASIC 3.2 from tape",
    "machine": "altair",
    "source": "${workspaceFolder}/boot.asm",
    "loadAddress": 0,
    "entryAddress": 0,
    "cassette": "${workspaceFolder}/4KBAS32.TAP",
    "console": "sio",
    "switches": 32768,
    "ramKilobytes": 32,
    "upperCase": true
}
```

The checksum loader reads its device from the sense switches too: the 3.2 loaders take the 88-ACR with A15 up, and
the 4.x loaders take device 3, the 88-ACR, in A11-A8. With the terminal's switches from the table above:

| Tape | Load address | Terminal | `switches` |
| --- | --- | --- | --- |
| 4K BASIC 3.2 | `$0FAE` | 88-SIO | `32768` (`$8000`) |
| 8K BASIC 3.2 | `$1FAE` | 88-SIO | `32768` (`$8000`) |
| 4K BASIC 4.0 | `$0FC2` | 88-2SIO | `768` (`$0300`) |
| 8K BASIC 4.0 | `$1FC2` | 88-2SIO | `768` (`$0300`) |
| Extended BASIC 4.0, 4.1 | `$3FC2` | 88-2SIO | `768` (`$0300`) |

A tape plays at 30 bytes a second, so 4K BASIC takes two and a half minutes and Extended BASIC nine; with
`fastCassette`, on by default, the machine runs as fast as it can meanwhile. Extended BASIC 4.1 also asks
`LINEPRINTER?`, where `C` answers that there is none but the console. The example gives 4K BASIC 3.2 32 KB, since
its memory test runs past the top of 64 KB (below). The tapes come from altairclone.com's "MITS
Tapes" CP/M disk; the `.TAP` files on it are the tapes' bytes.

Things to know:

- **Type a line at a time.** BASIC reads the keyboard while it prints, to check for ^C, and drops what it reads
  there, as on a real Altair: keys typed while it is busy are lost.
- **4K BASIC 3.2 with 64 KB.** Its memory test runs past `$FFFF` and overwrites BASIC, so answer the memory size,
  or give it less RAM. SIMH avoids this only because its boot ROM sits at `$FF00`, and hangs the same way without
  it.
- **Tapes.** 8K BASIC's `CSAVE "P"` saves the program to the 88-ACR's tape, and `CLOAD "P"` reads it back. Record
  from the Hardware view's cassette, or with `retro/media`; the recording is saved when the tape is ejected. To
  load, type `CLOAD`, then insert the tape, since it starts playing as it goes in.

## Disks and CP/M

A launch with `disks` fits the 88-DCDD and the DBL PROM and starts at `$FF00`, as an operator boots an Altair, so the
disk in drive 0 boots:

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "CP/M 2.2",
    "machine": "altair",
    "disks": ["${workspaceFolder}/cpm22b23-56k.dsk"],
    "upperCase": true
}
```

These 8-inch images, from deramp.com's Altair software archive, boot this way:

| Disk | What it does |
| --- | --- |
| Mike Douglas's CP/M 2.2b, 56K | Boots to `A>` with its console on the 88-2SIO. |
| Burcon's CP/M 2.2, 56K | Boots to its sign-on. |
| MITS Disk BASIC 5.0 | Asks `MEMORY SIZE?`. |
| Altair DOS | Asks `MEMORY SIZE?`. |

The drives are `disk0`-`disk3` in Retro Devices, where disks go in and come out, and a disk the machine has changed
can be saved to its image, saved as another, reverted or undone, as for the other machines' disks. Drive 0 is A: to
CP/M.

A launch with `diskController` and no disks has the drives empty; DBL waits for a disk in drive 0, so inserting one
boots it. `proms` chooses the PROMs: `["dbl"]` by default with the controller, `["dbl", "mbl"]` to add MBL, both
assembled from the SDK's sources, or from `sdkRoms` when the launch gives it. The launch still starts at
DBL; to load a tape with MBL, set the program counter to `$FE00` in the debugger and continue.

## Debugging

`"machine": "altair"` debugs an Altair with source debugging, the 8080 call stack (`CALL`, the conditional calls,
`RST` and interrupts), registers with the flags by name, cycle counts, `Keeps:` checks and I/O port watchpoints.
The launch options are `ramKilobytes` (1-64), `switches` (0-65535), `baudRate` (110-9600, for the 88-2SIO and
the 88-SIO), `console` (`2sio` or `sio`), `upperCase` (caps lock), `cassetteInterface` (the 88-ACR), `cassette` (a
`.tap` tape that plays from the start), `fastCassette` (run as fast as possible while a tape plays or records,
on by default), `disks` (up to four `.dsk` images, for drives 0-3), `diskController` (the 88-DCDD, on with disks)
and `proms` (`dbl` and `mbl`).

A `source` or `program` loads at `$0100` by default and starts there. With neither, the machine starts at DBL's
`$FF00` when DBL is fitted, and otherwise at `$0000` in empty RAM, which executes `NOP`s. MBL's source, and DBL's
copy loop, map to source lines; DBL's loader runs in RAM at `$2C00` once copied, which has no source map, so
stepping it shows disassembly.

```asm
.cpu I8080
        lxi sp,$1000
        mvi a,3             ; master reset the 88-2SIO's first ACIA
        out $10
        mvi a,$15           ; divide by 16, 8 bits, 1 stop bit
        out $10
        lxi h,Greeting
Print:  in $10              ; wait for TDRE
        ani 2
        jz Print
        mov a,m
        ora a
        jz Done
        out $11
        inx h
        jmp Print
Done:   hlt
Greeting: .byte "HELLO, ALTAIR", 13, 10, 0
```

The panel shows the terminal. **Ctrl** with a letter types its control character, the arrow keys send ^H, ^J, ^K and
^L as the ADM-3A's do, and **Ctrl+F12** or **Ctrl+Break** is RESET; the key bar has **Esc**, **Reset** and **Clear
Screen**.

## How it is checked

- [`AltairMachineTests`](../tests/Retrocore.Tests/AltairMachineTests.cs) run 8080 programs: printing, echoing,
  receive interrupts, the ACIA's master reset and overrun, the 88-SIO's status, input interrupt and overflow (its
  output interrupt is not tested), the 88-ACR's tape at 300 baud, playing and recording, sense switches, RAM size,
  the front panel and the terminal's controls.
- [`AltairBasicTests`](../tests/Retrocore.Tests/AltairBasicTests.cs) need SIMH's images in the external test
  data's `altair-basic` folder (or `RETROCORE_ALTAIR_BASIC`), and are inconclusive without them.
  - **From the images:** 4K BASIC 3.2 and 4.0 on both serial boards, and 8K BASIC 4.0 and Extended BASIC 4.0 on
    the 88-2SIO, each with SIMH's banner and bytes free at 32 KB, and a program's output.
  - **`CSAVE` and `CLOAD`:** 8K BASIC's `CSAVE` records the same bytes SIMH's tape punch does, and `CLOAD` reads them
    back.
  - **From MITS's tapes**, in the folder's `tapes` folder: 4K BASIC 3.2 and 4.0, 8K BASIC 3.2 and 4.0 and Extended
    BASIC 4.1 load through the front panel's bootstrap and the 88-ACR. The three SIMH has images of come up with
    the images' bytes free; SIMH has no 8K BASIC 3.2 or Extended BASIC 4.1 to compare with.
- [`AltairDiskTests`](../tests/Retrocore.Tests/AltairDiskTests.cs) check the 88-DCDD at exact cycles: selecting
  drives, the status bits, the head's load and settle, stepping's timing and track 0, each byte's arrival and how
  long it holds the data port, the two-bytes-a-pass read, a sector read from its first one bit, writing at ENWD's
  handshakes and a late write enable, and write protection. They check the images' sizes and trailer, the drives'
  mounts, and that DBL's and MBL's sources assemble to the PROMs' digests. With the PROM dumps and disk images in the
  external test data's `altair-disk` folder (or `RETROCORE_ALTAIR_DISK`), the sources match the dumps byte for byte,
  and CP/M 2.2b, Burcon CP/M, Disk BASIC 5.0 and Altair DOS boot through DBL; CP/M lists its disk, saves a file,
  which changes the disk, lists it with STAT and erases it. The same disks also boot on SIMH's `altairz80`, with
  its own boot ROM, which was checked by hand rather than by a test.
- [`RecoveryJournalTests`](../tests/Retrocore.Tests/RecoveryJournalTests.cs) keep a changed Altair disk, bring it
  back into a new machine's drive with its codec, and save it with the change and its trailer.
- The same programs, a greeting, an echo and a table of squares in decimal, print identically on SIMH's
  `altairz80` (open-simh `87eb7d5`, in 8080 mode), built outside the repository.
- [`Test-AltairDap.mjs`](../tools/Test-AltairDap.mjs) drives the debug adapter: breakpoints, the call stack,
  registers, step out, the terminal's frames, Clear Screen, typed keys, a port watchpoint, RESET, and a breakpoint
  after `HLT` that holds until a key's interrupt wakes the 8080, with the interrupt on the call stack. It records
  a tape through `retro/media` and plays it back from the `cassette` option. With 8K BASIC's image in the external
  test data it runs BASIC on the terminal, and with MITS's 4K BASIC 3.2 tape it loads BASIC with the bootstrap as
  a source and the tape in the 88-ACR. With CP/M 2.2b's image it boots CP/M from `disks`, checks the 88-DCDD's
  and PROMs' rows, lists the disk, saves a file under CP/M and saves the changed disk back to its image through
  `retro/device`.
