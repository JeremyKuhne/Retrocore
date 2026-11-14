# Apple Pascal

Retrocore runs Apple's Pascal on both of its Apple machines and debugs the programs it runs:

- **Apple III Pascal** 1.0, 1.1 and 1.2 on the Apple III;
- **Apple Pascal** 1.0, 1.1 and 1.2 on a 64K Apple II Plus, with the language card, and 1.1 and 1.2 on the IIe.

Apple Pascal 1.3 is not checked, as no image of it was at hand. On 1.0, a listing (`$L`) leaves the Compiler's code
file open, so compile without one there; and R(un) runs no code C(ompile) wrote, so X(ecute) the code file by name.

Both are UCSD Pascal II.1. The compiler turns a program into p-code, the instruction set of a stack machine, and a
6502 interpreter runs it: `SOS.INTERP` on the Apple III, and `SYSTEM.APPLE` in the language card on the Apple II.
The operating system, `SYSTEM.PASCAL`, is p-code too.

## Running it

Boot the first disk. On the Apple III put the second in `.D2` for the Editor and Compiler; on the Apple II, APPLE1
boots and APPLE2 in drive 2 has the Compiler.

```json
{
    "type": "retrocore",
    "request": "launch",
    "name": "Apple III Pascal",
    "machine": "apple3",
    "disks": ["${workspaceFolder}/disks/Apple3Pascal1.1Disk1.dsk", "${workspaceFolder}/disks/Apple3Pascal1.1Disk2.dsk"]
}
```

### Apple III Pascal 1.2

Apple shipped 1.2 as two update disks, whose files go onto 1.1's disks. Its system is larger than 1.1's, so the boot
disk keeps SOS, the interpreter and the system, and 1.1's Filer and Library, which 1.2 keeps, move to the second
disk with the Editor and Compiler. `--pascal sos` builds both disks:

```text
Retrocore.Debug --pascal sos Pascal1.2Disk1.dsk PASCAL1 --boot Apple3Pascal1.1Disk1.dsk
    --from Apple3Pascal1.1Disk1.dsk SOS.KERNEL SOS.DRIVER
    --from Apple3Pascal1.2UpdateDisk1.dsk SOS.INTERP SYSTEM.PASCAL
    --from Apple3Pascal1.1Disk1.dsk SYSTEM.MISCINFO
Retrocore.Debug --pascal sos Pascal1.2Disk2.dsk PASCAL2
    --from Apple3Pascal1.1Disk1.dsk SYSTEM.FILER SYSTEM.LIBRARY
    --from Apple3Pascal1.2UpdateDisk1.dsk SYSTEM.EDITOR SYSTEM.SYNTAX
    --from Apple3Pascal1.2UpdateDisk2.dsk SYSTEM.COMPILER
```

(each command on one line). 1.2's Editor asks `Edit what file?` where 1.1's says there is no workfile: RETURN starts
an empty one.

### Editing and saving

Disks load write-protected. For the Editor and Compiler to write, take the protection off in the **Retro Devices**
view (**Allow Writes** on the drive). What the machine writes stays in memory until you save the disk: **Save to
Its Image** on the drive, or **Save Disk As...** to keep the original.
CONTROL-C, which ends an insertion in the Editor, is the panel's Ctrl+C.

Paste a program into the Editor whole: pasted keys go in at a typist's pace, with a pause after each line, so the
Editor's type-ahead doesn't overflow as it scrolls.

## Debugging

Once the interpreter is running, the debugger finds it in memory, and a **Pascal** thread appears beside the CPU's.

### Your program's source

Compile the program with a listing, and its source debugs by line:

1. Keep a copy of the source on the host, such as `hello.pas` or `HELLO.TEXT` (the extension opens `.pas`,
   `.pascal` and `.text` files as Apple Pascal), with the same lines as the program the machine compiles.
   `--pascal extract` copies a `.TEXT` file out of a disk image as plain text.
