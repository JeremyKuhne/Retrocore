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
- `--pascal compile source.text APPLE1.dsk APPLE2.dsk output.code [listing.text] [--unit NAME.CODE]...` compiles a
  source with Apple Pascal's own Compiler, on an emulated Apple II, and writes the listing the source asks for with
  `(*$L APPLE1:NAME.TEXT*)`; a Pascal file's name is at most 15 letters, so `HIL.LST.TEXT`, not `HILBERT.LST.TEXT`.
  Each `--unit` code file goes beside the source, for its `USES (*$U NAME.CODE*) NAME` to find. With
  `--includes folder`, the source is a main file that includes the folder's files by name, `(*$I NAME.TEXT*)`, each
  put on SOURCE:, the boot disk or CODE:, whichever has room, and its directive given that volume (below);
- `--pascal assembly code output.text` writes each segment's assembled procedures as source for Apple's Assembler, as
  `output.SEGMENT.text`, a library's units naming their procedures from their interface text;
- `--pascal assemble-native source.text APPLE1.dsk APPLE2.dsk output.code` assembles a 6502 source with Apple's own
  Assembler, and `--pascal link host.code [library.code...] APPLE1.dsk APPLE2.dsk output.code` links a host with
  libraries with Apple's own Linker, both on an emulated Apple II, as `compile` runs the Compiler (below);
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
  indexes, GOTO, or a string passed to a VAR string of another length. A procedure that loads segments as it starts
  (GSEG) and releases them as it ends (RSEG) has `(*$R ...*)` after its BEGIN, naming each segment it sees and
  numbering the others (`(*$R DECLARAT,BODYPART,11,12*)`).
- **The system's other procedures**: a program compiled as part of the system that calls one of the system's
  procedures no standard procedure names (`CXP 0, 43`) declares headings for the system's procedures up to it in the
  system's block, FORWARD, which the Compiler numbers as the system does; the called ones take their arguments as
  parameters (`PROCEDURE SYSTEM43(VAR A1: T55; A2: INTEGER; A3: INTEGER); FORWARD;`).

With the Compiler's listing of the program (`--listing`), procedures, parameters and variables are named as the
source named them; with HILBERT's, the decompiled source reads as the original. Hints (`--hints`, the JSON file
[`--pascal disassemble`](#names) takes) name them too, keyed `SEGMENT.N` for procedure N and `SEGMENT.N@WORD` for a
variable, and win over the listing; a hint's comment for `SEGMENT.N` goes above the procedure's heading. A name must
leave the code as it is, so one is refused, with a warning, where it is a reserved or predeclared word (FORMATTER's
`IoResult` would hide the `IORESULT` its code calls), a library unit's, or the same in its first eight letters, all
the Compiler reads, as another the procedure reaches or is reached from; and the program's and a segment
procedure's names must be their segments'.

Hints also name what the decompiler's own names stand for, keyed by them: `T2` for a type, `T2.F0` for its field (by
the field's name as the decompiler writes it, `T2.T2F6V1` for a prefixed one), and, in a program compiled as part of
the system, `SYSTEM@8` for the system's global at word 8. A field goes by its name alone inside a `WITH`, where it
hides any other name, and a type's name reaches every procedure, so a type's or a field's name must be unlike every
other name the source has in its first eight letters, the decompiler's own names among them, or it is refused with a
warning. Comments go with the same keys: a type's above its declaration, a field's beside it, where its record is
written a field to a line, a variable's (`SEGMENT.N@WORD`, `SYSTEM@8`) beside its declaration, and a system
procedure's (`SYSTEM.43`) beside its heading. A comment of several lines (`\n`) is written as several, in the Pascal
and in the Assembler's source, where each line is also wrapped to fit the 80 characters the Assembler reads of one.
Hints can also name a variable's, field's or type's values (a set type's elements, for a set): `constants` gives
lists of names, for the values from 0 (`"SYMBOL": ["IDENT", "COMMA", ...]`, an empty name for a value left unnamed),
and `values` which keys take them (`"PASCALCO.1@15": "SYMBOL"`, `"T6.T6F1": "STRUCTFORM"`, `"T42": "SYMBOL"`). The
lists are declared as `CONST`s in the program's block, and a constant compared with, stored in, passed for or a
`CASE` label or set member of one of those is written by its name: a constant loads as the number it is, so the
code is the same. Each name must be unlike every other in the source, or its list is left out, with a warning.
A value read through another view of a word takes a list too, keyed by the view: `"T35.F2.I": "VACCESS"` names what
`ACCESS` holds where the source reads it as `CVAL.I`. A system procedure the code calls (`CXP 0,n`), written
`SYSTEMn`, is named by `SYSTEM.n` (`"SYSTEM.2": "EXECERROR"`), and its parameters by `SYSTEM.n@1` and on, and the
views of a word a record keeps as integer, pointer or bytes (`.I`, `.P`, `.B`) by `T4.I` and the like. The labels
of a variant record's variants, by which `NEW` makes one as short as its variant, are named by `T2:104`, declared as
`CONST`s above the types and written in the record's `CASE` and in `NEW(P, LABEL)`; the padding fields a variant
keeps (`X4N`) are named as other fields are.
Apple Pascal 1.3's Compiler, named and commented so, is kept outside this repository.

