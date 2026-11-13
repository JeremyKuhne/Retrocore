# Backlog: the Model III family's and the Model II's ROMs and software

The [Model III, 4, 4P, II, 12 and 16](../Trs80Model3And2.md) run from ROM dumps, and their hardware has been tested only
with ROMs the tests assemble. This is what remains for them to match the Model I.

**Status:** proposed; nothing here is approved yet.

## Stages

1. **Run the real ROMs.** With MAME's dumps in `RETROCORE_TRS80_ROMS`: the Model III to `Cass?` and `Memory Size?`, the
   Model 4 likewise, the 4P's boot ROM to its prompt, and the Model II's boot ROM to `INSERT DISKETTE`. Fix what the
   real ROMs show the emulation lacks, and add `Trs80Model3RomTests` and `Trs80Model2RomTests`, inconclusive without
   the dumps, as `Trs80RomTests` is.
2. **Boot their DOSes.** TRSDOS 1.3 and LDOS 5.3 on the Model III, TRSDOS 6 (LS-DOS) on the Model 4 and 4P, and
   TRSDOS-II on the Model II, from DMK, JV3 or IMD images; check the FD1793's wait states, the Model II's DMA and the
   keyboard codes against them.
3. **An oracle.** As `Trs80OracleTests` compares the Model I with MAME, compare the same keystrokes on MAME's
   `trs80m3`, `trs80m4` and `trs80m2`.
4. **ROM sources.** The Model III ROM in native source, sharing what it can with `Level2.asm` (most of its BASIC is
   Level II's), with the Model 4's revision as a conditional; the 4P's and Model II's boot ROMs; and the character
   generators. With them the machines run with nothing external, and Model III BASIC gets the BASIC thread.
5. **1500 baud cassettes**, which need the real ROM's timing to check.
6. **Writing disk images back**, for every TRS-80, in their own formats.
