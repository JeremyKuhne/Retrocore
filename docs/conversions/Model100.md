# Model 100: naming log

`src/Retrocore.Machines.Trs80Model100/Roms/`: the TRS-80 Model 100's 32K ROM in 27 modules and `Equates.asm`,
assembling byte for byte to the US Model 100's ROM and, with `MODEL = 102`, the Tandy 102's
(`Trs80Model100RomSourceTests`). Its labels are **named but not yet converted** to the maintained style, as
[MBASIC's](Mbasic.md) were ([ConvertingSources.md](../ConvertingSources.md)): each is a historical name where one is
known, not a current name with the old one in `Also:`. Unlike MBASIC's, the naming is not finished: this log records
the first stage, where each name came from, and what is left.

## Sources and citations

- **M100TR**: Tandy's
  [TRS-80 Model 100 Technical Reference Manual](https://archive.org/details/trs-80-model-100-technical-reference-manual)
  (1984), whose section 8, "ROM Subroutines", names 70 entry points and five variables with their addresses. Only
  the names and addresses come into the source, never the manual's text. The OCR of the archive's scan misreads
  some digits; each address was read against the code, and `CTON` is at $14A8 (the motor-on code, two bytes before
  `CTOFF`), not the OCR's $1448.
- **MBASIC**: the SDK's [MBASIC 5.21](../../src/Retrocore.Machines.Kaypro/Roms/Mbasic/Mbasic.asm), whose names are
  Microsoft's (from GW-BASIC's source, Level II's and memory; see [Mbasic.md](Mbasic.md)). The Model 100's BASIC is
  Microsoft's 8080 BASIC of the same family, much of its interpreter and string package the same code; a name taken
  from MBASIC is as good as MBASIC's own, and its doubts carry over.
- **MN2**: the statement and function handlers, named for their keyword (`ST_FOR`, `FN_LEFT`), as MBASIC's decision
  MN2 names them.
- **SDK**: names made for this source, in Microsoft's style, where neither source has one.

## How it was done

1. **Tracing the code.** The SDK's disassembler, with hints, found the code: RST 1 (SYNCHR) and RST 7 (a hook) each
   take the byte after them; the tables of routines (FUNDSP, STMDSP, the math dispatch, DEVDSP, TEXT's and TELCOM's
   keys, the screen's control characters and escape sequences, INLIN's keys) and the ROM's directory give entry
   points; so do Tandy's entries, and an LXI that a PUSH follows, which is a return address, and an LXI H that sets
   the error handler at $F652. A few runs of code reached in no other way were given as entries by hand, each after
   an unconditional jump or return. What is left untraced is mostly data (text, tables, the RAM image and the font),
   with a few runs of code the trace does not reach yet, written as bytes.
2. **Naming.** Tandy's names first, then the handlers', then Microsoft's interpreter core by hand (NEWSTT, GONE,
   MAIN, ERROR, CONSTP, STPEND, ENDCON, DIRIS and SNGFOR, read against MBASIC's code), then the rest of Microsoft's
   names by aligning the two programs' instruction streams: a diff of MBASIC's instructions against the ROM's,
   operands left out and the RSTs counted as the calls they stand for, gives blocks of the same code, and an MBASIC
   label in a block names the ROM's instruction it lines up with. Names were taken only in the interpreter
   ($0400-$12FF), the string package ($2700-$2B5F) and LINE INPUT #'s code ($4F00-$504F), from blocks of at least
   four instructions there, and six in LINE INPUT #'s; elsewhere blocks matched by chance (a `ST_WHILE` in a BASIC
   without WHILE, and a `CSKPCM`, CLEAR's in MBASIC, on CSAVE's `,A`). Within the ranges, the alignment also put
   `SNGFOR` on the double-precision FOR; it is on the single-precision one. `NTOERR` lined up with the Model 100's ON COM, KEY and
   TIME$ test; it is on the ON n dispatch that test falls through to, which is MBASIC's NTOERR. Variables took the name of MBASIC's
   operand at the same place, where at least two blocks and three quarters of them agree.
3. **Writing the source.** An emitter wrote the modules from the traced code, the names and both ROMs: the tables as
   entries (`KEYWORD`, `.word`, `DISPATCH`), each skip byte (an LXI or MVI whose operand is another entry) as a
   `.byte` saying what it skips, SYNCHR's byte with its character, and each difference between the ROMs as an
   `.if MODEL = 100` block. Both models were checked byte for byte at every step. From here the source is
   maintained by hand.

## Decisions

The IDs are M100.

- M100-1. Tandy's name wins where an address has a documented name and another: `CLS` is also the CLS statement's
  handler, `MENU` MENU's and `PRTLCD` LCOPY's, so there is no `ST_CLS`, `ST_MENU` or `ST_LCOPY`.
- M100-2. A label the naming has not reached keeps the disassembler's name, `L_` and its address for code and `D_`
  for data and RAM, rather than a made-up name: the modules' naming, which follows, replaces them, and an address in
  the name is a clear sign of what is left.
- M100-3. The restarts are named for what BASIC uses them as, and the routines they jump to keep Microsoft's names:
  `CHRGET` at $0010 jumps to `CHRGTR`, `GETYPE` at $0028 to `GETYPR`. The 80C85's interrupt entries are `TRAP`,
  `RST55`, `RST65` and `RST75`; RST 7's is `RST38`, and the hook dispatcher it jumps to `HOOK`. `GONE3`, the `RZ`
  after GONE, is Level II's name (Level2.asm), which MBASIC lacks.
- M100-4. The error entries are named for their two letters, as Microsoft's are (`SNERR`, `DV0ERR` for `/0`), and the
  Model 100's file errors from code 50 (`IEERR` to `CFERR`) by the same rule. Code 20 is `RWERR`, for the Model
  100's RW (RESUME without error), where MBASIC has `REERR`.
- M100-5. No names from MBASIC's math package: the Model 100's numbers are BCD, its math package other code, and the
  alignment found nothing there. The floating accumulator's bytes keep their `D_` names. The math package does use
  some of the interpreter's scratch variables, such as `TEMP3` and `TEMP8`, under those names.
- M100-6. One source for both machines, `MODEL` 100 or 102. 355 of the Tandy 102's bytes differ; counting differences
  with at most three equal bytes between them as one, and widening each to whole instructions in both ROMs, they make
  51 places, 30 of them in the font ($770B-$7D32), and places within 24 bytes of each other share a block, which
  makes 24 `.if` blocks. The font's glyphs and the other binary tables are written in hex, never as text.
- M100-7. The modules follow the ROM's subjects, at routine boundaries both ROMs share: Microsoft's BASIC in
  MBASIC's order, then the Model 100's own code by what it drives. The boundaries are a first cut, to be refined
  as each module is named.

## Names that are not Microsoft's or Tandy's

| Names | What |
| --- | --- |
| `RESET`, `TRAP`, `GETYPE`, `RST55`, `RST65`, `RST38`, `RST75`, `HOOK` | The restarts and interrupts (M100-3). |
| `DECDSP`, `RAMIMG`, `ERRMSG` | The interpreter's tables, beside `FUNDSP`, `RESLST`, `STMDSP`, `OPTAB`, `DBLDSP`, `SNGDSP`, `INTDSP` and `ERRTAB`, which are Microsoft's names for the same tables in MBASIC. `DECDSP` is the conversions before `DBLDSP`; each type has six routines, + - * / ^ and compare. |
| `IEERR`, `BNERR`, `FFERR`, `AOERR`, `EFERR`, `NMERR`, `DSERR`, `FLERR`, `CFERR` | The file errors' entries (M100-4). |
| `LCDCTL`, `ESCTAB`, `INLCTL`, `DEVTAB`, `DEVDSP`, `LCDDEV` to `RAMDEV`, `TELCMD`, `TRMFNK`, `ADRCMD`, `TXTCTL`, `TXTINL`, `ROMDIR` | The Model 100's own tables: the screen's control characters and escape sequences, INLIN's keys, the devices' names, the devices' driver tables and each driver's own (LCD:, CRT: and LPT: have three routines, the others five), TELCOM's commands and terminal keys, ADDRSS's and SCHEDL's commands, TEXT's keys and the ROM's directory entries. |
| `BASIC`, `TEXT`, `TELCOM`, `ADDRSS`, `SCHEDL` | The ROM's programs, named as the menu shows them. |
| `COLD` | The cold start. |
| `DIRTBL`, `DOSTRT`, `COSTRT`, `PRGNAM` | The file directory, the starts of the DO and CO files, and the menu's file name: what is typed at Select:, each name it formats for the screen, the name CHKDC looks for, and so the program the menu runs. |
| `STKTOP` | Level II's name (Level2.asm) for the bottom of string space, which the stack sits below: MENU sets it from `MEMSIZ`, and CLEAR, the stack and string space are bounded by it. |

- M100-8. The five bytes at $770B, first named `KEYTAB`, are a command the ROM sends to the device on ports
  $80-$83, not the keyboard's tables, which follow at $7BF1; neither has a name yet.
- M100-9. `BEGLCD` names the screen's memory at $FE00. The manual's `ENDLCD`, $FF40, the byte after the screen, is not a
  label: the ROM keeps the RS-232 port's state there, and the name would read wrong at those uses.

## Open questions

- Most of the ROM is not named yet: the Model 100's own code, from the device drivers to TEXT and TELCOM, and the
  math package. That is the next stage, module by module, with every routine documented.
- Microsoft's names taken from blocks of four or five instructions are the likeliest to be wrong. They are in the
  interpreter and the string package, where the code follows MBASIC's closely; the modules' naming checks each.
- The Technical Reference names only entry points. Covington's System ROM Map, which names much more of the ROM, was
  not found; the ROM's own names for most of its routines are unknown.
