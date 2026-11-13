# Business BASIC

Apple Business BASIC is the Apple III's BASIC. SOS loads it from a disk's `SOS.INTERP` file; its programs and
variables live in the switchable banks, which it reaches through extended addressing. The SDK has its source:
`BusinessBasic/BusinessBasic.asm`, in the Apple III's ROM sources, assembles byte-identically to Business BASIC
1.23's `SOS.INTERP`.

[`Apple3.md`](Apple3.md) covers the machine, and [`Sos.md`](Sos.md) the operating system.

## The source

The files follow Apple's Business BASIC 1.3 source, with Apple's file names and labels; the comments are our own.
`BusinessBasic.asm` includes them in Apple's order:

| Files | What they hold |
| --- | --- |
| `B3Invok.asm`, `ZpgEqus.asm` | SOS call numbers, the zero-page and system-page variables, the interpreter's header, buffers and dispatch tables. |
| `B3Resvb.asm` | The reserved words, their tokens, and the error messages. |
| `Initial.asm`, `B3MainC.asm`, `Extras.asm` | The cold start, the error handler, the prompt and the line editor, and small statements. |
| `SosStuf.asm` | The console's parameter lists and events, and the parameter list every file call shares. |
| `B3ListD.asm`, `B3GotoE.asm`, `B3InpuF.asm` | LIST, the statement fetcher, RUN, GOTO, GOSUB and the other control statements, and INPUT. |
| `B3EvalG.asm`, `StrUtils.asm` | The expression evaluator, and string utilities. |
| `B3MathK.asm`, `B3MathL.asm`, `B3FinpM.asm`, `B3Expon.asm`, `B3DmpyT.asm`, `LongInt.asm` | Arithmetic: reals, integers and long integers, number input and output, and the functions. |
| `B3FreeR.asm`, `B3DimnH.asm`, `B3UdefI.asm`, `StrngStuf.asm` | Memory and garbage collection, variables and arrays, user-defined functions, and the string functions. |
| `Invoke.asm`, `Invoke1.asm` | INVOKE and PERFORM: loading and calling invokable modules. |
| `B3Pru1.asm`, `B3Pru2.asm` | PRINT and PRINT USING. |
| `DiskStuf1.asm`, `DiskStuf2.asm`, `DisCmds.asm`, `FileStuf.asm`, `Catalog.asm` | Files: OPEN, READ#, WRITE#, LOAD, SAVE, the file commands and CATALOG. |
| `BasicEnd.asm` | The end of the interpreter. |

The file starts with SOS's interpreter header ("SOS NTRP", the load address and the length), loads at `$5200`
and starts at `INIT`.

## Versions

`VERSION` picks the release:

- `123`, the default, builds 1.23. It lacks 1.3's program selector support: the `SELECTOR`, `PROGPATH` and
  `SOSPATH` buffers, the routines that keep the program's prefix apart from SOS's, the `PROGPREFIX$` keyword and
  the calls to them. Storage the source reserves holds whatever was in memory when Apple built the file, spelled
  out as bytes, and the file runs 21 bytes past the length its header gives.
- `130` builds the 1.3 source as Apple printed it, loading at `$5000`. No 1.3 binary is known, so this build is
  unchecked.

`RUNTIME = 1` and `DEBUG = 1` select Apple's run-time and debugger variants. They assemble, but nothing exists to
check them against.

## Programs

The BASIC library (`Retrocore.Basic`) reads Business BASIC programs as the `business` dialect:

- **In memory.** A program runs from TXTTAB up to ARYTAB: Business BASIC keeps its arrays before its simple
  variables. Each line is a length byte (to the next line's), the line number, the tokens and a zero; a zero length
  ends the program. BASIC's pointers are two bytes in its zero page (`$1A00`) with an X-byte in `$1600` beside each
  high byte, and their pages stay from `$02` to `$81`, so the program runs on from one bank pair into the next. The
  library reads them as flat addresses, through the X-bytes.
- **In files.** A program file (SOS type `$09`) is two bytes BASIC ignores, which older versions set to the length
  and 1.23's SAVE leaves zero, then the program as it lies in memory.
- **As text.** Reserved words are one-byte tokens, or `$FF` and a token from a second list for the functions and
  words such as `THEN` and `TO`. The tokenizer is BASIC's `CRUNCH`: a word is reserved only with a separator (not a
  letter, digit or period) before and after it, so names may hold reserved words, as `PRINTER` does; `?` is PRINT
  and `!` is REM. A listing spaces words as BASIC's LIST does, and tokenizes back to the same bytes.