2. Compile it with a listing named after it: `HELLO.LST.TEXT` for `hello.pas` or `HELLO.TEXT`, at the Compiler's
   `Listing file` prompt or with `(*$L HELLO.LST.TEXT*)` at the top of the program. The debugger reads the listing
   from a disk in a drive, again whenever the disk changes, or from beside the source on the host.
3. Set breakpoints in the source's gutter. A line binds to the first p-code of its statement, as the listing places
   it; a line that only declares, or that no longer matches the listing, stays unverified and says why.

Then the Pascal thread's frames show their source line and procedure name, such as `SHOW (HELLO.2+$0005)`, and
**Step Over** and **Step Into** go by line, stopping again when a loop comes back to the line. Without a source on
the host, a frame whose segment a listing on a disk compiles still names its procedure and line.

A listing places each line's code where the compiler was when it read the line, so code that needs the next line's
first word to finish, such as a call at the end of a line, counts as the next line's.

- **Call stack.** The Pascal thread's frames are the procedures running, read from the p-machine's mark stack:
  the one about to run a p-code first, then each caller, down to the system's outer block. Each is named by its
  segment and procedure and its offset from the procedure's entry, as the compiler's listing counts, such as
  `HELLO.2+$0005: SLDC 7`. The top frame shows the p-code about to run.
- **Segment names** come from the code files on the disks in the drives: a segment in memory ends with the same
  bytes as its code file's segment. A segment no disk has is named by number, such as `1.2`.
- **Variables.** Each frame has **Locals**, its parameters and local variables, and **Globals**, the program's.
  Where a listing declares them they have their names and their values as their types read: integers, characters,
  booleans and strings; hovering a name in a Pascal frame reads it too. Other words are numbered as `LDL` numbers
  them. The top frame also shows the p-machine's registers: IPC, MP, BASE, JTAB and SEG. On the Apple III a register
  reaching another bank shows its X-byte, such as `x86:$4A3A`.
- **Stepping** without a listing goes by p-code: **Step Into** stops at the next p-code wherever it is, **Step Over**
  at the next one in the same procedure or a caller, and **Step Out** at the first one back in the caller. **Pause**
  stops at the next p-code. The Disassembly view's steps always go by p-code.

### Pascal breakpoints

A function breakpoint (**+** in the Breakpoints view) named `pascal` and a procedure stops before the procedure's
p-code at an offset, on the Pascal thread:

| Name | Stops |
| --- | --- |
| `pascal HELLO.2` | at the entry of procedure 2 of the segment `HELLO` |
| `pascal HELLO.2+$0D` | 13 bytes into it, as `+13` does |
| `pascal 1.2` | at the entry of procedure 2 of segment 1, whatever its name |

A compiler listing gives each line's segment number, procedure, and offset: in

```text
     9   1    1:2    13 SHOW(I)
```

line 9 is in segment 1, procedure 1, at offset 13, so `pascal 1.1+13` stops at `SHOW(I)`. Ask for a listing at the
Compiler's `Listing file` prompt, or with `(*$L name*)` at the top of the program.

Conditions, hit counts and log messages work as on any breakpoint, with the CPU's expressions.

## Disks and code files

`Retrocore.Debug --pascal` reads Pascal and SOS volumes from `.dsk`, `.po` or `.woz` images:

