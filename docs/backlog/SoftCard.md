# Backlog: the Z80 SoftCards

Status: **agreed 2026-11-12.** The SoftCard is done on the Apple II, from the machine to the debugger and the
extension ([Apple II](../Apple2.md)). On the Apple III the slot bus and the SoftCard /// are built and boot CP/M, in
step with MAME; the debugger and the extension are left.

Microsoft's Z-80 SoftCard (1980) puts a Z80 on an Apple II slot card so the machine runs CP/M. The SoftCard ///
(1982) does the same for the Apple III. Both borrow the host's memory by DMA, so the 6502 stops while the Z80 runs.

## The SoftCard ///

From MAME's `softcard3` (a "best guess" from the boot disk and checks on real hardware, by Rob Justice and
R. Belmont), Rob Justice's disassembly of the boot blocks, and the installation manual
([archive.org](https://archive.org/details/apple-iii-soft-card-iii-installation-and-operation-manual)). This goes
into `docs/Apple3.md` with the debugger work.

| Part | What it does |
| --- | --- |
| Clock | Twice the slots' 1.02 MHz. The boot code puts the III in 1 MHz mode before switching. |
| Mapping PROM | 256 bytes: the Apple address is the Z80's low byte plus the PROM entry for its high byte, times 256. The DMA goes into the 6502's view, so it follows the bank and zero-page registers. Z80 `$0000` is Apple `$2000`, the I/O page is at Z80 `$A000` and zero page at `$F000`. |
| Registers | At `$C080 + slot * 16`. A read returns `$50`, which the boot code looks for. Writing `$01` arms a Z80 reset for the next switch; writing `$10` lets the card answer reads of `$FFFC` and `$FFFD`. |
| Switching | A 6502 **read of `$FFFC`** hands the bus to the Z80 and starts a supervision timer; a read of `$FFFD` stops the timer. The Z80 hands the bus back with `OUT ($00),A`. If the timer fires first, the card hands it back anyway, so the 6502 can serve SOS. MAME's period, 5 Hz, is marked as unchecked. |
| Interrupts | Not modelled by MAME. |
| Boot | Its own boot blocks, not SOS's. They load at `$A000`, look for the card from slot 4 down, load the SOS drivers named in `DRIVER.SOS`, and run CP/M's console, printer and disk I/O through those drivers on the 6502. The banner is "Apple SoftCard /// CP/M 56K Version 2.20". |

What exists: `SoftCard3` and the slot bus (`IApple3Card`, `Apple3Bus.InstallSoftCard`) in the Apple III project, on
the `Z80Card` base the Apple II's `SoftCard` shares; `Roms/SoftCard3Prom.asm`, byte-identical to MAME's
`softcard3.rom`; `SoftCard3Tests` and `SoftCard3OracleTests`. The fixtures are in `%USERPROFILE%\Retrocore\softcard3`.

## Next: debugger and extension, Apple III

As the Apple II's SoftCard has them:

- **The Z80 thread.** Generalize `SoftCardDebugTarget` from `SoftCard` to `Z80Card`, and give `Apple3DebugTarget` a
  coprocessor, the `z80` bank and `StepTState`. `Apple3Machine` runs the Z80 by time, not by half cycles, so its
  T-state step needs its own shape.
- **Launch and hardware.** `softCard3: <slot>` in the launch (slots 1-4, 4 by default) and the machine state; the
  Apple III's slot rows, Add Card › SoftCard /// and `removeCard`; the PROM assembled from the SDK's source. Its
  refresh-read switch, if it should be shown at all.
- **Docs and tests.** `docs/Apple3.md` and `docs/Devices.md`; the extension's Add Card entry, schema and README; a DAP
  script that boots CP/M to a `z80:0x0000` breakpoint and `A>`.

## Later

- Z80 interrupts from the DIP switches, if any software uses them.
- Apple III slot interrupts (VIA 0 CA1, VIA 1 PA4-PA5 and `$C064`/`$C065`, as MAME wires them), for a card that
  needs them.
- The line-end clock stretch (69 ns a line), if a test can tell.
- Microsoft's Premium SoftCard IIe and CP/M 3 (which wants slot 4 or 5).
- CP/M sources: the 6502 side of the BIOS, written to assemble byte-identically, as the other ROMs are.
- CP/M disks in the media library ([media](Media.md)).
- Other Z80 cards: PCPI's AppliCard, which MAME lists for both machines.
- ZEXDOC and ZEXALL under SoftCard CP/M, as an end-to-end check against the core's own results.

## Decisions

Agreed 2026-11-12 ("Looks right"):

- The Z80 is its own debugger thread, not a CPU thread that changes ISA when the bus changes hands.
- The SoftCard models the 6502's refresh cycle after each M1, with two T-states per Apple cycle. An option leaves the
  refresh out, so the oracle test can match MAME. The SoftCard /// starts with it off, as no source says it has one.
- The SoftCard is a card added in the Machine view (the Retro Devices view when decided), or with the launch's `softCard`, not an entry in the Run
  and Debug dropdown (decided 2026-11-12). The SoftCard /// follows suit.
- Each fixture download is approved on its own, with its site, file and checksum, and saved under
  `%USERPROFILE%\Retrocore`, never committed.