A unit's procedures are named from its interface text in the library (by default the disk's `SYSTEM.LIBRARY`, or
`--library disk NAME`); the source `USES` them as the program did. Where some code cannot be decompiled, the
procedure says so in a comment, the command lists it as a warning, and exits with 1.

Apple Pascal 1.1's sample programs (HILBERT, TREE, BALANCED, CROSSREF, DISKIO, GRAFDEMO, GRAFCHARS, SPIRODEMO,
LINEFEED) and the BINDER utility decompile to sources that compile to the same code, but for the byte the Compiler
skips to align a constant or case table, which holds whatever its buffer had and which `compare` ignores. Not
decompiled yet: a unit's variables. `SCAN` decompiles,
with its test (`SCAN(41, = CH, BUF)`), and so does Apple III Pascal's `UNITSTATUS(UNIT, BUF, CONTROL)`, its `CSP 12`,
and the Compiler's own `IDSEARCH(CURSOR, BUF^)` and `TREESEARCH(ROOT, FOUND, NAME)` (`CSP IDS`, `CSP TRS`), which a
program can name too. A segment procedure that calls one of the program's procedures (`CXP 1, n`) has it declared
`FORWARD` before it, as the Compiler takes no segment procedure after a procedure's code; a segment procedure is named
after its segment.

A program compiled as part of the system, `(*$U-*)`, such as Apple's Compilers, is told from its body, which does not
start with the two `NOP`s (or the jump) a program's does. Found by compiling probes: with `(*$U-*)` before `PROGRAM`,
the program is the system's outer block, at level -1, segment 0, and its variables are the system's globals, from
word 1, beside the `INPUT`, `OUTPUT` and `KEYBOARD` the Compiler still declares at words 2 to 4; its segment
procedures are numbered from 1, and `(*$U-*)` turns off I/O and range checks. Each takes a slot of the code file's
16 too, so a placeholder can't number them on; the Compiler's own option `(*$NS n*)` (next segment), found in its
options parser, COMPOPTI, sets the next one's number without a slot. Apple's Compiler is segment procedure 1 with
its own from 7, so it is decompiled as

    (*$U-*)
    PROGRAM PASCALSYSTEM;
    VAR SYS1: T1; ... SYS8: T4; ...        (* the system's globals the code reaches *)
    SEGMENT PROCEDURE PASCALCO(G2: ...; G1: ...);
      ...
      (*$NS 7*)
      SEGMENT PROCEDURE COMPINIT;
      ...
    BEGIN ... END;
    BEGIN
    END.

Apple Pascal 1.0's Compiler, whose code is version 1, has no `NS`: segment procedures declared `FORWARD` and never
given a body take the numbers before Apple's, `SEGMENT PROCEDURE SEG2; FORWARD;` to `SEG6`, and their slots, named
but empty, are left out of a comparison. It indexes the system's files from word 1 (`SYS1[5 + 1]^`), an array of
pointers to files, and leaves its buffer's byte, not 0, after a procedure's last p-code where its attributes start
on a word, which `compare` ignores as it does an operand's alignment byte.

A global the code passes as a file holds the file's address (`LOD`), so it is a pointer to an untyped file, written
`BLOCKREAD(SYS8^, ...)`: the Compiler takes that for `BLOCKREAD`, but not `WRITE(P^, ...)`. Apple's file then had
its own segments copied out by the Librarian, into other slots and without segment 0; `--pascal compare` pairs
segments by number and leaves out those with no code and the outer block. A source too long for APPLE1 beside its
code file, such as a Compiler's, is compiled from a volume of its own, SOURCE:, in a second Disk II in slot 5 (units
11 and 12), to CODE: beside it; Apple Pascal 1.1 sees both. One too long for a volume, such as Apple Pascal 1.3's
Compiler's, is cut before procedures of the outer block into pieces of about 40K characters, or fewer where the main
file would not fit: the main file keeps every other piece and includes each of the others where it was (`(*$I
SOURCE:INC1.TEXT*)`; the Compiler includes no file from an included one), each on SOURCE: while it fits, then on the
boot disk, then on CODE:, which keeps room for the code file. The code file is read back without the empty blocks
after its code, which it keeps of the room CODE: had and the Linker cannot copy. A source already kept as a main file
and the files it includes, one level deep as the Compiler allows, is compiled with `--includes`: each file goes
where it fits in the same way.

