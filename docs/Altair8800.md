# The MITS Altair 8800

Retrocore's Altair 8800 is [`AltairMachine`](../src/Retrocore.Machines.Altair/AltairMachine.cs): a state-exact 8080,
RAM, the 88-2SIO serial board or the original 88-SIO with a terminal, the 88-ACR cassette interface, and the front
panel's switches. It runs Altair BASIC from images you supply. This guide covers what it emulates and how to debug
on it. [The backlog](backlog/Altair8800.md) has what comes next: the 88-DCDD disks with CP/M, and a front panel
view.

## The machine

| Part | Addresses or ports | Emulated |
| --- | --- | --- |
| RAM | `$0000` up | 1 to 64 KB (`RamKilobytes`, 64 by default). Addresses past it read `$FF`, as the S-100 bus's pull-ups leave them, and lose writes. |
| 88-2SIO | Ports `$10`-`$11` and `$12`-`$13` | Two MC6850 ACIAs. The terminal is on the first unless it is on the 88-SIO; the second has nothing connected. |
| 88-SIO | Ports `$00`-`$01` | When the terminal is on it (`Console`). |
| 88-ACR | Ports `$06`-`$07` | An 88-SIO at 300 baud with a cassette recorder (`CassetteInterface`, on by default). |
| Sense switches | Port `$FF` | The front panel's high 8 switches (`Switches`). |

Every other port reads `$FF` and ignores writes.

**CPU.** The 8080 runs at 2 MHz, a 500 ns state, with each machine cycle's bus access on the state the chip makes it
([`Retrocore.Cpu.I8080`](../src/Retrocore.Cpu.I8080)). The Altair has no ROM: at power-on and RESET the 8080 starts
at `$0000`, in whatever RAM holds.

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

## Debugging

`"machine": "altair"` debugs an Altair with source debugging, the 8080 call stack (`CALL`, the conditional calls,
`RST` and interrupts), registers with the flags by name, cycle counts, `Keeps:` checks and I/O port watchpoints.
The launch options are `ramKilobytes` (1-64), `switches` (0-65535), `baudRate` (110-9600, for the 88-2SIO and
the 88-SIO), `console` (`2sio` or `sio`), `upperCase` (caps lock), `cassetteInterface` (the 88-ACR), `cassette` (a
`.tap` tape that plays from the start) and `fastCassette` (run as fast as possible while a tape plays or records,
on by default).

A `source` or `program` loads at `$0100` by default and starts there. With neither, the machine starts at `$0000`
in empty RAM, which executes `NOP`s.

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
  receive interrupts, the ACIA's master reset and overrun, the 88-SIO's status, interrupts and overflow, the
  88-ACR's tape at 300 baud, playing and recording, sense switches, RAM size, the front panel and the terminal's
  controls.
- [`AltairBasicTests`](../tests/Retrocore.Tests/AltairBasicTests.cs) run 4K BASIC 3.2 and 4.0, 8K BASIC 4.0
  and Extended BASIC 4.0 on both serial boards, and 8K BASIC's `CSAVE` and `CLOAD`, when SIMH's images are in the
  external test data's `altair-basic` folder (or `RETROCORE_ALTAIR_BASIC`). Each prints what SIMH's does, with the
  same bytes free at 32 KB, and `CSAVE` records the same bytes SIMH's tape punch does. With MITS's tapes in its
  `tapes` folder, they also load 4K BASIC 3.2 and 4.0, 8K BASIC 3.2 and 4.0 and Extended BASIC 4.1 through the
  front panel's bootstrap and the 88-ACR. Without the files they are inconclusive.
- The same programs, a greeting, an echo and a table of squares in decimal, print identically on SIMH's
  `altairz80` (open-simh `87eb7d5`, in 8080 mode), built outside the repository.
- [`Test-AltairDap.mjs`](../tools/Test-AltairDap.mjs) drives the debug adapter: breakpoints, the call stack,
  registers, step out, the terminal's frames, Clear Screen, typed keys, a port watchpoint, RESET, and a breakpoint
  after `HLT` that holds until a key's interrupt wakes the 8080, with the interrupt on the call stack. It records
  a tape through `retro/media` and plays it back from the `cassette` option. With 8K BASIC's image in the external
  test data it runs BASIC on the terminal, and with MITS's 4K BASIC 3.2 tape it loads BASIC with the bootstrap as
  a source and the tape in the 88-ACR.
