# Backlog: the BBC Micro

Status: **agreed 2026-11-16.** The Model B and Model A are done, from the machine to the debugger, the extension
and the Desktop ([BBC Micro](../BbcMicro.md)). Their ROMs (MOS 1.20, BASIC II, DNFS 1.20 and the SAA5050's
characters) are SDK sources. What is left is below.

## Later

- The B+ (64 KB and 128 KB, shadow RAM, the 1770 and DFS 2.x) and the Master 128 (the 65SC12, which needs a new 6502
  variant, MOS 3.20, sideways RAM, the CMOS clock).
- The Tube and a 6502 second processor; Econet; the speech chip (TMS5220 and its PHROM).
- The Electron, which shares `Retrocore.Machines.Acorn`.
- BASIC I as a `VERSION` build of `BbcBasic.asm`. The two versions differ in a few hundred bytes, and BASIC II added
  `OPENUP` and `OSCLI`.

## Known gaps

- The code DNFS copies into RAM (its NMI routines at `&0D00` and the Tube host code) shows as disassembly, not
  source.
- The BASIC thread's map of a line counts a colon inside a `*` command as a statement break, though OSCLI takes the
  whole rest of the line.
- RS-423 works with the MOS, but the host's serial line is not connected to it.
- The UEF reader ignores the base frequency (`&0113`) and phase (`&0115`) chunks.
- The TRS-80's partial 6845 could move onto the shared `Crtc6845`.