### Rebuilding a linked program

The byte the Compiler skips to put an `LDC`'s or `XJP`'s words on a word boundary holds whatever its buffer had,
which no source says: Apple's Compilers left bytes there that the 1.1 Compiler on APPLE2 leaves as 0. A decompiled
source records those that are not 0 after its `END.`, where the Compiler reads nothing, as
`(* Alignment bytes FORMATTE $009F=$54 $00C9=$02 *)`, and `--pascal compile` puts them back.

A program with assembled procedures is rebuilt as Apple built it: the source compiled, the procedures assembled
with Apple's Assembler, and the two linked with Apple's Linker. `--pascal decompile` writes the assembled
procedures beside its output, as `NAME.asm.text`, in the Assembler's syntax: each a `.PROC` or `.FUNC` with the
parameters' words its call passes, named as the Pascal source declares it `EXTERNAL`, which is how the Linker
matches the two (a linked file keeps no name of its own for it). Hexadecimal is written without `$`, as the
Assembler reads it; an operand or word the procedure-relative list names is written by label, and the Assembler
lists it again in the order the code has it; and a three-byte instruction with an absolute operand below $100 is
written as its bytes, since the Assembler would make it zero page. FORMATTER rebuilds byte for byte from the disk,
hints or not:

```text
Retrocore.Debug --pascal decompile APPLE3.dsk FORMATTER.CODE formatter.text
Retrocore.Debug --pascal compile formatter.text APPLE1.dsk APPLE2.dsk FORMATTER.HOST.CODE
Retrocore.Debug --pascal assemble-native formatter.asm.text APPLE1.dsk APPLE2.dsk FORMATTER.ASM.CODE
Retrocore.Debug --pascal link FORMATTER.HOST.CODE FORMATTER.ASM.CODE APPLE1.dsk APPLE2.dsk FORMATTER.CODE
```

Hints name the assembled procedure's places as labels (`FORMATTE.2+$40` for `IOB`) and comment them. Each of an
assembled procedure's four relocation lists is written as what its words are relative to, as Apple's tools turn
them into words when they link:

| Words relative to | Linked as | Written as |
| --- | --- | --- |
| the procedure | an offset from its entry | a label |
| the segment, to another procedure | an offset in the segment | its name, `.REF PROC3`; or a label it defines, `.DEF D0B79` and `.REF D0B79` |
| the host's globals (BASE) | 10 + 2 bytes a word: word 3 is 16 | the global the decompiled source declares, `.PUBLIC G3` |
| the interpreter | an offset in it | `.INTERP+4` |

`.INTERP` is relocated only by Apple Pascal 1.2's Assembler and Linker, whose interpreter moves; 1.1's write it as
the offset alone, so code that uses it is rebuilt with 1.2's disks. Code is decoded from the procedure's entry, its
branches, and each place a JSR or JMP reaches, from it or from another procedure; the rest is data. An indirect JMP
is written `JMP @3D00`, as the Assembler takes no parentheses there; and a global named `A`, `X` or `Y`, or a
mnemonic, cannot be `.PUBLIC`. Not written: data before a procedure's entry, a segment-relative word to a place no
assembled procedure has or to its own procedure, and a global the host does not name, as for a system program; each
is a warning. Every assembled procedure in Apple Pascal 1.2's SYSTEM.LIBRARY and Apple III Pascal 1.1's Editor, and
all but the one with a word of the Editor's globals in 1.2's, assemble back to the same bytes with Apple Pascal
1.2's Assembler; so does Apple III Pascal's AIIFORMAT's, though it links with Apple III Pascal's Linker.

The Assembler's prompt for a listing is answered with none, and the Linker's for a host, libraries, map and output
with the workfile, the libraries in order, none, and the output; the Editor comes off APPLE1's copy to make room.

