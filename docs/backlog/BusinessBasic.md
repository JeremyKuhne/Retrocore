# Backlog: debugging Business BASIC

Status: **agreed 2026-11-13** ("Implement Business BASIC debugging"). Stages 1-7 are built; stage 7 awaits review.

Apple Business BASIC is the Apple III's BASIC. SOS loads it from `SOS.INTERP`, and its programs and variables live
in the switchable banks, reached through extended addressing. The goal is what AppleSoft and
Integer BASIC have on the Apple II ([BasicDebugging.md](BasicDebugging.md)):

- the BASIC thread, with statement breakpoints, stepping, the GOSUB stack and error stops;
- BASIC variables;
- the machine-program editor, workspace `.bas` files and the `basic` launch;
- language support.

Under that sits an SDK source for the interpreter, as SOS has: Business BASIC debugs at its source, and its symbols
(`NEWSTT`, `GONE`, `ERROR`) are the hooks.

## What there is

**Binaries** (`%USERPROFILE%\Retrocore\apple3-disks`):

| Disk | `SOS.INTERP` | Loads at |
| --- | --- | --- |
| `Apple3BusBasic1.23.dsk` | Business BASIC 1.23, "Copyright Apple Computer, 1980-83", 25,963 bytes | `$5200` |
| `Apple3BusBasic.dsk` (unlabeled) | Business BASIC 1.1, "(C) Apple Computer 1980, 1981", 25,600 bytes | `$5500` |

**Source:** `docs\apple3\Apple3_Business_BASIC_1.3.pdf`, Apple's 1983 source of 1.3 (220 pages, with a text layer).
No 1.3 binary is online: Asimov and apple3.org have 1.0, 1.1 and 1.23.

**How it runs**, from the listing, checked in both binaries:

- It is Microsoft BASIC underneath. `NEWSTT` fetches statements and `GONE` starts each one, as in AppleSoft, and
  `GONE`'s code is nearly the same in 1.1 (`$6A0E`), 1.23 (`$683C`) and the 1.3 listing.
- Its pointers are AppleSoft's (`TXTTAB`, `VARTAB`, `ARYTAB`, `STREND`, `FRETOP`, `MEMSIZ`, `CURLIN`, `OLDTXT`,
  `DATPTR`), each with an X-byte beside it naming its bank. A pointer's high byte runs from `$02` to `$81`; past
  that, the X-byte steps up and the high byte drops by `$80`. So a program sees one flat space, 32K per X-byte step.
- A line is a one-byte link, a two-byte line number and tokens ending in zero (AppleSoft's link is two bytes).

## Stages

Each ends in a review.

### 1. The interpreter's source

- `Retrocore.Machines.Apple3/Roms/BusinessBasic/`: the listing's files as native sources, building 1.23's
  `SOS.INTERP` byte-identically. Where 1.23 differs from the 1.3 listing, the source follows 1.23's bytes and says so,
  as the SOS kernel's does where the listing is damaged. Labels are Apple's; comments are ours.
- A source test pins the bytes and checks them against the disk when present; the doc lint covers the files.
- 1.1 is not a goal; see Later.

Built 2026-11-13: `Roms/BusinessBasic/` (32 files and `BusinessBasic.asm`), with `BusinessBasicSourceTests`; the
user guide is [BusinessBasic.md](../BusinessBasic.md).

- **1.23 against the 1.3 listing:** the code is 1.3's but for program selector support (the `SELECTOR`,
  `PROGPATH` and `SOSPATH` buffers, the prefix routines, `PROGPREFIX$` and their calls), the sign-on's version,
  leftover bytes in reserved storage, and 21 bytes past the header's length. `VERSION = 130` builds the listing as
  printed, pinned by digest but unchecked.
- **The listing's text:** the PDF's reformatting stretched the spaces in four error messages and in the sign-on;
  the source follows the bytes.
- **Apple's code, documented as found:** among others, engineering-notation PRINT USING fills one place;
  `SUB$` into an empty string with a one-character result writes 256 spaces; DEF FN with an integer argument
  overwrites two bytes; long-integer comparison is wrong when the top bytes differ by $80 or more, and negating
  -2^56 overflows; a program file whose length's low byte is $00 or $01 loads its arrays 256 bytes high; CHAIN's
  room check ignores the variables it keeps; FLUSH always flushes every file. RND is a Lehmer generator, not
  Microsoft's, and "MICROSOFT!" sits hidden after the sine constants.

