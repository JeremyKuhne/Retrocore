# Backlog: the Model III family's and the Model II's ROMs and software

The [Model III, 4, 4P, II, 12 and 16](../Trs80Model3And2.md) run the SDK's sources of their ROMs, which are
byte-identical to MAME's dumps, and boot to their prompts. This is what remains for them to match the Model I.

**Status:** proposed; nothing here is approved yet.

## Stages

1. **Run the real ROMs.** Done for the first prompts: `Trs80Model3RomTests` boots the SDK's builds, the Model III and
   Model 4 through `Cass?` and `Memory Size?` to BASIC, the 4P to its drive-not-ready message, and the Model II to
   `INSERT DISKETTE`, every boot ROM version among them. Writing the sources turned up two ports the emulation got
   wrong, now fixed: the Model III's RS-232 ports read `$FF`, as with no board, and the Model II's hard disk board's
   ports read zero, so versions 2 and 3 of its boot ROM boot from the floppy. Still open:
   - The Model 4's real-time clock and the function keys' codes (`$60`, `$1B` and `$08` with shift) are untested.
2. **Boot their DOSes.** TRSDOS 1.3 and LDOS 5.3 on the Model III, TRSDOS 6 (LS-DOS) on the Model 4 and 4P, and
   TRSDOS-II on the Model II, from DMK, JV3 or IMD images; check the FD1793's wait states, the Model II's DMA and the
   keyboard codes against them.
3. **An oracle.** As `Trs80OracleTests` compares the Model I with MAME, compare the same keystrokes on MAME's
   `trs80m3`, `trs80m4` and `trs80m2`.
4. **ROM sources.** Done: `Model3.asm` (sharing Level II's BASIC through `Level2.asm`), `Model4PBoot.asm`,
   `Model2Boot.asm` and the character generators, with each build's `Keeps:` contracts checked by its own `MODEL`.
   The Model III's Level I ROM (`8040032`) is `Level1.asm` with `MODEL = 3`, and a Model III launches with it. Still to
   write: MAME's `cpu_fc86` Model II boot ROM, which MAME lists but has no dump of.
5. **1500 baud cassettes.** Done: `CSAVE` and `CLOAD` at 1500 baud on the Model III and 4, timed as the ROM's source
   writes and reads, and high-speed CAS images.
6. **Writing disk images back**, for every TRS-80, in their own formats.