Apple III Pascal's code is rebuilt with its own tools the same way: given Apple III Pascal's disks, which are SOS
volumes, `compile`, `assemble-native` and `link` run its Compiler, Assembler and Linker on an emulated Apple III,
with /PASCAL1 in the built-in drive, /PASCAL2 in .D2 and the files on a work volume, /WORK, in .D3. Apple III
Pascal 1.1's two disks hold all three tools; the boot ROM and the disk sequencer are built from the SDK's sources,
so no ROM dump is needed. For 1.2, build its disks from 1.1's and the update with `--pascal sos`, as its update
disks say.

```text
Retrocore.Debug --pascal compile program.text Apple3Pascal1.1Disk1.dsk Apple3Pascal1.1Disk2.dsk HOST.CODE
Retrocore.Debug --pascal assemble-native program.asm.text Apple3Pascal1.1Disk1.dsk Apple3Pascal1.1Disk2.dsk ASM.CODE
Retrocore.Debug --pascal link HOST.CODE ASM.CODE Apple3Pascal1.1Disk1.dsk Apple3Pascal1.1Disk2.dsk PROGRAM.CODE
```
`PascalDecompilerTests.FormatterRebuildsByteForByte` rebuilds FORMATTER so, `LinkedProgramsRebuildByteForByte` a
program and a 6502 function of its own, `SharedNamesRebuildByteForByte` two procedures sharing a label and a global
with 1.1's tools, `InterpreterWordsRebuildByteForByte` one using `.INTERP` with 1.2's, and
`Apple3LinkedProgramsRebuildByteForByte` a program and its 6502 function with Apple III Pascal 1.1's on the Apple
III. AIIFORMAT's assembled procedure, and every one in Apple III Pascal 1.1's Editor, assemble to the same bytes
with Apple III Pascal's Assembler.

### Units

A program's own units, which the Linker linked in, decompile to UNIT sources of their own, written beside the
program as `NAME.UNIT.text`. A unit's segment holds its initialization, procedure 1, and its procedures beside it at
its level (a segment procedure's are inside it). Its interface declares the procedures something outside it calls,
from 2, with the types they are declared with, and the program takes those types from it; the rest are its own, in
its implementation, where the interface's are by name alone and an assembled one is `EXTERNAL`. The program
`USES (*$U NAME.CODE*) NAME`, in the order of their segments, which numbers them from 7, and the Compiler calls
their initializations, so the source does not. Each unit is compiled on its own, to `NAME.CODE`; then the program,
with them beside it; then all are linked:

```text
Retrocore.Debug --pascal decompile PASCAL3.dsk AIIFORMAT.CODE aiiformat.text
Retrocore.Debug --pascal compile aiiformat.GETUNITN.text PASCAL1.dsk PASCAL2.dsk GETUNITN.CODE
Retrocore.Debug --pascal compile aiiformat.text PASCAL1.dsk PASCAL2.dsk HOST.CODE --unit CODEACCE.CODE --unit GETUNITN.CODE
Retrocore.Debug --pascal link HOST.CODE CODEACCE.CODE GETUNITN.CODE ASM.CODE PASCAL1.dsk PASCAL2.dsk AIIFORMAT.CODE
```

A program and its two units, one with an assembled function, built so with Apple III Pascal 1.1's tools, rebuild
from their decompiled sources to the same segments (`UnitsRebuildOnTheApple3`); the blocks' unused ends differ, as
they hold what the Compiler's buffer had, the units' interface text, whose names the code does not keep.
AIIFORMAT's GETUNITNAME compiles to the same p-code. Its CODEACCESS does not compile: it reaches the system's global
at word 630 (`SYS630`), the running code file's, as only a program compiled as part of the system can; and its
segment 15 is the Apple II boot code it writes onto the disks it formats, data no source makes. Each is a warning. A code file from another version's Compiler decompiles, but
compiles the same only with that Compiler.

An intrinsic unit the code file names but no library at hand declares, such as the system's own that Apple III
Pascal 1.1's and 1.2's Compilers call in `SYSTEM.PASCAL`, whose code keeps no interface, is declared from its calls:
`UNITn`, `INTRINSIC CODE n DATA n+1`, its procedures `UnPm` (functions `UnFm`, of an integer) from 2 to the last
called, each `EXTERNAL`, with the parameters its calls pass: a string constant's a value string, an address's an
untyped VAR, a set's a set of its words, and a word an integer; and the variables of its data segment the code reaches
(`UnVm`), with padding between. It is written beside the program as `NAME.UNITn.text`, is compiled first for its
interface, which the program's `USES (*$U UNITn.CODE*) UNITn` reads, and is not linked, as the system has its code.
Each Apple III Pascal Compiler so rebuilds from its decompiled source to the same segments
(`Apple3PascalCompilerRoundTripTests`).

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
