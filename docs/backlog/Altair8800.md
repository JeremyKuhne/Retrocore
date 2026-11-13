# Backlog: the MITS Altair 8800

Status: **phases 1 and 2 built (2026-11-13)**; [the guide](../Altair8800.md) covers them. Phases 3-5 are next. The first machine for the 8080
([CPU backlog](I8080.md)), and the one that started personal computing: an S-100 bus, a front panel of switches
and lights, and boards for serial terminals, cassette and 8-inch disks.

## Why the Altair

- It is the 8080's defining machine, and Altair BASIC was Microsoft's first product.
- It is small: a CPU board, RAM and a serial board make a working machine, so the 8080 gets a debug target early,
  and each further board adds software that runs.
- Its software is well preserved: Altair BASIC (4K, 8K, Extended, Disk), CP/M 2.2 and many disk images, all of it
  run on SIMH's `altairz80`, which makes a good oracle.

## The hardware

| Part | What it is | Ports and addresses |
| --- | --- | --- |
| CPU | 8080A at 2 MHz (500 ns states) | |
| Memory | S-100 RAM boards, 1 to 64 KB | |
| Front panel | 16 address/data switches, status and address/data lights; STOP, RUN, SINGLE STEP, EXAMINE (NEXT), DEPOSIT (NEXT), RESET; the high 8 switches read as sense switches | `IN $FF` |
| 88-2SIO | Two MC6850 ACIAs: serial terminals. Most later software (BASIC 4.x and later, CP/M) uses it | `$10`-`$11`, `$12`-`$13` |
| 88-SIO | The original single serial board, with active-low status | `$00`-`$01` |
| 88-ACR | Audio cassette, an 88-SIO with a modem; how BASIC was first loaded | `$06`-`$07` |
| 88-DCDD | 8-inch disk controller and drives (77 tracks, 32 sectors of 137 bytes) | `$08`-`$0A` |
| 88-DBL / MBL | The disk boot loader and multi-boot loader PROMs | `$FF00`, `$FE00` |

The ACIA joins the shared chips in `Retrocore.Core` (`Machines/Chips`), as the 6821 and 6522 did.

## Software

Every program the Altair ran is copyrighted, so, as for the other machines, it is supplied by the user:

- **Altair BASIC** 4K, 8K and Extended, as binary images or paper tapes, loaded over the serial port or into
  memory directly. Its documented sense-switch settings choose the terminal board.
- **CP/M 2.2 and Altair Disk BASIC** on 8-inch disk images in SIMH's format (77 tracks of 32 137-byte sectors,
  337,568 bytes).
- **The boot PROMs** (88-DBL, MBL) become documented SDK sources rebuilt byte-identically to dumps the user
  supplies, as the other machines' ROMs did. Until then the disk boots through a loader the debugger deposits,
  as an operator keyed one in through the front panel.

## The debug target

- Launch id `altair`, with options for RAM, boards (`2sio`, `sio`, `acr`, `dcdd`) and the sense switches.
- The terminal as the machine's screen: an 80-column teletype-style console on the 2SIO's first port.
- Assembling `source`, loading a `program` binary at an address, and mounting disk images, as the other machines
  do.
- A call tracker for `CALL`, the conditional calls, `RST` and interrupts, checked against the stack as the Z80's
  is; the register view with the flags by name; `Keeps:` sections naming 8080 registers.
- The front panel as a VS Code view: its lights follow the address and data buses while the machine runs, and its
  switches examine and deposit memory.

## Phases

1. **The machine.** `Retrocore.Machines.Altair`: the 8080, RAM, the 88-2SIO with the MC6850, sense switches, and a
   front panel model (examine, deposit, run, stop, single step) with no UI. Tests run small 8080 programs through
   the serial port.
2. **The debug target.** Launching `altair`, the terminal, the call tracker and register view, `source` and
   `program` launches, and a DAP test script like the other machines'.
3. **BASIC.** Altair BASIC 4K and 8K from user-supplied images, over the 2SIO; the 88-SIO and 88-ACR for the
   versions that need them, with tape images.
4. **Disks.** The 88-DCDD and its drives, SIMH disk images, the boot loaders as SDK sources, and CP/M 2.2.
5. **The front panel view** in the extension.

## Testing

- The machine against SIMH's `altairz80` with the same keystroke-oracle approach the Model I and CoCo use.
- The ACIA against the MC6850 data sheet's status and interrupt behaviour.
- The boot PROMs pinned by digest, once their sources exist.
- A DAP script like the Model I's.

Every download (SIMH, software images, ROM dumps) is approved first, as before.

## Decisions (agreed 2026-11-13)

- **Project and launch id.** A new `Retrocore.Machines.Altair`, launch id `altair`.
- **Defaults.** 64 KB RAM, the 88-2SIO on `$10`, sense switches set for a 2SIO terminal. The MC6850 ACIA joins
  the shared chips in `Retrocore.Core`.
- **This round: phases 1 and 2**, so the 8080 runs and debugs in a machine. BASIC, disks and the front panel view
  stay in the backlog.
- **Oracle.** SIMH's `altairz80`, built locally outside the repository.
- **Software** is supplied by the user; the boot PROMs become SDK sources once dumps are available.
