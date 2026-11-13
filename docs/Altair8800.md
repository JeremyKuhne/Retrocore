# The MITS Altair 8800

Retrocore's Altair 8800 is [`AltairMachine`](../src/Retrocore.Machines.Altair/AltairMachine.cs): a state-exact 8080,
RAM, the 88-2SIO serial board with a terminal on its first port, and the front panel's switches. This guide covers
what it emulates and how to debug on it. [The backlog](backlog/Altair8800.md) has what comes next: Altair BASIC,
the 88-DCDD disks with CP/M, and a front panel view.

## The machine

| Part | Addresses or ports | Emulated |
| --- | --- | --- |
| RAM | `$0000` up | 1 to 64 KB (`RamKilobytes`, 64 by default). Addresses past it read `$FF`, as the S-100 bus's pull-ups leave them, and lose writes. |
| 88-2SIO | Ports `$10`-`$11` and `$12`-`$13` | Two MC6850 ACIAs. The terminal is on the first; the second has nothing connected. |
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

**Interrupts.** The ACIAs' interrupt requests drive the 8080's INT line: a full receiver with control bit 7 set,
or an empty transmitter with bits 5-6 at `01`. The Altair has no vectored interrupt board here, so the acknowledge
reads the floating bus's `$FF`, `RST 7`, and the handler is at `$0038`.

**Terminal.** An 80-by-24 glass teletype with the Lear Siegler ADM-3A's controls, the most common terminal on
Altairs: ^H left, ^J down, ^K up, ^L right, ^M to the first column, ^Z clear and home, ^^ home, and ESC `=` row
column, each plus `$20`, to place the cursor. Printable characters wrap after the 80th column, and the line after
the last scrolls the screen. Bit 7 is ignored, and other controls, ^I among them, do nothing. The characters are
8 by 8 in 8-by-10 cells, white on black. Typed keys go out one character time apart, and only into an empty
receive register, so typing ahead or pasting never overruns the ACIA.

**Front panel.** [`AltairFrontPanel`](../src/Retrocore.Machines.Altair/AltairFrontPanel.cs) models the 16
switches and EXAMINE, EXAMINE NEXT, DEPOSIT and DEPOSIT NEXT, as an operator keyed programs in. The debugger's
RUN, stop, step and RESET stand in for the panel's own switches; the panel has no view in the extension yet.

## Debugging

`"machine": "altair"` debugs an Altair with source debugging, the 8080 call stack (`CALL`, the conditional calls,
`RST` and interrupts), registers with the flags by name, cycle counts, `Keeps:` checks and I/O port watchpoints.
The launch options are `ramKilobytes` (1-64), `switches` (0-65535) and `baudRate` (110-9600).

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
  receive interrupts, the ACIA's master reset and overrun, sense switches, RAM size, the front panel and the
  terminal's controls.
- The same programs, a greeting, an echo and a table of squares in decimal, print identically on SIMH's
  `altairz80` (open-simh `87eb7d5`, in 8080 mode), built outside the repository.
- [`Test-AltairDap.mjs`](../tools/Test-AltairDap.mjs) drives the debug adapter: breakpoints, the call stack,
  registers, step out, the terminal's frames, Clear Screen, typed keys, a port watchpoint, RESET, and a breakpoint
  after `HLT` that holds until a key's interrupt wakes the 8080, with the interrupt on the call stack.