- `--pascal catalog disk` lists the files;
- `--pascal extract disk NAME output` copies one out, a text file as plain text (`--raw` keeps Pascal's format);
- `--pascal segments code` lists a code file's segments and procedures;
- `--pascal disassemble code [SEGMENT[.PROCEDURE]]` lists its p-code, and its assembled procedures as 6502 code;
- `--pascal disassemble code output.asm [--library library] [--listing listing] [--hints hints.json]` writes the
  whole code file as source that assembles back to the same bytes, and checks it does (below); `--pascal assemble source.asm output.code` assembles such a source;
- `--pascal sos output NAME [--boot disk] --from disk FILE...` builds a SOS volume from other SOS disks' files, as
  above.
- `--pascal decompile code [--library library] [--listing listing] [--hints hints.json] [output.text]` decompiles a
  program back to Pascal (below);
- `--pascal compile source.text APPLE1.dsk APPLE2.dsk output.code [listing.text]` compiles a source with Apple
  Pascal's own Compiler, on an emulated Apple II, and writes the listing the source asks for with
  `(*$L APPLE1:NAME.TEXT*)`; a Pascal file's name is at most 15 letters, so `HIL.LST.TEXT`, not `HILBERT.LST.TEXT`;
- `--pascal compare code code` compares two code files' segments, and says where their code first differs.

A code file is a file's path, or a disk and the file's name: `--pascal disassemble APPLE3.dsk HILBERT.CODE HILBERT.2`.

The libraries behind them are `PascalVolume`, `PascalCodeFile`, `PascalTextFile` and `SosVolumeBuilder` in
`Retrocore.Media`, and the
p-code and its disassembler in `Retrocore.Pascal`.

## Decompiling

`--pascal decompile` turns a program's code file back into Pascal, written so that Apple Pascal's Compiler compiles
it to the same p-code:

```text
Retrocore.Debug --pascal decompile APPLE3.dsk HILBERT.CODE HILBERT.TEXT
Retrocore.Debug --pascal compile HILBERT.TEXT APPLE1.dsk APPLE2.dsk HILBERT.CODE
Retrocore.Debug --pascal compare APPLE3.dsk HILBERT.CODE HILBERT.CODE
```

The Compiler translates a statement at a time, without optimizing, so each IF, WHILE, REPEAT, FOR, CASE and WITH
leaves its own pattern of jumps, and the stack holds each expression whole. What the code does not keep is made up:

- **Names** come from offsets: `G3` for the program's variable at word 3, `A3` for a level-1 procedure's, `B3` a
  level-2 one's, `PROC2` and `FUNC2` for procedure 2, `T1` for a type, `F4` for a record's field at word 4; or from a
  listing and hints (below).
- **Types** are inferred from how the code uses each word: arithmetic makes an integer, character I/O and a string's
  elements a character, AND, OR and NOT a boolean; a range check gives a subrange, `IXA` an array, `INC` a record,
  `SAS` a string's length. Where a use disagrees with the type chosen, `ORD`, `CHR`, `ODD`, `SUCC` and `PRED`, which
  compile to nothing, convert it; a word used both as an integer and a pointer (or as bytes), or a pointer a number
  is stored in (FORMATTER keeps RWTS's address so), is a variant record.
- **Constants** are written in place, but for a negative one the program declared: the Compiler loads `CONST M = -1`
  as `LDCI 1, NGI` and `-1` written in place as `SLDC 1, NGI`, so the first is a `CONST` (`NEG1 = -1`).
- **Declarations** are one variable to a line, in the order of their offsets, as the Compiler allocates them, with
  padding where the code never uses a word; files are grouped so they are opened in the same order.
- **Procedures** nest as the order of their code shows, and one numbered before another whose code comes first is
  declared FORWARD.
- **Assembled procedures** are declared `EXTERNAL`, where their number puts them. Their code says nothing of their
  parameters, so their first call does: two zero words on top of the stack are a function's room for its result
  (`FUNCTION FUNC2(A4: INTEGER; A3: INTEGER): BOOLEAN; EXTERNAL;` in FORMATTER), and the words below them its
  parameters. A segment the Linker linked them into is marked for the 6502, not p-code; it decompiles all the same.
- **Options**: `(*$I-*)`, `(*$R-*)`, `(*$G+*)` and `(*$V-*)` are written where the code shows unchecked I/O, unchecked
  indexes, GOTO, or a string passed to a VAR string of another length.

With the Compiler's listing of the program (`--listing`), procedures, parameters and variables are named as the
source named them; with HILBERT's, the decompiled source reads as the original. Hints (`--hints`, the JSON file
[`--pascal disassemble`](#names) takes) name them too, keyed `SEGMENT.N` for procedure N and `SEGMENT.N@WORD` for a
variable, and win over the listing; a hint's comment for `SEGMENT.N` goes above the procedure's heading. A name must
leave the code as it is, so one is refused, with a warning, where it is a reserved or predeclared word (FORMATTER's
`IoResult` would hide the `IORESULT` its code calls), a library unit's, or the same in its first eight letters, all
the Compiler reads, as another the procedure reaches or is reached from; and the program's and a segment
procedure's names must be their segments'.

A unit's procedures are named from its interface text in the library (by default the disk's `SYSTEM.LIBRARY`, or
`--library disk NAME`); the source `USES` them as the program did. Where some code cannot be decompiled, the
procedure says so in a comment, the command lists it as a warning, and exits with 1.

Apple Pascal 1.1's sample programs (HILBERT, TREE, BALANCED, CROSSREF, DISKIO, GRAFDEMO, GRAFCHARS, SPIRODEMO,
LINEFEED) and the BINDER utility decompile to sources that compile to the same code, but for the byte the Compiler
skips to align a constant or case table, which holds whatever its buffer had and which `compare` ignores. Not
decompiled: programs compiled as part of the system (`(*$U-*)`), such as SOROCGOTO, and the system's own programs;
units of a program's own (they need the Linker); a unit's variables; and `SCAN`, `IDSEARCH` and `TREESEARCH`.
FORMATTER's source compiles to the same p-code, but its assembled procedure needs the Assembler and the Linker to
make the same code file. A code file from another version's Compiler decompiles, but
compiles the same only with that Compiler.

## P-code source

`--pascal disassemble code output.asm` writes a code file as source for the native assembler, and assembles it to
check that it gives the same bytes, exiting 0 when it does. `--pascal assemble` turns such a source, edited or not,
back into a code file:

```text
Retrocore.Debug --pascal disassemble APPLE3.dsk FORMATTER.CODE formatter.asm
Retrocore.Debug --pascal assemble formatter.asm FORMATTER.CODE
```

The source says every byte of the file, from address 0:

- **P-code** is written with the macros of [`Pcode.asm`](../src/Retrocore.Pascal/Pcode.asm), which the source
  includes from the debug host's SDK as `.include <Pascal/Pcode.asm>`: `LDL 3`, `CXP 0, 19`, `CSP IOC`,
  `LSA "TEXT"`, one macro to a p-code. They are defined under `.cpu Pcode`, which has no instructions of its own.
- **Layout:** the segment dictionary in block 0, then each segment from its block, as a `.scope`, and each procedure
  as a scope inside it. Jumps go to labels; a jump back, or one too far for a byte, goes through the procedure's jump
  table (`UJPT T0542`). Jump tables, a procedure's entry and exit, and the procedure dictionary are self-relative
  words written as label arithmetic (`.word * - Exit`), so code can move.
- **Assembled procedures** are 6502 code under `.cpu Mos6502`, where p-code's `LDA`, `INC`, `NOP` and `STP` are the
  6502's again. An operand the procedure's relocation list names is an offset from its entry, written
  `lda.w L059A - Entry`, and the list names each such operand by its instruction's label.
- **What it cannot read** it writes as data, with a note: the system's stub segments, whose procedures are elsewhere.
  The byte the Compiler skips to put an operand on a word is kept as it is.

### Names

Unnamed, segments are named as their dictionary names them, procedures `P2`, and places by their offset, `L059A`.
Calls and constants are named whatever is at hand:

- **The system's procedures** by `Pcode.asm`'s scopes: `CXP 0, PASCALSY::FWRITESTRING`, and PASCALIO's
  `CXP PASCALIO::Segment, PASCALIO::FWRITEREAL`.
- **Units** from the library's interface text (`--library`, by default `SYSTEM.LIBRARY` on the code file's disk):
  the source defines each unit's scope, `TURTLEGR::Segment = 20` and its procedures, and calls
  `CXP TURTLEGR::Segment, TURTLEGR::TURN`.
