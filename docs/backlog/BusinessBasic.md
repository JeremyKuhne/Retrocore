# Backlog: Business BASIC

Business BASIC 1.23 debugs as AppleSoft does: its source, the BASIC thread, variables, editing, the launch and
language support are built and reviewed, and [BusinessBasic.md](../BusinessBasic.md) describes them. What is left:

- Business BASIC 1.1 as a conditional build, and a 1.3 build should a binary turn up. Apple's 1.3 source
  (`docs\apple3\Apple3_Business_BASIC_1.3.pdf`) is the base; 1.1's `SOS.INTERP` is on `Apple3BusBasic.dsk` (25,600
  bytes, loading at `$5500`), and no 1.3 binary is online (Asimov and apple3.org have 1.0, 1.1 and 1.23).
- Business BASIC's invokable modules (`.INV` files), such as `BGRAF.INV`.
- DEF FN functions in the Variables view and in expressions, and the `!` arrays (type `$C0`).
- Programs as SOS files on disk images, once the media library writes them ([Media.md](Media.md)).
