# Backlog: the Z80 SoftCards

Status: **agreed 2026-11-12.** Phases 0-2 are built; phase 2 awaits review.

Microsoft's Z-80 SoftCard (1980) puts a Z80 on an Apple II slot card so the machine runs CP/M. The SoftCard ///
(1982) does the same for the Apple III. Both borrow the host's memory by DMA, so the 6502 stops while the Z80
runs. Neither card has RAM. The first card has no ROM, and the second has only a 256-byte mapping PROM.

Retrocore already has the pieces: the cycle-exact Z80 core from the Model I, the Apple II and Apple III machines,
and a debugger that can show more than one thread. The new parts are the cards, an Apple III slot bus, and a
second CPU in one debug session.

## The hardware

### The SoftCard (II, II Plus, IIe)

From the SoftCard manual's Part 2, "Software and Hardware Details"
([archive.org](https://archive.org/details/mscard_software_hardware_details)), checked against MAME's
`a2softcard` and AppleWin's `Z80Card`.

| Part | What it does |
| --- | --- |
| Clock | Built from the Apple's 7M and locked to it: three short half-periods in Φ1, then low through Φ2. That makes 2.041 MHz, two T-states per Apple cycle, and one memory access per machine cycle in Φ2. There are no wait states. MAME and AppleWin both use exactly twice the Apple clock. |
| 6502 refresh | The card holds the 6502 on DMA and RDY. After each Z80 opcode fetch, during M1's refresh, it lets the 6502 make one bus cycle, so the NMOS 6502's dynamic registers keep their state. No emulator models this. |
| Switching | A 6502 **write** anywhere in `$Cn00-$CnFF` hands the bus to the Z80. A Z80 write to `$En00`, the same address after translation, hands it back. Reads do nothing. The Z80 resumes where it stopped; it is not reset. |
| Reset | Apple RESET turns the card off. The Z80 waits from power-on, and MAME resets it on the first switch after a reset. |
| Addresses | Z80 `$0000-$AFFF` is Apple `$1000-$BFFF`; `$B000` is `$D000`, `$C000` is `$E000`, `$D000` is `$F000`, `$E000` is the I/O page `$C000`, and `$F000` is `$0000`. DIP switch S1-1 on turns translation off. |
| Lines | IN and OUT are not decoded. S1-4 wires the Apple's IRQ to INT and S1-3 its NMI to NMI. An acknowledge reads `$FF`. CP/M leaves interrupts off and handles them on the 6502. |
| ROM | None. A 6502 boot from a 16-sector disk (or 13-sector for 2.20) loads CP/M and switches. The 6502 call protocol (`$3C0`, `$3D0`, `$3DE`, `$45-$49`) is software, not card logic. |
| IIe | The card's accesses go through the IIe's memory switches as the 6502's do: RAMRD, RAMWRT, ALTZP and the language card. MAME does this too. No primary source says so, and the CP/M images will tell us. |

### The SoftCard ///

From MAME's `softcard3` (a "best guess" from the boot disk and checks on real hardware, by Rob Justice and
R. Belmont), Rob Justice's disassembly of the boot blocks, and the installation manual
([archive.org](https://archive.org/details/apple-iii-soft-card-iii-installation-and-operation-manual)).

| Part | What it does |
| --- | --- |
| Clock | Twice the Apple's 1 MHz, as for the SoftCard. The boot code puts the III in 1 MHz mode before switching. |
| Mapping PROM | 256 bytes: the Apple address is the Z80's low byte plus the PROM entry for its high byte, times 256. The DMA goes into the 6502's view, so it follows the bank register. The boot code's self-test puts Z80 `$0000` at Apple `$2000`. |
| Registers | At `$C0n0-$C0nF`. A read returns `$50`, which the boot code looks for. Writing `$01` arms a Z80 reset for the next switch; writing `$10` enables the card's inhibit-mapped addresses. |
| Switching | A 6502 **read of `$FFFC`** hands the bus to the Z80 and starts a supervision timer; a read of `$FFFD` stops the timer. The Z80 hands the bus back with `OUT ($00),A`. If the timer fires first, the card hands it back anyway, so the 6502 can serve SOS. MAME's period, 5 Hz, is marked as unchecked. |
| Interrupts | Not modelled by MAME. |
| Boot | Its own boot blocks, not SOS's. They load at `$A000`, look for the card from slot 4 down, load the SOS drivers named in `DRIVER.SOS`, and run CP/M's console, printer and disk I/O through those drivers on the 6502. The banner is "Apple SoftCard /// CP/M 56K version 2.20". |

The Apple III has no slot bus in Retrocore yet: `$C0n0` I/O, `$Cn00` and `$C800` ROM spaces, slot interrupts, and
DMA. The SoftCard /// needs only the I/O space and DMA, but the bus should be built for any card.

## Shape in the code base

- **A Z80 card that any 6502 machine can host.** A `SoftCard` type in the Apple II project owns a
  `Z80Processor<SoftCardBus>`, the translation and the switch. Its bus reads and writes through the host's bus with
  side effects, so keyboard strobes and soft switches work from the Z80, and through the IIe's switches.
- **Clocking.** The machine's step ticks the card. While the Z80 owns the bus, the 6502 is held on RDY and the card
  runs two T-states per Apple cycle. The refresh cycle after each M1 is a real 6502 read that the 6502 discards.
  The video, disk and audio keep their cycle as now. Machines without a SoftCard pay nothing, and the core speed
  benchmarks must not move ([core speed ledger](CoreOptimization.md)).
- **The SoftCard /// shares the card's Z80 and clocking**, with its own PROM mapping, registers and timer, in the
  Apple III project. The PROM is rebuilt byte-identically from our own source, as the ROMs are.
- **An Apple III slot bus** in `Apple3Bus`: four slots, `$C0n0` I/O, `$Cn00` and `$C800` ROM spaces, and DMA. The
  SoftCard /// is its first card.
- **The debugger shows the Z80 as a second thread**, "SoftCard Z80", beside the 6502's (and the BASIC thread
  where there is one). Each thread has its own registers, call stack, disassembly (Z80 or 6502) and breakpoints,
  in its own address space. Only the CPU that owns the bus runs, so its thread is the one that stops; a step on
  the other thread runs until that CPU gets the bus and finishes an instruction. Breakpoints in a `.cpu Z80`
  source bind to the Z80 thread.
- **Launch and hardware rows.** `softCard: <slot>` installs the card at launch (any free slot; 4 is the
  manual's). The hardware view gets **Add Card** › SoftCard on free slots, and `removeCard`. The machine state
  saves it as `softCard`. The Apple III gets `softCard3: <slot>` and the same actions on its slots 1-4.

## Phases

Each phase ends in a review before the next one starts.

### 0. Fixtures and references

Each download is approved on its own, with its site, file and checksum, and saved under
`%USERPROFILE%\Retrocore`, never committed.

- **`softcard-disks`**, from the Asimov mirror's `images/cpm/os` (143,360 bytes each):
  `Softcard 16-sector disk (Microsoft 1980).dsk`, `CPM_Z80SoftCard.dsk`, `CPM2.2(56k).dsk` and
  `CPM2.23(60k).dsk`. archive.org's `049_Microsoft_Softcard_Original_Master.dsk` (SHA-1 `c84529c9...0306`) is a
  second source for the master.
- **`softcard3`**, from the Asimov mirror's `images/apple3/system/os`: `Apple Softcard III CPM Master Diskette
  (076-0002) Apple 1982.dsk` and `SOS-CPM Utilities Diskette (076-0001) Apple 1982.dsk`. Also MAME's
  `softcard3.rom` (256 bytes, CRC `9d4433b2`, SHA-1 `aff45dd8...99a4`) as the PROM's oracle.
- **`docs\softcard`**: the SoftCard manual's Part 2 and its schematic (archive.org `apple_schematics_Softcard`),
  and the SoftCard /// installation manual.
- MAME 0.289 (already cached) has both cards and is the trace oracle.

Done 2026-11-12. Every file matched its published hash; the disks, which have none, have SHA-256 in their
`README.txt`. MAME's II Plus ROM path was built from the local chip dumps in `apple2-roms\mame` (`apple2p`,
`a2diskiing`, `d2fdc`), with no download.

### 1. The SoftCard

- The card, the switch, translation, reset, the clock and the refresh cycle, on the II, II Plus and IIe.
- Unit tests with small Z80 programs that need no disk: translation, the switch both ways, keyboard reads from
  `$E000`, and a 6502 call through the CP/M convention.
- **Done when** each CP/M image reaches `A>` on the II Plus with a language card and on the IIe, `DIR` lists the
  disk, and a Z80 trace matches MAME's from the first switch.

Built 2026-11-12:

- `SoftCard` and `SoftCardBus` in the Apple II project; `Apple2Bus.InstallSoftCard` and `RemoveSoftCard`; and
  `Apple2Machine.StepWithSoftCard`. The 6502 is held at its next opcode fetch, so it simply stops stepping (its
  cycle count stops too, while the bus's goes on). After the Z80 hands the bus back, both run until WAIT holds the
  Z80's next access. `Z80Processor.IsWaiting` is new. `SoftCard.InstructionBoundary` is a hook for the oracle and
  for phase 2's breakpoints.
- `Apple2SoftCardTests` (8 tests, no disks), `Apple2CpmTests` (four disks on the II Plus and the IIe: 2.20, 2.20,
  2.20B and Datasoft's 2.23B all reach `A>` and list their files), and `Apple2SoftCardOracleTests` (Conformance).
- MAME's trace takes no register log for the Z80 here: `tracelog` actions write nothing in this setup, even with
  `focus`. The oracle compares the instruction addresses instead, with back-to-back loops collapsed, from the first
  switch to CP/M's wait for a key. They match.
- Machines without the card: the enhanced IIe's loop ran 45.0 M cycles/s against `HEAD`'s 45.7 M (four interleaved
  runs of 100 M cycles, Release), inside the runs' ±5% spread.
- With the card on the IIe, the firmware may leave INTCXROM on mid-routine; a store to `$Cn00` then reaches the
  firmware, not the card, as on the real machine.

### 2. Debugger and extension, Apple II

- The Z80 thread, `softCard` in the launch and the machine state, the hardware row and its actions, and
  `docs/Apple2.md` and `docs/Devices.md`. The card is hardware added from the Retro Devices view, not a machine in
  the Run and Debug dropdown.
- **Done when** a DAP test boots CP/M, stops at a Z80 breakpoint in a launched `.cpu Z80` program, steps it, and
  shows both threads' registers; the extension's editor test does the same.

Built 2026-11-12:

- **The machine.** `Apple2Machine.StepTState` advances half a cycle while the Z80 runs, so the debugger can stop at a
  Z80 instruction that starts mid-cycle; `StepCycle` finishes a half-done cycle first. `SoftCard.WaitingAtInstruction`
  says WAIT holds the Z80 at its next instruction's fetch, which counts as a boundary. `SoftCard.TakeBus` starts a
  launched Z80 program.
- **The debugger.** `IDebugTarget.Coprocessor` and `CoprocessorActive`; `SoftCardDebugTarget` is the Z80's view,
  with its own memory area (`SoftCardMemoryArea.Z80`) so Z80 modules and 6502 modules never match each other's
  addresses, and the `z80` bank, which carries the Z80 instruction set for the Disassembly view. The session's `Cpu`
  is the view with the bus: the run, `Execute`, `Observe`, `Hit` and conditions use it, while memory, devices and
  the display stay the machine's. The Z80 is thread 3, its frames numbered from 1001. A step runs until its own
  thread's CPU has stepped. Calls and contracts are followed only on the 6502; the Z80's calls come from the card's
  instruction boundaries. A bare-address breakpoint is the 6502's.
- **The launch.** `softCard: <slot>`; a `.cpu Z80` source (its first `.cpu` line) loads through the card at $0100
  and the Z80 takes the bus at its entry. `sample/softcard/count.asm` and the workspace's "II Plus: SoftCard Z80
  sample" configuration.
- **Switches.** Hardware rows can carry `settings` (`HardwareSetting`), changed by `setSetting` and saved in the
  machine state's `settings`. The SoftCard's are `translation` and `refresh`, checkboxes under its row in the Retro
  Devices view (asked for after phase 2).
- **Hardware.** The slot's row ("Z80 SoftCard"), `addSoftCard`, `removeCard`, and `softCard` in the saved cards. The
  extension's Add Card menu, `softCard` in the launch schema, and its README (by a subagent; 58 unit tests pass).
- **Tests.** `tools/Test-SoftCardDap.mjs` (a Z80 source: entry, steps, a call, a breakpoint, both threads, the
  disassembly, the hardware row; then CP/M from its disk to a `z80:0x0000` instruction breakpoint and to `A>`), and
  the editor test's SoftCard sample.

### 3. The Apple III slot bus and the SoftCard ///

- The slot bus, the card, `SoftCard3Prom.asm` (byte-identical to the dump), the registers and the timer.
- **Done when** the CP/M master reaches `A>` with its SOS drivers, `DIR` works, the boot code's self-test passes,
  and a trace matches MAME's.

### 4. Debugger and extension, Apple III

- As phase 2, on the Apple III, with `docs/Apple3.md`.

## Later

- Z80 interrupts from the DIP switches, if any software uses them.
- The line-end clock stretch (69 ns a line), if a test can tell.
- Microsoft's Premium SoftCard IIe and CP/M 3 (which wants slot 4 or 5).
- CP/M sources: the 6502 side of the BIOS, written to assemble byte-identically, as the other ROMs are.
- CP/M disks in the media library ([media](Media.md)).
- Other Z80 cards: PCPI's AppliCard, which MAME lists for both machines.
- ZEXDOC and ZEXALL under SoftCard CP/M, as an end-to-end check against the core's own results.

## Decisions

Agreed 2026-11-12 ("Looks right"):

- The Z80 is its own debugger thread, not a CPU thread that changes ISA when the bus changes hands.
- The card models the 6502's refresh cycle after each M1, with two T-states per Apple cycle. An option leaves the
  refresh out, so the oracle test can match MAME.
- The Apple II card comes first, then the Apple III, in the phase order above, with a review after each phase.
- The SoftCard is a card added in the Retro Devices view (or with the launch's `softCard`), not an entry in the Run
  and Debug dropdown (decided 2026-11-12, after phase 2).
- Each phase 0 download is approved on its own, with its site, file and checksum.
