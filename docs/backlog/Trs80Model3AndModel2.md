# Backlog: the Model III family's and the Model II's ROMs and software

The [Model III, 4, 4P, II, 12 and 16](../Trs80Model3And2.md) run the SDK's sources of their ROMs, which are
byte-identical to MAME's dumps, and boot to their prompts. This is what remains for them to match the Model I.

**Status:** proposed; nothing here is approved yet.

## Stages

1. **Run the real ROMs.** Done for the first prompts: `Trs80Model3RomTests` boots the SDK's builds, the Model III and
   Model 4 through `Cass?` and `Memory Size?` to BASIC, the 4P to its drive-not-ready message, and the Model II to
   `INSERT DISKETTE`. Writing the sources turned up what the emulation still gets wrong for them:
   - The Model III's RS-232 set-up takes port `$EA` reading `$FF` as no RS-232 board; the emulation answers as if one
     were there. With no board it should read `$FF`.
   - The Model II boot ROM's versions 2 and 3 take port `$C2` reading nonzero in its low bits as a hard disk board, and
     unmapped ports read `$FF`. By the code, they would find a drive ready, time out restoring it, and show
     `BOOT ERROR H0` until ESC or BREAK sends them to the floppy; this has not been run. Version 5, which launches use,
     checks the controller's registers instead and asks for a diskette, as `Trs80Model3RomTests` shows.
   - The Model 4's real-time clock and the function keys' codes (`$60`, `$1B` and `$08` with shift) are untested.
2. **Boot their DOSes.** TRSDOS 1.3 and LDOS 5.3 on the Model III, TRSDOS 6 (LS-DOS) on the Model 4 and 4P, and
   TRSDOS-II on the Model II, from DMK, JV3 or IMD images; check the FD1793's wait states, the Model II's DMA and the
   keyboard codes against them.
3. **An oracle.** As `Trs80OracleTests` compares the Model I with MAME, compare the same keystrokes on MAME's
   `trs80m3`, `trs80m4` and `trs80m2`.
4. **ROM sources.** Done: `Model3.asm` (sharing Level II's BASIC through `Level2.asm`), `Model4PBoot.asm`,
   `Model2Boot.asm` and the character generators. Still to write: the Model III's Level I ROM (`8040032`, mostly the
   Model I's Level I relocated), for a Model III Level I machine, and MAME's `cpu_fc86` Model II boot ROM, which MAME
   lists but has no dump of.
5. **1500 baud cassettes**, whose timing the ROM's source now gives: a bit is one cycle of the signal, about 18 or 23
   counts of `BIT1`'s delay for a 1 and 43 or 47 for a 0, after a leader of 256 `$55` bytes and a `$7F` sync byte.
6. **Writing disk images back**, for every TRS-80, in their own formats.
