# Backlog: the Model III family's and the Model II's ROMs and software

The [Model III, 4, 4P, II, 12 and 16](../Trs80Model3And2.md) run the SDK's sources of every ROM they run that has a
known good dump, byte-identical to MAME's dumps, and boot to their prompts. This is what remains for them to match
the Model I. Hardware beyond that, such as the RS-232 ports, hard disks and the Model 16's 68000, is out of its
scope; the page's [What is not done yet](../Trs80Model3And2.md#what-is-not-done-yet) lists it.

**Status:** every stage is built; what each still lacks is listed with it: the Model II's oracle past TRSDOS's prompt,
and with LS-DOS; TRSDOS on the Model II writing a file; the PIO's bit-mode interrupt when its condition already holds;
Teledisk images, for TRSDOS-II 4.2; the Model II's keyboard codes against its keyboard's ROM; MAME's `cpu_fc86` Model II
boot ROM, which needs a good dump; and TRSDOS 1.3 writing.

## Stages

1. **Run the real ROMs.** Done for the first prompts: `Trs80Model3RomTests` boots the SDK's builds, the Model III and
   Model 4 through `Cass?` and `Memory Size?` to BASIC, the 4P to its drive-not-ready message, and the Model II to
   `INSERT DISKETTE`, every boot ROM version with a source among them. Writing the sources turned up two ports the
   emulation got wrong, now fixed: the Model III's RS-232 ports read `$FF`, as with no board, and the Model II's hard
   disk board's ports read zero, so versions 2 and 3 of its boot ROM boot from the floppy. The Model 4's real-time
   clock and function keys are tested against its ROM, MAME and the technical references (see
   [the Model III, 4 and 4P](../Trs80Model3And2.md#the-model-iii-4-and-4p)): F1, F2 and F3 give `$60`, `$1B` and
   `$08`, with or without shift, and match MAME. The clock was 30 Hz at both speeds; a Model 4 at 4 MHz now
   interrupts 60 times a second, as the references say (MAME, 0.264 and 0.289, keeps 30), and the interrupt
   latches only while its mask enables it. The Model 4 DOS comparisons with MAME 0.289 now run, with the images,
   and match.
2. **Boot their DOSes.** Done for the Model III family: TRSDOS 1.3 and LDOS 5.1.3 on the Model III, TRSDOS 6.0 and
   6.2 and LS-DOS 6.3 on the Model 4, and LS-DOS 6.3 on the 4P boot from DMK, JV3 and IMD images, take the date and
   list their directories (see [DOSes](../Trs80Model3And2.md#doses)). Booting them found that drive select's wait
   was only masked by INTRQ, so the ROM's NMI handler hung reading the status; INTRQ and DRQ now end it. Still open,
   the Model II:
   - **Its images.** MAME's `trs80m2` software list has the Model II's DOSes on 8-inch disks: TRSDOS 1.2, 2.0a and
     2.0b (IMD), TRSDOS-II 4.2 for the Model 16 (Teledisk) and LS-DOS 6.3.1 (DMK). The fixtures keep them in
     `trs80-disks` as `M2TRSDOS12.imd`, `M2TRSDOS20A.imd`, `M2TRSDOS20B.imd`, `M16TRSDOS42.td0` and
     `M2LSDOS631.dmk`, with the TRSDOS 2.0 set's calculator disk as `M2TDOSCALC.imd`. The
     [DOSes](../Trs80Model3And2.md#doses) table gives each one's source file and SHA-256.
   - **TRSDOS.** Done: TRSDOS 1.2, 2.0a and 2.0b boot, take the date and time and list their directories
     (`Trs80Model2RomTests.BootsItsDos`), and match MAME 0.264 and 0.289 at their prompt
     (`Trs80Model3OracleTests.Model2DosMatchesMame`). They had stopped at `BOOT ERROR DM 23`. The boot code the ROM
     loads first checks the machine (at `$1404`, `DIAG`), and its DMA test copies 80 bytes to video RAM, interrupting at
     the block's end with vector `$A8` and status affecting it, then looks for the flag set by the routine its table
     names at `$AC`. Zilog's DMA puts the cause in the vector's bits 1-2, 10 for the end of a block, but ours put 01, a
     match's, so the interrupt took the table's entry at `$AA`, and the test failed with its code `23`. Still open:
     - **The PIO's bit-mode interrupt.** In the same checks, ours interrupts as soon as port A's interrupt is enabled
       with the controller's INTRQ already high, where MAME's waits for INTRQ to rise. TRSDOS's routine does not keep
       A, so here TRSDOS then writes the controller `$01` (restore) where MAME's writes `$D0`; the check passes
       either way. Check the Z80 PIO's documentation for which is right.
     - **Writing.** TRSDOS on the Model II writing a file and its image saved back is untested.
     - **The keyboard codes** need checking against the Model II keyboard's ROM.
     - **The oracle past the prompt.** MAME's TRSDOS 1.2, in 0.264 and 0.289 alike, restores the drive and seeks again
       17 times in its first 30 seconds, where ours seeks once, so it asks for the date about 15 seconds later and is as
       slow to list its directory; the comparison stops at `TRSDOS READY` (see
       [Comparing with MAME](../Trs80Model3And2.md#comparing-with-mame)).
   - **LS-DOS 6.3.1 boots.** Done: from its DMK image it shows its welcome screen, takes the date and lists its
     directory (`Trs80Model2Tests.BootsLsDos`). Its boot had slowed: launched through the debug adapter at full speed,
     it reached the date prompt in 13 seconds at #32 and in 151 at `fa0b5b2`, so a launch watched for less looked blank;
     the welcome screen came up in 5 to 9 seconds throughout. By the date LS-DOS has the PIO's port A in bit control
     mode, taking the FD1791's INTRQ as an interrupt, so the PIO reads port A at every T-state, and port A's bit 1 asks
     the selected disk whether it is two-sided. #49 (`2901dbc`, found by bisecting) made `FloppyDisk.Sides` sort all the
     disk's tracks, about 5 KB allocated each time. #244 made `Sides` cheap for TRSDOS's boot, and a disk now keeps all
     its geometry as its tracks change (`Trs80Model2Tests.PioWatchingTheControllerDoesNotAllocate`). Still open:
     comparing it with MAME's `trs80m2`.
   - **Teledisk.** TRSDOS-II 4.2 is a Teledisk (`.td0`) image, which the media library does not read; see the
     [media backlog](Media.md).
3. **An oracle.** Done: `Trs80Model3OracleTests` compares video RAM with MAME's `trs80m3`, `trs80m4` and `trs80m2`
   after the same keystrokes. It covers BASIC on the Model III and 4, the five DOSes, from seven images, booting and
   listing their directories, versions 1, 2, 3 and 5 of the Model II's boot ROM asking for a diskette, and TRSDOS 1.2,
   2.0a and 2.0b on the Model II booting and taking the date and time (see
   [Comparing with MAME](../Trs80Model3And2.md#comparing-with-mame)). Still open: the Model II past TRSDOS's prompt,
   and with LS-DOS (see stage 2).
4. **ROM sources.** Done: `Model3.asm` (sharing Level II's BASIC through `Level2.asm`), `Model4PBoot.asm`,
   `Model2Boot.asm` and the character generators, with each build's `Keeps:` contracts checked by its own `MODEL`.
   The Model III's Level I ROM (`8040032`) is `Level1.asm` with `MODEL = 3`, and a Model III launches with it. Still
   open: MAME's `cpu_fc86` Model II boot ROM, version 4, which MAME lists with no good dump known; its source can't be
   written until there is one.
5. **1500 baud cassettes.** Done: `CSAVE` and `CLOAD` at 1500 baud on the Model III and 4, timed as the ROM's source
   writes and reads, and high-speed CAS images.
6. **Writing disk images back**, for every TRS-80, in their own formats. Done, with
   [saving media back to images](MediaPersistence.md): the Model I's and the Model III family's floppies save as JV3,
   DMK, IMD, DSK or JV1, and the Model II's as IMD, DMK or JV3. A DMK or IMD image keeps its layout, so the DMK and IMD
   DOS images save back byte for byte unchanged, and the JV3 ones to the same sectors (`Trs80DiskSaveTests`). LDOS
   5.1.3, TRSDOS 6.0 and 6.2 and LS-DOS 6.3 write a file that the saved image boots with and lists
   (`Trs80Model3RomTests.DosSavesAFile`). Still open: TRSDOS 1.3's `DUMP` stops with `ERROR 11` after reading its
   directory, before it writes a sector, and its `COPY` does not finish.