`--basic list file --dialect business` lists a program file, and `--basic tokenize file.business.bas out` writes
one.

**Workspace files** are named `.business.bas`, or start with `REM retrocore business`, and may use labels in place
of line numbers, each label on a line of its own (`loop:`). A `basic` launch on the Apple III takes such a file with
the Business BASIC disk in `disks`: SOS boots the disk, BASIC runs its HELLO (which must end at the prompt, as
Apple's does), and the program is written into memory and RUN. **Retrocore: Start Machine** asks for the disk.
**Retrocore: Open BASIC Program** edits the program in memory, as for the other BASICs; writing one while a program
runs puts BASIC back at its prompt first.

**In the editor** a `.business.bas` file is Business BASIC: words are highlighted only where BASIC takes them,
between separators, so `PRINTER` stays a name. Hover gives each word's help and a variable's type (`&` is a long
integer), and diagnostics, go to definition, references, completion, the outline and **Retrocore: Renumber BASIC
Program** work as they do for the other BASICs. Names are significant in full, dots included; the name after
`EXFN.` is a function in an invoked module, not a variable.

## Debugging

The interpreter maps where SOS loaded it, at `$5200` in the bank the `$2000-$9FFF` window shows while BASIC runs,
whenever memory there holds 1.23's bytes. A breakpoint can be set in its source before the disk boots, and stops
once the code is there: one on `GONE` in `B3ListD.asm` stops before every statement BASIC runs.

Once Business BASIC is in memory, the debugger shows a **BASIC** thread, as it does for AppleSoft:

- **The program in memory** opens as `Program.business.bas`. Breakpoints on its lines stop at a statement, with
  conditions and log messages in BASIC and hit counts.
- **Stepping** goes statement by statement, through colons; step over runs a GOSUB whole, and step out returns to
  the statement after it. Each GOSUB in progress is a frame below the current statement. Set Next Statement moves
  BASIC to another statement.
- **Stops:** the BASIC errors filter stops at an error with its message (`?UNDEF'D STATEMENT ERROR in 40 (code 8).`),
  and the stop filter at STOP, END, CONTROL-C and the program's end.
- **Variables:** the Variables scope lists the simple variables, the Arrays scope each array's elements, and the
  Loops scope each FOR in progress, with its limit and step; values can be set, a string going into string space as
  BASIC's LET puts it. Long integers are exact. The Program scope says where the program, the arrays, the simple
  variables and the strings are, as banked addresses such as `x81:$0201`.
- **Expressions** in watches, hovers, conditions and the Debug Console are Business BASIC: names of any length with
  `%`, `&` and `$`, `DIV` and `MOD`, and the functions that need no machine (`RND(`, `TIME$`, `EOF` and user
  functions are refused). Numbers print as BASIC prints them, to six digits; a real mixed with a long integer is a
  type mismatch, as in BASIC.

PERFORM and EXFN count as calls into machine code, as CALL does on the Apple II. While a program has `ON KBD`
on, the console takes every key, CONTROL-C too, for it; RUN turns it off.

## Testing

`BusinessBasicDialectTests` checks the reserved words against the source's tables, the tokenizer, and that every
program on the 1.23 disk lists and tokenizes back. `BusinessBasicSourceTests` pins both builds by digest, so no disk is needed. With Apple's Business BASIC 1.23
disk (in `RETROCORE_APPLE3_DISKS` or `%USERPROFILE%\Retrocore\apple3-disks`), it also compares the 1.23 build
byte for byte with the disk's `SOS.INTERP` and names the first difference. The documentation lint runs over the
sources as the editor does. With the disk, `tools/Test-Apple3Dap.mjs` boots it and stops at `GONE` as `HELLO`
runs, and `tools/Test-BusinessBasicDap.mjs` types a program at the prompt and debugs it on the BASIC thread.