- **Calls** within the file have their callee beside them: `CGP 2 ; HILBERT::HIL`.
- **A real constant** has its value beside it, where its two words read as a number a source would write.
- **A listing** (`--listing`, the Compiler's listing of the program) names segments and procedures by their
  headings, names variables beside each load and store (`STL 3 ; A`, `SLDO5 ; SIZE`), and puts each statement's
  source line above its p-code (`;   12: HIL(I-1,...)`).
- **Intermediate variables**, which `LOD`, `STR` and `LDA` reach in an enclosing procedure: the system's files,
  INPUT, OUTPUT and KEYBOARD; a program's globals; and, with a listing, any other procedure's, as HILBERT's HIL1
  reaches HIL's `A` (`LOD 1, 3 ; A`). The listing gives the nesting: a procedure is declared in the last procedure
  a level out whose heading comes before its own.
- **A FOR loop's limit**, the word the Compiler adds to keep it, which no source declares: where the loop stores
  it and where its top tests the control variable against it (`SRO 8 ; FOR N's limit`). The word can serve another
  loop or a `WITH` elsewhere, so only those two places are named.
- **Hints** (`--hints`, a JSON file) name and comment anything else, keyed as `pascal` breakpoints name code:
  `SEGMENT` for a segment, `SEGMENT.N` for procedure N, and `SEGMENT.N+$OFFSET` for a place in it, by its offset
  from the procedure's entry; and `SEGMENT.N@WORD` for a variable, by its word in procedure N's frame, as `LDL`
  numbers it (a program's globals are its procedure 1's, as `LDO` numbers them). A name is a segment's or
  procedure's scope, a label, or a variable's, written beside each load and store of it; a comment goes above.

```json
{
  "names": { "FORMATTE.2": "FormatDisk", "FORMATTE.2+$40": "Iob", "FORMATTE.1@1038": "DataFile" },
  "comments": { "FORMATTE.2+$40": "RWTS's input/output block" }
}
```

A listing or a hint wins over a name the file has; a name the assembler cannot take is made one (letters, digits and
`_`), and two the same are made different.

Every code file on Apple Pascal's and Apple III Pascal's disks, the system's own programs among them, is written so
and assembles back byte-identically, named or not. Hovers in the editor show a p-code's macro on a p-code line and the 6502's
instruction on a 6502 line.

## Testing

- `PcodeTests`, `PascalListingTests` and `PascalMediaTests` need no files for most of their tests.
- With the disks, `PascalMediaTests` and `PcodeTests` read and disassemble every code file on them;
  `Apple3PascalTests` and `Apple2PascalTests` boot Pascal, compile and run a program, and read its frames: Apple III
  Pascal 1.0, 1.1 and 1.2 (on disks built as above), and Apple Pascal 1.0, 1.1 and 1.2 on the II Plus and 1.1 and
  1.2 on the IIe. Apple III Pascal's disks are with the other Apple III disks
  (`RETROCORE_APPLE3_DISKS`), and Apple Pascal's in `RETROCORE_APPLE2_PASCAL_DISKS` (by default
  `<cache>\apple2-pascal-disks`, as `UCSD Pascal 1.1_0.dsk` to `1.1_3.dsk` and `1.2_0.DSK` to `1.2_3.DSK`).
- `PcodeAssemblyTests` assemble p-code source: a small code file of the tests' own with an assembled procedure, named
  from hints and from a listing, and, with Apple Pascal's disks, HILBERT with the library's names and every code file
  on them, written by `--pascal disassemble`'s writer.
- `PascalDecompilerTests` decompile two small programs kept as code files; with Apple Pascal's disks, each sample
  program on APPLE3 is decompiled, compiled again on an emulated Apple II, and compared with the original.
- `node tools/Test-PascalDap.mjs` drives the debug host on both machines, and on the Apple III compiles a program
  and stops in its source.

The [backlog plan](backlog/ApplePascal.md) says how this was built and what is still to come.
