# Backlog: the Z80 SoftCards

Status: **agreed 2026-11-12.** The SoftCard is done on the Apple II ([Apple II](../Apple2.md)) and the SoftCard /// on
the Apple III ([Apple III](../Apple3.md#the-softcard-)), from the machine to the debugger and the extension. What is
left is below, each only if wanted.

Microsoft's Z-80 SoftCard (1980) puts a Z80 on an Apple II slot card so the machine runs CP/M. The SoftCard ///
(1982) does the same for the Apple III. Both borrow the host's memory by DMA, so the 6502 stops while the Z80 runs.

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
- The SoftCard is a card added in the Machine view (the Retro Devices view when decided), or with the launch's
  `softCard`, not an entry in the Run and Debug dropdown (decided 2026-11-12). The SoftCard /// follows suit, with
  `softCard3`.
- Each fixture download is approved on its own, with its site, file and checksum, and saved under
  `%USERPROFILE%\Retrocore`, never committed.

Agreed 2026-11-20 ("Approve, hide switch"):

- The SoftCard ///'s refresh-read switch is not shown: no source says the card has one, and the Apple III's video
  refreshes its RAM.
- The SoftCard /// thread is "SoftCard /// Z80"; a Z80 source launched on it keeps the bus until its `OUT ($00),A`,
  with the supervision timer off.