### 2. The interpreter in the debugger

- The debugger maps the interpreter's source where SOS loaded it, as it maps the kernel.
- `Test-Apple3Dap.mjs` stops at a breakpoint in the source once Business BASIC is at its prompt.

Built 2026-11-13: the debug host ships `BusinessBasic/`, and `Apple3DebugTarget` maps the 1.23 build
(`Apple3SdkModules.AssembleBusinessBasic`) wherever memory holds its bytes, as the kernel is mapped. No bank needs
naming: while BASIC runs, the window shows its bank. `Test-Apple3Dap.mjs` boots the 1.23 disk and stops at `GONE`
in `B3ListD.asm` as `HELLO` runs, with the breakpoint set before boot; it skips without the disk, as in CI.

### 3. The dialect and banked memory

- `BusinessBasicDialect` in `Retrocore.Basic`: its tokens (from the source's tables), lines, numbers and the
  pointer layout.
- BASIC memory learns banked pointers. A dialect can say each pointer has an X-byte, and `IBasicMemory` then reads
  the flat space (an address past `$FFFF` is a later bank step); `TargetBasicMemory` turns it into extended
  addresses on the Apple III. The Apple II and Model I dialects are unchanged.
- Listing and reading the program in memory, the `--basic` command line, and tests on memory images.

Built 2026-11-13:

- **`BusinessBasicDialect`** (`business`): both reserved word lists, pinned to the source's tables; `CRUNCH`'s
  tokenizer for program lines (a line number's last digit before a word typed without a space reads as a
  separator, where BASIC would not tokenize it); a LIST-style detokenizer; program files, whose two leading bytes
  hold the length in older files and zeros from 1.23's SAVE. Writing a program into memory waits for stage 6.
- **Banked memory:** `IBasicMemory.ReadFar`/`WriteFar` and `IDebugTarget.PeekFar`/`PokeFar` read through an
  X-byte; the dialect reads its pointers as flat addresses, `$10000` up for banked memory, so lines and
  statements keep one address each. The other dialects are unchanged.
- **Command line:** `--basic list file --dialect business`.
- **Tests:** `BusinessBasicDialectTests`, including every program on the 1.23 disk listing and tokenizing back,
  and `Apple3SosTests` reading the typed program from a booted machine's memory.

### 4. The BASIC thread

- `Apple3DebugTarget` gets the BASIC hooks from the source's symbols: statement start, current line, text pointer,
  the FOR and GOSUB stack, errors (with `ON ERR`), STOP, END and CONTROL-C, RUN and CONT.
- Statement breakpoints, stepping in, over and out, the GOSUB frames, set next statement, and error stops.
- `tools/Test-BusinessBasicDap.mjs`, which needs the 1.23 disk and skips without it, as the SOS boot does.

Built 2026-11-13:

- **`Apple3DebugTarget.BusinessBasic.cs`:** the hooks, from the source's symbols, while GONE's bytes are in the bank
  `BASICBNK` names (SOS shows its drivers' banks while they run, as the console's while BASIC waits for a key).
  Statements start at GONE, but for an empty one; GOSUB entries are read off BASIC's stack in page `$1B`, from the
  stack pointer at GONE itself, where `REMSTK` is still the subroutine's after RETURN; errors read their message from
  ERRTAB; STOP, END and CONTROL-C all stop at `STOP2`. `InRom` covers the interpreter and SOS's kernel.
- **Session:** three dialect hooks (`ProgramBounds`, `Text`, `MemoryImage`) replace the places that read program
  bytes at 16-bit addresses; PERFORM and EXFN count as machine calls; at a STOP stop an END statement is named END.
  Business BASIC gets only the Program scope, and expressions say its variables cannot be read yet.
- **A keyboard fix:** the Apple III bus now sends a control character as its letter with CONTROL held, as the
  keyboard does, so CONTROL-C (from the panel too) reaches SOS's console as the attention key.
- **Tests:** `tools/Test-BusinessBasicDap.mjs` (in CI, skipping without the disk): a typed program, a breakpoint
  in a GOSUB, stepping, Set Next Statement, the Program scope, an error, STOP and CONTROL-C;
  `Apple3BusTests.ControlCharactersHoldControl`.

### 5. Variables

- Business BASIC's types: real, integer (`%`), long integer (`&`) and string (`$`), simple and in arrays, read and
  written, as the AppleSoft variables view does.

Built 2026-11-13:

- **`BasicVariables.Business.cs`:** simple variables, arrays, values (four-byte reals, integers and long integers
  high byte first, strings as distances below HIMEM), writes (a string into string space below FRETOP with its type
  and back offset, the string it replaces marked free), new variables at STREND, and FOR loops off BASIC's stack
  (the variable as a 16-bit offset from its table, the step unpacked with its sign, the limit packed).
- **`BusinessBasicExpression`:** Business BASIC's expressions over text, as Integer BASIC's are; `BasicValue.Long`
  and `BasicVariableKind.Long` keep long integers exact. Six-digit formatting, checked against BASIC's own PRINT.
- **Session:** the usual Variables, Arrays, Loops and Program scopes; "long integer" as a type.
- **Tests:** `Apple3SosTests.BusinessBasicVariablesReadAndWrite` (each kind, an array, expressions, PRINT's format,
  a string written that BASIC then prints); `Test-BusinessBasicDap.mjs` with variables, a loop, expressions,
  setting a variable and a condition.
- **Not done:** DEF FN functions are not listed or evaluated, and the `!` arrays (type $C0) are skipped.

### 6. Editing, files and the launch

- The machine-program editor with import and export.
- Workspace files: a `.business.bas` name or a first-line pragma, as Integer BASIC files have.
- The `basic` launch boots the 1.23 disk, waits for the prompt and types the program in.

Built 2026-11-13:

- **Writing:** `BusinessBasicDialect.Write` puts the program at TXTTAB and clears as typing a line does (CLEARL,
  RESTORE, CLEARONS, no CONT); `Apple3DebugTarget.EnterBasicPrompt` returns a running BASIC to MAIN.
- **The launch:** `IDebugTarget` gained `HasBasicSource`, `BasicBootSeconds` and `PressesReturnForPrompt`, and
  `ReachPrompt` looks for BASIC's hooks as it boots, so a BASIC loaded from disk works; the Apple III waits two
  minutes and presses nothing. The extension's Apple III takes `business` files and asks for the Business BASIC disk
  (`Machine.basicDisk`).
- **A fix for every dialect:** `THEN GOTO label` (and `THEN GOSUB`) never took the label, as the word after THEN was
  skipped when it was no label; `BasicLabelTests.ThenGotoTakesALabel`.
- **Found:** RUN turns ON KBD off (`STXTPT` runs `CLEARONS`), so CONTROL-C needed only stage 4's keyboard fix.
- **Tests:** `BusinessBasicDialectTests.WritesAProgramAcrossBanks`; `Test-BusinessBasicDap.mjs` writes a program
  while one runs and launches a workspace file with a label; the extension's start flow and machine tests.

### 7. Language support

- A grammar, diagnostics, navigation, hover with keyword help, completion and renumber, as Level II has.

Built 2026-11-13:

- **The language:** `retrocore-business` for `.business.bas` files, with a grammar generated from the dialect's
  two word lists that highlights a word only between separators, as CRUNCH takes it; the language server, the
  breakpoint languages and the `retrocore.basic.dialect` setting know it, and an Apple III session makes a plain
  `.bas` file Business BASIC.
- **Analysis:** the line scanner reads `$FF` words from the second list, names whole with dots and `&`, the name after
  `EXFN.` as no variable, and gives no "BASIC reads X as Y" warning, since no word hides inside a name. Hover names a
  long integer, and keyword help covers all 116 words (`b` in `Keywords.txt`).
- **Tests:** `BasicSourceTests.BusinessBasicNamesAndWords`, `BusinessBasicRenumbers` and the `business` row of
  `EveryKeywordHasHelp`; the extension's grammar test and its editor test of a `.business.bas` file.

## Later

- Business BASIC 1.1 as a conditional build, and a 1.3 build should a binary turn up.
- Business BASIC's invokable modules (`.INV` files), such as `BGRAF.INV`.
- Programs as SOS files on disk images, once the media library writes them ([Media.md](Media.md)).

## Decisions

Agreed 2026-11-13:

- Stage 1 builds the interpreter's source, rather than finding 1.23's hook addresses in the binary.
- Workspace files are named `.business.bas`, or say `business` in a first-line pragma.
