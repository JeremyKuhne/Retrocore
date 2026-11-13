# Retrocore Assembly and Debugger

Native Retrocore assembly highlighting, language features and source debugging on
the Apple II family, the Apple-1, the TRS-80 Model I, III, 4, II, 12 and 16, and the TRS-80 Color Computer in one extension. Highlighting is declarative and needs no C# process,
ROMs or debug session. Language features (errors as you type, go to definition,
hover, completion and symbols) come from a language server in the .NET debug host,
which starts when a `retrocore-asm` document opens; see
[Language features](#language-features).

## Select the assembly language

`*.asm` files open as **Retrocore Assembly** (`retrocore-asm`), and `*.mac` files as
**MACRO-10 Assembly**. `*.s` and `*.inc` are not claimed, as ca65 and the GNU
assembler use them; select the language with the status-bar language selector or
**Change Language Mode**, or add a workspace setting:

```json
{
  "files.associations": {
    "*.s": "retrocore-asm"
  }
}
```

Other assembly extensions claim `*.asm` too, and when two do, VS Code picks one.
A `files.associations` entry settles it either way: map `*.asm` to
`retrocore-asm` in a workspace that should use this extension, or to the other
extension's language where it should not. This extension does not edit your
settings automatically.

MACRO-10 sources, such as the SDK's AppleSoft (`m6502.asm` and its `applesoft.mac`
overlay), can use **MACRO-10 Assembly** (`retrocore-macro10`) instead: it is the
same assembly language, highlighting and language server, with its own red `MAC`
file icon. The BASIC
languages show a green `BAS` icon. Language icons appear only where your file
icon theme has none of its own for the file.

## Installing and self-hosting

**The extension is not published**: it is not on the VS Code Marketplace or Open
VSX. Build its VSIX from the repository and install that. There are two ways to use
it: installed, for everyday work in any folder, and self-hosted, to fix it.

To build and install it, run this from the repository root. It needs the .NET 10
SDK, Node.js with npm, PowerShell 7, and VS Code's `code` command on `PATH`:

```powershell
.\tools\Install-Extension.ps1
```

The script:

1. compiles the extension;
2. publishes the debug host, which also runs the language server, into the package;
3. writes `artifacts\vsix\retrocore-<version>.vsix` and installs it in VS Code.

Reload VS Code's windows afterwards. Run it again whenever a fix is good enough to
keep.

`-PackageOnly` only writes the VSIX. To install that VSIX somewhere else, use
**Extensions: Install from VSIX...** or `code --install-extension` with its path.
The packaged host is framework-dependent, so it needs the .NET 10 runtime.

The installed extension uses the host packaged with it, so it works in any folder
and stays on that build even with this repository open. A self-hosted extension
uses the repository's Release build first, so a rebuild shows at once. The
`retrocore.languageServer.host` setting and a launch configuration's `debugHost`
override either.

To try the extension from this repository (self-hosting), run
`tools\Start-SelfHost.ps1` from the repository root. It compiles the extension,
builds the debug host that runs the language server, and opens the repository in
a separate VS Code window running the in-repo extension, on
`sample\trs80\hello.asm` or the files given with `-File`. That window has its own
profile under `artifacts\self-host`, so your VS Code profile is unchanged.
Highlighting and IntelliSense need no ROMs, and neither does a launch: without dumps
the IIe, the Model I and every Color Computer run ROMs assembled from the SDK's sources. `-RomDirectory` (or
`RETROCORE_IIE_ROMS`) lets the IIe launch configurations use your IIe dumps instead, and
`tools\Start-IIeDevelopment.ps1 <rom directory>` opens the IIe sample with them.
`-SkipBuild` relaunches without building. After a change, rebuild and run
**Developer: Reload Window** in the development window.

**Run Extension** in the repository's Run and Debug view does the same from F5,
with the debugger attached to the extension's TypeScript, in your own profile.

Agents can do this for you: the `retrocore-self-host` skill in `.claude/skills`,
which both Claude Code and GitHub Copilot in VS Code read, tells them to run the
script. Ask either one to "self host", or to "install the extension" to update the
installed copy.

A day's loop: notice a problem in your everyday VS Code, self-host to fix it, then
run `Install-Extension.ps1` to bring the fix to your everyday editor.

## Starting a machine

No launch.json is needed to start a machine. Without dumps, the Apple II family and the
TRS-80s run ROMs assembled from the SDK's sources, so there is nothing else to set up; the
Color Computer 1, 2 and 3 run Color, Extended and Disk BASIC and the CoCo 3's ROM from
their sources.

The quickest way is the **Run and Debug** dropdown. Under Retrocore it lists each
machine: Apple IIe (enhanced), Apple IIe, Apple II Plus, Apple II, Apple III, TRS-80
Model I (Level II), TRS-80 Model I (Level I), TRS-80 Model III, Model 4, Model 4P,
Model II, Model 12 and Model 16 (Z80 side), Apple-1, and the TRS-80 Color Computer,
Color Computer 2 and Color Computer 3. Pick one and press F5, and it boots as it is. **Debug: Select and Start Debugging** lists them too.

To start a machine with something in it, run **Retrocore: Start Machine…**. It is in
the Command Palette, and it is the ▶ button on the **Retro Devices** view while no
session runs. It asks three things:

1. **Which machine.** The last setup you started comes first, so one pick repeats it.
2. **What it runs.** The choices depend on the machine:
   - just the machine;
   - a source file, which is assembled and loaded, then stops at its start;
   - a binary program, loaded at the machine's usual address;
   - a BASIC file, for the machine's own BASIC;
   - a disk image, booted from the first drive;
   - a tape, on the Model I, the Apple-1 and the Color Computer;
   - on the Apple II family, a source file on a fresh DOS 3.3 disk, which boots and
     runs it.

   The open editor's file is offered first when the machine can run it.
3. **Start, Options… or Save as Launch Configuration.**
   - **Start** boots it with the machine's defaults. Cards and disks the machine
     last ran with come back, as [Retro Devices](#retro-devices) describes.
   - **Options…** lists that machine's own choices, such as the II's Monitor, the II
     and II Plus's memory and slot 0 card, the Mockingboard, the Model I's
     Expansion Interface and lowercase, and the Apple-1's memory and cassette interface. Each shows its current value; Esc goes back.
   - **Save as Launch Configuration** adds the setup to the workspace's launch.json,
     under a name you confirm, replacing one of the same name.

**Retrocore: Start Last Machine** starts the last setup again without asking.
**Retrocore: Save Last Machine as Launch Configuration** saves it to launch.json.

A launch configuration is still the way to use options the picks don't offer, such
as `breakpoints`, `speed` or your own ROM dumps. Saving a setup is a good start for
one. The sections below describe each machine's launch options.

## What is highlighted

- All three current CPU maps: MOS 6502, WDC 65C02 and Rockwell 65C02, including
  undocumented NMOS names and numbered `BBR`/`BBS`/`RMB`/`SMB` instructions.
- From a `.cpu Z80` line to the next `.cpu` of another CPU, the Z80's mnemonics
  (including `SLL`), its registers anywhere in an operand (`AF'` included) and
  the condition after a jump, call or return.
- From a `.cpu I8080` or `.cpu I8085` line to the next `.cpu` of another CPU,
  Intel's mnemonics and registers, `M` and `PSW` included.
- Instructions only at the start of a statement or after its label. A label
  named `LDA:`, an operand named `LDA` and `LDA` in a comment are not opcodes.
- Flow instructions separately from other instructions.
- Label definitions, constant assignments and symbol references.
- Index registers only in indexed operand syntax; `A` only in accumulator
  instruction syntax. `LDA A`, `ASL A+0` and `.byte X` retain ordinary symbols.
- Native `.cpu`, `.rom`, `.equ`, `.set`, `.byte`, `.word`, `.dword`, `.res`,
  `.org`, `.logicalorg`, `.align`, `.dum`, `.dend`, `.checksum`, `.section`,
  `.assert` and `.export` directives, processor identifiers (including the
  assembler's `65SC02` subset) and generated ROM type names.
- Native includes, macros, conditionals and repeats, including `.local`,
  `.paramcount`, `.ifblank` and `.exitmacro`.
- Hexadecimal, binary and decimal numbers, quoted literals, operators,
  punctuation and semicolon comments. A semicolon inside quotes is not a comment.

Semicolon line-comment toggling, parenthesis matching/navigation, quote pairing
and symbol-oriented word selection are included. Quoted text is recognized
lexically; highlighting does not imply the assembler supports string directives,
escapes or any additional syntax.

This is **syntax** highlighting, not semantic validation. It highlights the union
of supported mnemonics without checking the selected `.cpu`, an operand's range,
whether a name is defined, or a reference's kind. Unknown or unfinished source
is not marked as a compiler error; that is the language server's job, below.

## Language features

The extension starts `Retrocore.Debug --language-server` for `retrocore-asm` documents. It
uses `retrocore.languageServer.host`, or by default the host packaged with the installed
extension; a self-hosted extension uses the workspace's Release build,
`artifacts/AnyCPU/Release/Retrocore.Debug/net10.0/Retrocore.Debug.dll`, first.
`retrocore.languageServer.enabled` turns it off.

The server assembles with retrocore itself, so everything follows the real dialect,
includes and macros:

- **Errors as you type.** Each edit reassembles the file's assembly about a quarter
  second later. An error inside an include or a macro is reported where it is, with
  the include or invocation as related information.
- **Go to definition** for labels, constants and macros, across includes. In a
  source that does not assemble yet, column-0 labels and equates are still found,
  and cheap locals resolve to the nearest definition.
- **Find all references** (Shift+F12) for labels, constants and macros: every use
  in code, across includes and the SDK's ROM sources, and every `<NAME>` link in a
  `;;` comment. Each use is resolved as going to its definition is, so a local
  label, or another assembly's name spelled the same, is not listed; strings and
  ordinary comments are skipped.
- **Hover:**
  - for a name: its value and where it is defined, with its `;;` documentation
    rendered (sections, links you can follow, inherited text), or the plain comment
    above its definition when it has none;
  - for an instruction: what it does, the flags it changes, and its addressing modes
    and opcodes for the CPU selected by the nearest `.cpu`;
  - for a directive: what it does;
  - for any line that emits code: its address and bytes.

  While debugging, VS Code shows the debugger's hover instead: a name's value now,
  followed by its `;;` summary. Hold Alt to see the full hover above.
- **Completion:** at an operation, the CPU's mnemonics, the directives and the
  assembly's macros; in an operand, its labels and constants, each with its
  documented summary.
- **Documentation checks** as warnings: `;;` comments that document nothing,
  links and `Inherit:` targets that don't resolve, unknown registers or symbols in
  `In:`/`Out:`/`Keeps:`, and uses of definitions marked `Deprecated:`.
- **Outline** of a file's labels, constants and macros, and **workspace symbol
  search** (Ctrl+T) across open assemblies and the SDK's ROM sources shipped beside
  the host, so `COUT` finds the Monitor's.

Each file is assembled as its own root unless an assembly already analysed
includes it; a MACRO-10 base such as `m6502.asm` is analysed through the overlay
beside it that names it. Files the extension does not recognize as `retrocore-asm`
(such as `.s` sources) get language features once you select the language or add a
`files.associations` entry.

Not yet: find references, rename, semantic tokens and inlay hints, which need the
assembler to record where names are used.

## Documentation comments

`;;` comments are documentation, as `///` is in C#; plain `;` comments stay
ordinary. A `;;` block documents the definition directly below it, and a trailing
`;;` documents a constant or member on its own line. Sections are one line each:

```asm
;; Plots one lo-res block in the current color.
;; In:    A = row (0-47), Y = column (0-39), COLOR = the color in both nibbles
;; Uses:  A, GBASL, GBASH, MASK
;; Keeps: X, Y
;; See:   <SCRN>, <SETCOL>
PLOT:
```

`<Name>` links resolve through scopes, the rest of the assembly and the SDK's
modules (`<Monitor:COUT>`, `<$FDED>`, `<GETLN#Out>`), and `Inherit: <GETLN>` takes
another topic's documentation like `<inheritdoc>`. The debugger shows the routine
each stack frame is in as a scope in the Variables pane, with its `In:`/`Out:`
entries' current values, and reports a call that returns with a `Keeps:` register,
flag or memory location changed (launch options `checkContracts`: `warn`, `stop`
or `off`; `checkUses` to also check `Uses:`). The source generator copies summaries
of exported symbols into the generated C# members' XML documentation. The full
format is in [docs/DocComments.md](../docs/DocComments.md); the SDK's ROM sources
use it throughout.

## Native assembly

The native dialect, Retrocore's own, is specified in
[the native assembly reference](../docs/NativeAssembly.md). In brief:

- Labels end with a colon, constants are `Name = value`, and data is `.byte`, `.word`, `.res` and the like.
- Expressions use `$hex`, `%binary` and `'c'` with C's operator precedence, and `*` is the current address.
- `.cpu` selects `Mos6502`, `Wdc65C02`, `Rockwell65C02`, `65SC02`, `Z80`, `M6809`, `I8080` or `I8085`; one
  source may switch between families.
- 8080 and 8085 operands are Intel's: `MOV A,M`, `LXI H,Table`, `PUSH PSW`, and `RST` with its number 0-7.
- The 6502 chooses zero page by value, with `a:`, `!`, `.w` and `z:` to force a width.
- Z80 memory and port operands are written in brackets (`LD A,[HL]`, `LD [IX+5],A`, `IN A,[$FE]`), so
  parentheses always group an expression.
- Macros, conditionals, `.repeat`, `.define`, `.struct`, `.enum`, `.charmap`, includes, `.incbin`, scopes,
  cheap `@` locals and `:` anonymous labels work as ca65's do, with native expressions.

Hover help lists each instruction's opcode bytes and cycles, and each directive's syntax. The disassembler writes
the same syntax.

### ca65 and single-object ld65 support

Select `AssemblyDialect.Ca65`, source/resolver dialect metadata, or a first-line
`; retrocore: dialect=ca65` pragma. ca65 sources use source-order address widths and
the shared includes, macros, conditionals, repeats, scopes and local labels.
Supported translations include:

- `.setcpu "6502"` / `"65C02"` / `"65SC02"`, `.p02`, `.pc02` and `.psc02`. As in
  ca65 2.19, 65C02 means the Rockwell instruction set, without `WAI` and `STP`;
- `.segment` (an optional `: zeropage`, `: absolute` or `: direct` suffix is
  accepted), `.code`, `.rodata`, `.data`, `.bss` and `.zeropage`;
- `.org` and `.reloc`, `.addr`, `.dword`, `.res`, `.align`, `.mac`, `.endmac` and
  `.endrep`;
- `.assert expression, severity, "message"`. Diagnostics have no warning level, so
  `warning` and `ldwarning` fail like `error` and `lderror` when the condition is
  false;
- `.import` and `.importzp`, `.exportzp`, and `.global`/`.globalzp`, which export a
  name when it is defined and otherwise ignore it, as ca65 treats an unused import;
- `.macpack name`, which includes `name.mac` from the include path. ca65 builds its
  packages in, so put cc65's `asminc` directory in `AssemblyOptions.IncludePaths`;
- `.sizeof(Procedure)` for contiguous procedures, `.time` and `.version`.

Expressions use ca65's own operator precedence, which differs from native
precedence. From tightest to loosest:

1. unary `+ - ~ .bitnot < > ^` and `.lobyte()`, `.hibyte()`, `.bankbyte()`;
2. `* / .mod & .bitand ^ .bitxor << .shl >> .shr`;
3. `+ - | .bitor`;
4. `= <> < > <= >=`;
5. `&& .and .xor`;
6. `|| .or`;
7. `! .not`, which apply to the entire expression that follows them.

The front end writes each ca65 expression as an explicitly parenthesized native
expression, so `2 | 1 + 1` is 4 and `! 0 + 1` is 0, as in ca65. Macro arguments
are substituted as written and translated only where the expanded line uses them.
`.time` uses `AssemblyOptions.BuildTime`; `.version` reports the verified ca65
2.19 compatibility level (`$0213`).

In a single-object link only the linker can satisfy an import, so `.import` lines
check their names and otherwise do nothing. Linker-defined symbols are visible
without an import, where ca65 would report them undefined.

Without a configuration, linking uses ld65's built-in `none` target, the same text
as cc65 2.19's `cfg/none.cfg`: zero page starts at `$0080`, main memory at `$1000`,
with the usual STARTUP/LOWCODE/ONCE/CODE/RODATA/DATA/BSS ordering. Supply an
`AssemblySource` in `AssemblyOptions.LinkerConfiguration` for another layout:

```csharp
AssemblyOptions options = new(ProcessorVariant.Mos6502, 0x1000, 0x6800)
{
    Dialect = AssemblyDialect.Ca65,
    LinkerConfiguration = new(File.ReadAllText(@"sample\iie\link.cfg"), "link.cfg"),
    OutputFile = "sample.bin"
};
AssemblyResult result = new Assembler().Assemble(
    new AssemblySource(File.ReadAllText(@"sample\iie\main.s"), @"sample\iie\main.s"),
    options);
// Check result.Success and result.Diagnostics before accessing the output.
ReadOnlyMemory<byte> bytes = result.Files["sample.bin"];
```

The config subset supports:

- `MEMORY` start and size expressions, `file`, `fill`, `fillval`, `type` and
  `bank` (ignored), and `define`. A defined region exposes `__NAME_START__`,
  `__NAME_SIZE__`, `__NAME_LAST__` and `__NAME_FILEOFFS__`; a later region may
  start at an earlier one's `__NAME_LAST__`, as `apple2-asm.cfg` does;
- `SEGMENTS` load, ro/rw/bss/zp type, align (any positive value), start, offset,
  optional and define. A defined segment exposes its size, load and run symbols;
- `SYMBOLS` with `export` and `weak` values (a source definition overrides a weak
  one) and `import` entries;
- `FEATURES` `STARTADDRESS` for `%S`, which otherwise defaults to the options'
  origin. `CONDES` entries are accepted and ignored, because no constructors exist
  to collect.

Commas between attributes are optional, as in ld65. Unspecified `.res` and
`.align` fill bytes use the load region's `fillval`. As in ld65, `.align` in a
linker segment pads relative to the segment's start, and absolutely inside a
`.org` region. Regions maintain independent placement counters. Of cc65 2.19's
stock configurations, those without `run` attributes or a `FILES` block parse.
Sections
can be re-entered, BSS occupies memory without file bytes, and regions assigned
the same file concatenate in MEMORY declaration order. `%O` means `OutputFile`;
`file=""` suppresses file output. The assembler returns owned in-memory
`AssemblyResult.Files` and never writes those filenames itself. Section indices
and source maps remain available through the existing result properties.

This is not a multi-object linker: run/load relocation, the `FILES` block, other
attributes and unimplemented ca65 directives are
rejected rather than ignored. The source generator supports ca65-tagged ROM
inputs too, using `.rom` bounds for one padded output instead of the none layout.
It still resolves includes only from `AdditionalFiles`.

### ca65 SDK types and preprocessing

The ca65 front end also supports:

- `.define` / `.undefine`, including parameterized inline token definitions.
  Definitions expand before expression translation, outside strings/comments.
  Parameters are comma-delimited token lists; braces delimit a list without
  becoming part of it, while parentheses remain expression-grouping tokens.
  Expansion is bounded by the macro recursion limit.
- `.struct` / `.endstruct`, `.union` / `.endunion`, `.enum` / `.endenum`,
  `.tag`, and type/member `.sizeof`. Layouts emit constants, not storage.
  Struct fields advance by their storage sizes; union members share an offset.
  A named nested `.struct Name` opens a namespace with zero-based fields;
  `Member .struct` names a field whose anonymous children stay in the enclosing
  namespace. A type's `.org` changes field offsets, not its storage size.
- `.ident`, `.concat`, `.string`, `.strlen`, `.strat`, `.sprintf`, `.defined` / `.def`,
  `.definedmacro`, `.const` and `.blank`, and the numeric `.min`, `.max`, `.loword`
  and `.hiword`. `.sprintf` takes C-style `%c %d %i %o %s %u %x %X` conversions
  with flags, width and precision. As in ca65, a macro name is not a defined
  symbol for `.defined` or `.ifdef`. `.string` preserves an identifier's spelling;
  numeric expressions become decimal strings.
- Token-list functions `.match`, `.xmatch`, `.tcount`, `.left`, `.right` and `.mid`.
  A list is enclosed in braces or ends at the next comma. `.match` compares token
  types, so all integers match and `a`, `x` and `y` are distinct register tokens;
  `.xmatch` also compares values. Returned lists keep their original spelling.
- `.sizeof` on contiguous scopes and procedures, types and fields, and labels. As in
  ca65, a label's size is the size of the statement on its own line. A forward
  `.sizeof` of a label is accepted here, where ca65 reports the size unknown.
- ca65's built-in `CPU_*` and `CPU_ISET_*` constants, with the values ca65 defines.
- `.charmap` and `.asciiz`. Character mappings apply to emitted strings and
  single-quoted character constants, including instruction operands. `.asciiz`
  appends one zero after its string list.
- `.byt`, big-endian `.dbyt`, 24-bit `.faraddr`, `.lobytes`, and `.hibytes`.
  Data ranges are checked before emission.
- `.ifconst`, `.ifnconst`, `.ifnblank` and CPU-selection conditionals, alongside
  the existing conditional family. `.cpu` and instruction-set masks describe
  the selected CPU. Reference-dependent `.ifref` / `.ifnref` and `.referenced`
  remain errors.
- Labels on `.proc` lines. Listing/debug controls and `.out` / `.warning` are
  accepted without emitting bytes or forwarding messages to a host output
  stream. `.error` / `.fatal` fail with source-located messages. The
  `ubiquitous_idents` feature is accepted; unsupported feature flags are errors.

The optional `Ca65SdkTests` use all 75 cached cc65 `.inc` headers, selected with
`RETROCORE_CA65_ASMINC` or the sibling `asminc` directory in the dependency cache.
The tests compare emitted bytes and fully qualified defined symbols against
real ca65/ld65 debug data, preserving duplicate field names in different scopes.
Hardware fragments receive their parent platform's base-address definitions;
the sim65 fixture supplies its documented linker-defined peripheral address.
Interface declarations such as `zeropage.inc`'s `.globalzp` names stay in the
assembled program; ca65's built-in `CPU_*` constants are values here, not program
symbols, so they are left out of the symbol comparison. Other tests assemble programs
that load `generic`, `longbranch` and `cpu` with `.macpack` and include SDK headers.
External headers are not modified or vendored.

Conditions are evaluated before layout, so an expression that reads `*` or a label's
address is not constant there. A logical operator is still decided by one known
operand: a known-false `.and` operand, or known-true `.or` operand, decides the
condition. cc65's `longbranch.mac` chooses its short form with `.const` of a
location-counter expression, so its `j*` macros always produce the valid long form
here; ca65 uses a short branch for a nearby earlier target. `.ismnemonic` is not
supported.

### Merlin 8/Pro source

Select `AssemblyDialect.Merlin`, source/resolver metadata, or a first-line
`; retrocore: dialect=merlin` pragma. Column zero contains a label; indented text
starts with an opcode or directive. `*` and `;` in column zero are comments.
Operand whitespace follows the verified Merlin32 reference: `DFB 1, 2` emits
both bytes, rather than reproducing the historical Merlin 8 truncation rule.

```asm
; retrocore: dialect=merlin
        ORG $1000
        DSK example.bin
Value   EQU 1
Entry   LDA #Value+2*3
:again  DEX
        BNE :again
        ASC "READY"8D
```

Arithmetic is left-to-right, so the immediate above is 9. `.` is OR, `!` is XOR
and `&` is AND. Immediate `#<`, `#>` and `#^` select bytes of the whole remaining
expression; legacy `#/` is also accepted as a bank-byte alias, where Merlin32
reports an error. Character `"A"` is `$C1`, while `'A'` is `$41`. As in Merlin32,
values keep their low bits silently: an immediate or `DFB` keeps its low byte,
`DA`/`DW`/`DDB` their low 16 bits and `ADR` its low 24 bits, so `DFB -1` is `$FF`.
In data, `<` keeps a value, `>` shifts it right 8 bits and `^` 16, before the field
keeps its low bits. A fourth opcode character other than `L` forces absolute
addressing (`LDA: $10`); `L` selects 65816 long addressing, which is rejected.

Supported directives include `DFB`/`DB`, `DA`/`DW`, `DDB`, `ADR`, `ADRL`, `HEX`,
`DS`, `ORG`, `DUM`/`DEND`, `CHK`, `ERR`, and `ASC`/`DCI`/`INV`/`FLS`/`REV`/`STR`.
Delimiters below `'` set the high bit; string and hexadecimal chunks can be mixed.
DCI flips the final output byte's high bit, including a hexadecimal trailer.
STR prefixes the complete payload length; REV takes one string without trailers.
`DS \` pads to the next page. `BRK` may carry a signature byte (`BRK $12` or
`BRK #$12`). One `XC` selects 65C02. `XCE` assembles as `$FB` in every mode, as in
Merlin32, since 6502 code uses it to probe for a 65816. A second `XC`, `MX`,
`IF MX`, and other 65816-only operations are rejected.

`EQU` is textual, as in Merlin32, including an immediate operand marker such as
`Stack EQU #$FF` and `]` variables read at each use. The exception is `*`, which
means the location of the definition: `Here EQU *` names that address wherever it
is used. An unused EQU is published when its text is a valid expression over
defined names; otherwise, such as hexadecimal text for string trailers, it is
omitted, since Merlin32 accepts any unused EQU. `=` and `]` variables use
source-ordered versioned values;
a `]` address label assigns the current PC. Colon locals use the preceding
ordinary-label context. As in Merlin32, duplicate colon definitions in one
context receive distinct storage, while references bind to its first definition.
Wider source names are collision-checked and exposed through the immutable
`AssemblyResult.SymbolAliases` map.

Macros use `Name MAC` and `EOM`/`<<<`; invoke them with a bare name,
`PMC Name,arg1;arg2`, or `>>>`. Arguments are separated by `;` only, so an
argument such as `($06),Y` keeps its comma. `]1` through `]8` substitute
textually, `]0` is the argument count, and macro-body labels are
invocation-local. `DO`/`ELSE`/`FIN`, character-comparison `IF`, and `LUP`/`--^`
share the bounded expansion engine; in a `LUP`, `@` in a label becomes `A`, `B`,
`C` ... for each iteration, up to 26.

As in Merlin32, only the master file's PUT and USE lines include files; those in
an included file are ignored. PUT inserts its file each time, while USE loads a
macro file once. A name resolves through the source resolver as written, or with
`.s` appended when only that file exists. Merlin32's `4/` macro-folder prefix is
not supported.

SAV/DSK name one trimmed, owned in-memory `AssemblyResult.Files` output; they
never write source-directed host files. Multiple output filenames and external
Merlin linking are unsupported. The source generator accepts Merlin-tagged ROM
inputs, uses the Merlin default CPU or XC, and keeps `.rom`'s exact padded size.
`MerlinText.Decode` converts already-extracted high-bit, CR-separated disk text
to a Merlin-tagged source, rejecting embedded NULs and stripping trailing padding.

The optional `MerlinFrontendTests` run the approved Merlin32 v1.2 beta 2 executable
from the dependency cache (`RETROCORE_MERLIN32` can override its path). The source-only
corpus is [Olivier Jan's BIOS/JMON port](https://github.com/olivierjan/ROM-software-for-6502-SBC)
at `a487813378a05d7230326373fdee77cb8e1f7613`: MIT project code with retained
Apache-2.0 JMON notices. `RETROCORE_MERLIN_CORPUS` overrides its cache directory.
Both builds use the same staged sources: the misplaced macro file is copied
beside its user and the disabled BASIC is an empty stub. The monitor's two XCE
CPU-detection probes are assembled unchanged. All 12,288 output bytes are
compared. No ROM image or BASIC source is downloaded
or vendored. The previously approved Passport revision is ACME, not a Merlin
corpus, and is not used for this milestone.

### MACRO-10 source (Microsoft BASIC)

The MACRO-10 subset is the one Microsoft's published 6502 BASIC 1.1 source
(`m6502.asm`) uses, selected with `dialect=macro10`. MACRO-10 is bracket
structured, so a whole file is expanded at once: `IFE`/`IFN`/`IFG`/`IFGE`/`IFL`/
`IFLE`, `IFDEF`/`IFNDEF`, `IFIDN`/`IFDIF`, `IFB`/`IFNB` and `REPEAT` take
`<...>` bodies that may open and close mid-line and span lines; `DEFINE` macros
take `(dummy,...)` arguments, and `IRP`/`IRPC` iterate over one of them. `IF2`
text applies and `IF1` text does not, as in MACRO-10's final pass. Conditionals
may use label addresses, which the expander lays out as the native assembler
will. Lines from a `DEFINE` body are expansions of their call for debugging, and
a single-statement expansion debugs as its call line.

Numbers use `RADIX` (8 by default, and 8 and 9 keep their face value), `^D`,
`^O`, `^B` or a trailing decimal point; `"AB"` packs seven-bit ASCII; `.` is the
location counter. Operators from tightest: unary `-` `+` `^-`, `_` (shift),
`&` `!` `^!`, `*` `/`, then `+` `-`; `<...>` groups. Symbols are matched without
case to six characters, and names native syntax cannot spell, such as `$Z`, get
aliases in `SymbolAliases`. Labels end in `:`, `::` or `:!`; `=`, `==` and `=:`
assign, and a symbol assigned more than once is a native variable.

Each PDP-10 word is one 6502 byte: a lone expression or `EXP` item emits its low
byte, `XWD` its right half, `BLOCK` reserves, `ORG` moves forward. The 6502
instructions come from Microsoft's unpublished M6502 universal file, rebuilt
from the source's use: the usual mnemonics, an `I` suffix for immediate, `DY`
for `(zp),Y`, `DX` for `(zp,X)`, `JMPD` for `JMP (abs)`, `,X`/`,Y` indexing (a
trailing comma changes nothing) and `A` for the accumulator, with zero page
chosen when the address is known by then. `ADR` emits words and `DC "text"`
characters with the last one's high bit set. Listing and cross-reference
controls (`TITLE`, `SUBTTL`, `PAGE`, `SALL`, `XLIST`, `LIST`, `.XCREF`, `.CREF`,
`PRINTX`, `SEARCH`, `PURGE`) and `COMMENT` blocks are ignored.

The optional `Macro10FrontendTests` build `m6502.asm` from the dependency cache
for KIM-1 and Apple and compare them with the original KIM BASIC 1.1 and
AppleSoft I binaries from mist64/msbasic. The published source is a later
revision than either release (its change log adds `GO TO`, the space check in
reserved words and several fixes, and AppleSoft I has Apple's own statements),
so no byte-exact build exists; built with each release's configuration (RAM,
long errors), the zero-page layout matches and 78% of KIM BASIC and 67% of
AppleSoft I appear in runs of eight bytes or more, and every remaining difference
examined is a source revision. The OSI and STM configurations of the published
source use symbols it never defines, as MACRO-10 would also report.

#### Overlays and AppleSoft II

A MACRO-10 file can be an overlay: a list of edits to a pinned base file, so a
derived program ships only its changes and unchanged lines still debug in the
base file. The first line names the base and its SHA-256 (UTF-8, LF line
endings), which must match:

```
; retrocore: dialect=macro10 overlay=m6502.asm sha256=F3EC99C9...
;@REPLACE 18-18
LNGERR==1
;@END
;@INSERT AFTER 100
...
;@END
;@DELETE 200-210
;@END
```

Line numbers are the base's, one-based. The base is found through the
`SourceResolver`, relative to the overlay.

`AssemblyOptions.PredefinedSymbols` defines constants before any source is read.
Every dialect sees them, and MACRO-10 `IFDEF` does too, so a source can default a
switch with `IFNDEF NAME,<NAME==1>` that a build overrides.

The SDK's AppleSoft II (`src/Retrocore.Machines.Apple2/Roms/AppleSoft`) is Microsoft's
`m6502.asm` (MIT, with its `LICENSE`) plus `applesoft.mac`, an overlay with Apple's
changes. Both have their tabs expanded to spaces at the original's 8 columns, so they
align in any editor. It assembles byte-identically to the IIe ROM at $D000-$F7FF for both
models: `ENHNCD` is 1 for the Enhanced IIe (the default) and 0 for the original.
`AppleSoftTests` pin both ROMs by digest, and compare against your dumps when
`RETROCORE_IIE_ROMS` is set.

With the Monitor, the internal firmware and the video ROM
(`Roms/System/CharacterGenerator.asm`, the font for either model, MouseText included),
the SDK builds the whole IIe: a launch without `romDirectory` or `RETROCORE_IIE_ROMS`
assembles the ROMs from `sdkRoms` (or the copy beside the debug host) and runs them, so
the machine runs exactly the sources you debug.

The Disk II controller's ROMs are SDK sources too (`Roms/DiskII`): the 16-sector card's
boot ROM (`Boot16.asm`, 341-0027) and sequencer (`Sequencer16.asm`, 341-0028), and the
13-sector card's (`Boot13.asm` and `Sequencer13.asm`, 341-0009 and 341-0010). Each
assembles byte-identically to its chip. The two boot ROMs share their code in `Boot.asm`;
a sequencer source lists its reading table in logical order, each entry a command and
the next state, and `Sequencer.asm` holds the shared writing table and lays both out as
the chip is wired. [DiskII.md](../docs/DiskII.md) explains the card and its sources.
A WOZ, `.dsk` or `.do`
`diskImage` boots through the 16-sector card built from them (`diskSectors: 13` for the
older card; a `.d13` image, 13-sector sectors in order, picks it by itself), and the boot
ROM debugs at source level in slot 6. A `.po` image still goes
to the slot 7 block device unless `diskController` is `diskII`. Dumps given as
`diskBootRom` and `diskSequencerRom` replace the SDK's; the known 341-0010 dump was read
from the boot ROM's socket, so it takes `sequencerLayout: "boot-socket"`. `DiskIISourceTests` pin
each chip by digest, and compare against the dumps in `%USERPROFILE%\Retrocore\disk2-roms`
(or `RETROCORE_DISKII_ROMS`) when they are there.

The overlay is maintained by hand.
Apple's text reads as `DT` strings, skip tricks as `SKIP1`/`SKIP2` or commented
opcode bytes, and every address operand is symbolic:

- Microsoft's labels sit where Apple's code puts them, with each keyword handler
  matched through both dispatch tables.
- Apple's keyword handlers and documented entry points have names: `HPOSN`,
  `HPLOT0`, `HGLIN`, `DRAW0`, `HANDLERR` and `GETARYPT`, for example.
- Page zero, the Monitor's entry points and the soft switches have their Apple names.
- Other branch and call targets are named after the routine they are in, in
  Microsoft's style (`HGLIN3`).

Immediates that are characters, tokens or error codes use m6502.asm's spellings
(`CMPI "?"`, `CMPI TOTK`, `LDXI ERRFC`); masks, limits and counts stay numeric.

#### Monitor and internal firmware

The SDK's native sources for the rest of the system ROM are in
`src/Retrocore.Machines.Apple2/Roms/System`:

- **`Monitor.asm`** covers $F800-$FFFF for both models. Lines that differ sit
  under `.if ENHANCED`, which defaults to 1 for the Enhanced IIe; 0 selects the
  original.
- **`Firmware.Original.asm`** and **`Firmware.Enhanced.asm`** cover $C100-$CFFF,
  the 80-column firmware and the routines the Monitor calls with internal ROM
  switched in.
- **`IIeEquates.asm`** names the IIe's page zero, soft switches and keys, and
  **`MonitorEntries.asm`** the Monitor's entry points, for the other sources. The
  firmware, the Disk II boot ROM and DOS (`Roms/Dos`) include both, and the Monitor
  the first, so each name is defined and documented once.

Each assembles byte-identically to its model's ROM, and `SystemSourceTests` pins
all four builds by digest. Apple's documented entry points, tables, page-zero
locations and soft switches have their Apple names. Every routine and table has a
comment describing what it does, with its inputs and outputs where known, and the
firmware's routines have descriptive names (`SCROLLUP80`, `MINILINE`). Other labels
are named after their routine (`PLOT_1`) or their address (`L_C9A4`).

The sources are maintained by hand. They assemble Apple II text through a high-bit
`.charmap`, so characters read as `'A'` and `"Apple //e"`, and they build their
tables from readable lists: the Monitor's disassembler tables from the opcode
matrix's addressing modes (`MODES IMP, INVALID, ...`) and its mnemonics
(`MNEMONICS 0, "BRK", "PHP", ...`), and its command tables from one `COMMAND key,
handler` list.

## Debugging on the IIe

[The Apple II guide](../docs/Apple2.md) covers the family in full: the models, their cards and ROMs, and the
SDK's sources of them.

`"machine": "apple2"` debugs the Apple II family; `model` picks which: `iie-enhanced`
(the default, with the 65C02 and MouseText), `iie` (the original IIe, with an NMOS
6502), `iiplus` or `ii`. Launch configurations written for the IIe alone, with
`"machine": "apple2e"` and `model` `enhanced` or `original`, still work.

The II and II Plus have an NMOS 6502 and 48 KB, and no auxiliary memory, 80-column text
or double hi-res; their keyboards type only capitals, and slot 3 takes a card like the
others. Their ROMs are assembled from the SDK's sources unless the launch gives dumps:
`romDirectory`, or `RETROCORE_IIPLUS_ROMS` or `RETROCORE_II_ROMS`, naming a folder of
2716 chips. The II Plus's are its five AppleSoft chips (341-0011 to 341-0015), the
Autostart Monitor (341-0020) and the 7341-0036 character generator; the II's are its
three Integer BASIC chips (341-0001 to 341-0003) and its original Monitor (341-0004),
with the character generator and Autostart Monitor taken from an `APPLE II+` folder
beside them when they are not there.

- **II Plus:** AppleSoft and the Autostart Monitor. Its AppleSoft is the original IIe's but
  for its last byte, so AppleSoft debugs on its BASIC thread and the SDK's AppleSoft and
  Monitor sources apply.
- **Memory:** `ramKilobytes` gives the II or II Plus 16, 32 or 48 KB (the default) on the board.
- **II:** Integer BASIC and, as `monitor` says, the `original` Monitor (the default),
  whose reset stops at its `*` prompt (CONTROL-B starts Integer BASIC), or the
  `autostart` Monitor of later IIs. `"boardRevision": 0` gives the first boards' hi-res,
  which ignores bit 7: black, white, green and violet, without orange and blue.
  `"programmersAid": true` puts Programmer's Aid #1 in its D0 socket ($D000-$D7FF), from
  the dumps or the SDK's source, so `CALL -12288` starts its hi-res graphics and stepping
  into it shows the source.
- **Slot 0** (`slot0`): the II Plus has a `languageCard` (16 KB of RAM at $D000-$FFFF)
  unless it says `empty`; the II has nothing unless it says so. A `firmwareCard` holds
  the other model's BASIC and Monitor in ROM, AppleSoft on a II and Integer BASIC on a II
  Plus, from `firmwareCardRoms` or the other model's dumps; $C080 selects it and $C081
  the board's ROM, as DOS 3.3's FP and INT do. Without the other model's dumps, the card
  holds the SDK's build of them. The Retro Devices view's **Add Card** puts either card in.

On a II running Integer BASIC, or a II Plus with its Integer BASIC firmware card, a
`basic` launch takes an Integer BASIC file (named `.integer.bas`, or with
`REM retrocore integer` as its first line): it is tokenized exactly as Integer BASIC's
ROM would, a line its grammar refuses fails the launch with its message, and the program
goes into memory and runs on the BASIC thread, as AppleSoft does. The thread follows
whichever BASIC is in memory, so Integer BASIC that DOS 3.3's INT loads into a language
card debugs the same way.

With `"dos": "3.3"` or `"3.2"`, a launch runs its program under DOS instead of loading it
into memory: the program goes on a fresh DOS disk, built from the SDK's DOS sources, as a
binary file named after the source, with a HELLO that BRUNs it. The IIe boots the disk
from a Disk II in slot 6 (the 13-sector card for DOS 3.2), and breakpoints in the program stop once DOS has run it. BRUN
starts a binary at its first address, so the program must too. `dosYear` picks the 1983
DOS (the default) or the 1980 one. [Dos.md](../docs/Dos.md) explains DOS and its sources.

The `retrocore` debugger steps through source in every dialect. A launch
configuration with `source` assembles a native, ca65 or Merlin file with retrocore
(`dialect` selects the front end, `linkerConfiguration` an ld65-style config),
loads each section at its address, and starts at `entryAddress` or the first
section; the debugger reads the assembly's source map directly. `program` and
`debugFile` instead load a prebuilt binary with a cc65 `.dbg` file or VICE labels.

SDK ROM sources shipped with the debugger are assembled at launch, each for the
launched model. Today they are:

- the slot-seven block device's firmware;
- AppleSoft II;
- the Monitor;
- the internal $C100-$CFFF firmware;
- the Disk II's 16- and 13-sector boot ROMs, in slot six;
- DOS 3.3 (1983 and 1980) and DOS 3.2, where they run at $9D00, while memory holds their code.

They debug alongside the program. Each module is
tied to the memory it runs from (main or auxiliary RAM, a language-card bank,
internal ROM or a slot ROM), so code at the same address in different memory
never borrows another module's source, and a source line applies only while
memory holds the bytes it assembled to.

Macros debug as inline frames. Stopping on a line that invokes a macro shows that
line; step into moves one macro level inward without running anything, step over
runs the whole invocation, and step out leaves it. The call stack shows a frame
per macro level, named by its invocation, and a breakpoint on a macro body line
stops in every expansion. A module can treat single-statement macros as their
call line, as AppleSoft does, since MACRO-10 sources define instructions as macros.

While debugging, the gutter shows the CPU cycles of each source line's latest
run. Consecutive instructions on one line, such as a macro's, add up.

A `JSR` line also shows its latest call's cycles after the line's text, for
example `⤷ 17c`. That count covers the `JSR`, the subroutine with any calls it
made, and the return to the next instruction. A call whose return address is
discarded, for instance by resetting the stack, shows nothing.

**Retrocore: Clear Source Cycle Counts** clears both.

`Retrocore.Debug --assemble source output.bin` writes the binary and a cc65 `.dbg`
beside it (`--dbg`, `--dialect`, `--cpu`, `--origin $6000` and `--config` are
optional). The library writes the same format through `AssemblyDebugFile.Write`.
For ca65 sources it maps every address and line as ld65 does, including include
files, macro body lines and BSS.

`Retrocore.Debug --pascal catalog disk.dsk` lists the files on an Apple Pascal or
SOS disk, `--pascal extract` copies one out, and `--pascal disassemble` lists a
code file's p-code ([Pascal.md](../docs/Pascal.md#disks-and-code-files)).

`Retrocore.Debug --dos catalog disk.dsk` lists a DOS 3.3 or 3.2 disk's files,
with each binary file's address and length (`--json` for a machine to read), and
`--dos extract disk.dsk "NAME" out.bin` copies one out. `Retrocore.Debug
--disassemble --disk disk.dsk --file "NAME" out.asm` turns a binary file into
native source, or a plain file with `--origin`. It names what the program uses of
the Monitor, firmware, BASIC and DOS by the SDK sources' names (`--machine` and
`--dos` pick whose), takes a `--hints` file of entry points, data ranges, names
and comments, and checks that the source assembles back to the same bytes. The
`retrocore-disassembly` skill describes the whole process.

Included and Merlin `PUT` files map to their own lines, code after `.org` or Merlin `ORG` maps to its CPU addresses, and scoped
labels resolve as `scope::name` as well as by plain name. A relative file name
in an ld65 `.dbg` is looked up beside the sources named with full paths before
beside the `.dbg` itself, since ca65 records includes relative to its working
directory.

### The IIe's display and keys

The **Apple IIe** panel opens beside the editor when a session starts. While paused
it shows the beam's position, and with **Beam overlay** ticked (it starts off, and the
panel remembers it) a red cross where it is drawing; in blanking, where
the beam is off the picture, a dimmer marker at the left edge of its line (horizontal
blanking) or the bottom edge (vertical blanking).

When a session ends, its panel stays with the last picture, dimmed, and says
**Machine off**. **Restart** starts the same launch again, with the cards and disks it
last had; **Start Machine…** picks another; **Close** closes the panel. The next
session's picture replaces it. To have the panel close instead, set
`retrocore.display.onSessionEnd` to `close`.

**Scale: sharp**, the default, draws each dot as a whole number of screen pixels, as
large as fits: 560x384 physical pixels and its multiples on the IIe, 768x576 and its
multiples on the Model I, allowing for Windows display scaling. **Scale: fit** fills
the panel's width instead; sharp falls back to it when the panel is too small for 1x.
The panel remembers the choice.

**Screen** picks the machine's monitor: **Color** on the Apple II family and the Apple
III, or a monochrome monitor of the time, **Black and white**, **Green** or **Amber**, on
any machine. On an Apple II, a monochrome monitor shows every one of the 560 dots on its
own, so double hi-res text and the mouse desktops are sharp instead of smeared into
color; on the others it lights the picture in the phosphor's color. The `screen` launch
option sets where a session starts; once you pick one in the panel, the panel keeps it
for later sessions on machines that have it.

With a mouse card in, a strip under the screen says so. Click the screen to capture
your mouse for it: the strip and the screen's border light up and say **press Esc to
release it**.

**Speed** on the key bar runs the machine at 1x (its real speed), 2x, 4x or 8x its
clock, or Max, as fast as the host can, from the moment you pick it; the `speed`
launch option sets where a session starts. While it runs, the status line shows the
speed the debug host measures, such as `Running · 1.00× · 1.02 MHz`, or at Max how
fast it really goes. Sound plays only at 1x.

**Fast disk**, on by default (the `fastDisk` launch option), runs the IIe as fast as it
can while any Disk II drive's motor turns, then returns to the chosen speed; the
status line says `Fast disk` while it does. The machine runs the same cycles either
way, so copy protection that times the disk still works; only the real time
shrinks. At 1x, the DOS 3.3 System Master boots in about 3 seconds instead of 12,
and `CATALOG` takes 0.2 seconds instead of 1.4. Sound goes quiet while it's fast,
and slot 7's block storage is instant already. On the Model I, the fast cassette
does the same while the tape motor turns (`Fast tape`). Click the screen
to type into the machine. While it has focus, its keys go only to the machine, so
Ctrl+P is CONTROL-P rather than Quick Open; function keys (the debugger's F5, F10
and F11) and Ctrl+Shift+P still reach VS Code, as does Cmd on a Mac. The keys that
aren't letters:

| Key on the IIe | In the panel | On the key bar |
| --- | --- | --- |
| CONTROL with a key | **Ctrl** with a letter or `@ [ \ ] ^ _` | **Ctrl**, then the key |
| CONTROL-C (stops a BASIC program) | **Ctrl+C** | **Ctrl-C** |
| CONTROL-RESET | **Ctrl+F12** or **Ctrl+Break** | **Ctrl-Reset** |
| Open Apple | hold **left Alt** | **Open Apple** stays down until clicked again |
| Closed Apple | hold **right Alt** | **Closed Apple** likewise |
| ESC, TAB, DELETE, arrows, RETURN | **Esc**, **Tab**, **Delete**, arrows, **Enter** | **Esc** |

To paste, right-click the screen and choose **Paste**, or press **Shift+Insert**.
This works on every machine. The clipboard's text is typed into the machine as if
you typed it, waiting for the program to read each key, so a pasted BASIC listing
enters line by line. On the Apple II and the Apple III keys go in at a typist's pace,
with a pause after each line, so a program with its own type-ahead, such as Apple
Pascal's Editor, doesn't lose them as it scrolls. Each line ending is RETURN. Typographic quotes, dashes and
ellipses become their ASCII forms. Control characters and anything else without a
key are left out. The II Plus types capitals, as its keyboard does. **Ctrl+V** is
CONTROL-V, like any other Ctrl letter, and doesn't paste.

Open Apple with CONTROL-RESET restarts the machine, as on the real keyboard, and
Closed Apple runs the self-test. This works even when the debugger stops at the
reset and you let go of the keys: an Apple key that is down at a reset stays down
for a tenth of a second of the machine's running time, long enough for the firmware
to read it. A
CONTROL-C takes the place of any typed key the program hasn't read yet, since BASIC
checks for it without reading other keys.

A game controller (Xbox, PlayStation, Switch Pro and most others) is the Apple
joystick while the machine runs, even with VS Code in the background: its left
stick or d-pad moves paddles 0 and 1, and A, B and X (Cross, Circle and Square)
press buttons 0, 1 and 2. A second controller is paddles 2 and 3. The Retro Devices
view's **Game port** row names the controllers it sees, and the launch option
`"controllers": false` turns them off.

The panel plays the IIe's sound while it runs. The `sound` launch option sets what
you hear, and the key bar's **Sound** button changes it during the session:

| `sound` | You hear | Emulation cost |
| --- | --- | --- |
| `off` | nothing | none |
| `speaker` (the default) | the IIe's speaker, in mono | about 2% |
| `mockingboard` | the speaker and the Mockingboard's two sound chips, in stereo | about a quarter, as the chips' output is worked out every cycle |

The Mockingboard is a card in slot 4, and a launch leaves it out unless `sound` is
`mockingboard` or `mockingboard` is `true`; `"mockingboard": false` keeps it out even
then, and you hear the speaker. The Retro Devices view's **Add Card** puts it in
during a session. The **Sound** button offers the Mockingboard only while it is in,
and taking it out goes back to the speaker.

Sound plays in time only at the machine's real speed (`speed` 1, the default);
running faster, the panel drops sound rather than fall behind. Browsers start audio
only after a click or key, so if the button says to, click the screen.

The key bar's **Volume** slider sets how loud it plays, 50% to start; the panel
remembers it while it stays open.

## Debugging on the Apple III

`"machine": "apple3"` debugs an Apple III: `ramKilobytes` (128, 256 or 512), `disks` for
.D1-.D4, `fastDisk` and `sound`. The boot ROM is `apple3.rom` from `romDirectory` or
`RETROCORE_APPLE3_ROMS`, or else assembled from the SDK's `BootRom.asm`, which is
byte-identical to it and debugs as a ROM module. Memory references can name a bank:
`system`, `bank0` and up, `rom`, or an X-byte such as `x81` for SOS's extended
addresses. See [the Apple III guide](../docs/Apple3.md).

## Debugging on the TRS-80 Model I

`"machine": "trs80-model1"` debugs a Model I with the same source debugging, call
stack, cycle counts and `Keeps:` checks; a Z80 `CALL` or `RST` line shows its latest
call's cycles as a `JSR` line does. The machine is configured by:

- `rom`: `level2` (the default) or `level1`;
- `revision`: Level II `1.3` (the default) or `1.2`;
- `ramKilobytes`, `expansionInterface`, `diskController`, `lowercase` and `doubler`
  (`percom` for NEWDOS/80's double density, `tandy` for Radio Shack's, or `both`);
- `characterGenerator`: `stock`, or `kit` for the Radio Shack lowercase kit's font
  (the default with `lowercase`);
- `snow`, which shows the video snow of CPU access to video RAM;
- `cassette` (a `.cas` tape to play), `fastCassette` (on by default: run
  unthrottled while the cassette motor runs) and `disks` (JV1, or JV3 with a
  `.jv3` extension, for drives 0-3).

The ROMs are dumps from `romDirectory` or `RETROCORE_TRS80_ROMS`, under MAME's names
(`rom-a.z1`-`rom-c.z3` for 1.2, the `_alt` parts for 1.3, `level1.rom` and
`mcm6670p.z29`). Without dumps they are assembled from the SDK's sources, which are
byte-identical to them, so the Model I needs no external files. Those sources
(`Level2.asm` or `Level1.asm`) also debug as ROM modules, so a breakpoint in a ROM
routine stops there, and stepping into a ROM call from a program goes into its source.

A program (`source` or `program`, loaded at `$7000` by default) runs after the ROM
has booted for `bootSeconds` (1 by default), so the ROM's RAM vectors and device
control blocks are set up for its ROM calls; [the sample](../sample/trs80/hello.asm)
prints through `DISPLAY_CHAR`. Running keeps to the machine's real speed unless
`speed` says otherwise.

The panel shows the 64x16 display (32 columns in wide mode) and takes keys: arrows,
**Home** for CLEAR, **Escape** for BREAK and **Ctrl+F12** or **Ctrl+Break** for the reset button,
which is also **Reset** on the key bar. The reset button boots a disk when there is
a disk controller, and otherwise restarts BASIC with the program kept. **TRS-80: Insert Cassette…**, **Record
Cassette…** and **Eject Cassette** handle tapes (a recording is saved when ejected),
and **TRS-80: Insert Disk…** and **Eject Disk…** handle drives 0-3, through the
debug host's `retro/media` request.

## Debugging on the Apple-1

`"machine": "apple1"` debugs an Apple-1 with the same source debugging, 6502 call
stack, cycle counts and `Keeps:` checks. The machine is configured by:

- `ramKilobytes`: 4 (the default) or 8 from `$0000`;
- `highRam`: the 4 KB bank at `$E000` where BASIC loads and runs (on by default);
- `cassetteInterface`: the Apple Cassette Interface, started with `C100R` (on by
  default);
- `cassette` (a `.wav` tape, which plays from the start of the session) and
  `fastCassette` (on by default: run unthrottled while a tape plays or records);
- `loadBasic`: Apple-1 BASIC in the `$E000` bank at power-on, as if its tape had
  been loaded, so `E000R` starts it (on by default with `highRam`).

The Monitor, the cassette interface's PROM and BASIC are `wozmon.bin`, `aci.bin` and
`basic.bin` from `romDirectory` or `RETROCORE_APPLE1_ROMS` when they are there.
Otherwise they are assembled from the SDK's sources, as the terminal's character
generator always is, so the Apple-1 needs no external files. `WozMonitor.asm` and
`Aci.asm` also debug as ROM modules: a breakpoint on `ECHO` stops as each character
goes to the screen. So does Apple-1 BASIC's `Basic.asm`, while BASIC is in memory.

A `basic` launch runs an Apple-1 BASIC file: `.apple1.bas`, or a `.bas` whose first
line is `REM retrocore apple1`. It starts BASIC, puts the program in and types `RUN`,
and the **BASIC** thread debugs it by statement, as on the other machines: breakpoints
and stepping in the file's lines, GOSUBs in the call stack, the variables and FOR
loops, and the program in memory as text. A key typed while the program runs stops
it, as on the machine; **Program stops** reports that as `A key in` its line.

A program (`source` or `program`, loaded at `$0300` by default) runs after the
Monitor has set up the PIA, so it can print through `ECHO` ($FFEF) and return to the
Monitor with `JMP $FF1F`.

The panel shows the 40x24 terminal, which takes about 60 characters a second as the
real one does. **Backspace** types the back arrow (`_`), **Escape** ESC, and
**Ctrl+F12** or **Ctrl+Break** RESET; the key bar has **Esc**, **Reset** and **Clear
Screen**. Letters arrive as capitals. Tapes go in and out from the cassette's row in
[Retro Devices](#retro-devices); a recording is saved as a WAV file when it is
ejected.

## Debugging on the TRS-80 Color Computer

`"machine": "coco"` debugs a Color Computer 1, 2 or 3, chosen by `model` (`coco1`,
`coco2`, the default, or `coco3`), with the same source debugging, call stack, cycle
counts and `Keeps:` checks; the call stack follows `JSR`, `BSR`, `LBSR`, `SWI` and
interrupts on the 6809's S stack. The machine is configured by:

- `ramKilobytes`: 4, 16, 32 or 64 on a CoCo 1 or 2, 128 or 512 on a CoCo 3;
- `colorBasic` and `extendedBasic`, the CoCo 1 and 2's ROM versions;
- `lowercase` (the MC6847T1 VDG), `artifacts` (`blue-red`, `red-blue` or `none`)
  and, on a CoCo 3, `monitor` (`composite` or `rgb`);
- `cartridge` and `autostart`, a ROM pack;
- `diskController`, `diskBasic` and `disks` (JVC `.dsk` images for drives 0-3);
- `cassette`, `fastCassette` and `sound` (`speaker` or `off`).

Color, Extended and Disk BASIC are the SDK sources `ColorBasic.asm`, `ExtendedBasic.asm`
and `DiskBasic.asm`, and the CoCo 3's ROM is those with its patches and `Coco3.asm`, so
every model needs nothing else, disk controller included, and debugging steps into the
sources, on a CoCo 3 in the copy of its ROM it runs from RAM. Dumps from `romDirectory`
or `RETROCORE_COCO_ROMS`, under MAME's names (such as `coco3.rom`), replace the sources'
ROMs when given. A program
(`source` or `program`, loaded at `$3000` by default) runs after BASIC has started for
`bootSeconds` (2 by default); [the sample](../sample/coco/hello.asm) prints through
Color BASIC's `CHROUT` vector.

The panel shows the screen and takes keys: arrows, **Home** for CLEAR, **Escape** for
BREAK and **Ctrl+F12** or **Ctrl+Break** for RESET, which are also on the key bar. The
TRS-80 cassette and disk commands work as on the Model I. See the
[Color Computer guide](../docs/Coco.md) for what is emulated.

## Debugging on the TRS-80 Model III, 4 and II

`"machine": "trs80-model3"` debugs a Model III, 4 or 4P (`model` `3`, `4` or `4p`;
`"trs80-model4"` is the Model 4), and `"machine": "trs80-model2"` a Model II, 12 or the
Z80 side of a Model 16 (`model` `2`, `12` or `16`). Without dumps they run the SDK's
builds of their ROMs (`Model3.asm`, `Model4PBoot.asm`, `Model2Boot.asm` and the character
generators), which are byte-identical to MAME's; `romDirectory` or `RETROCORE_TRS80_ROMS`
can hold MAME's dumps instead. When the running ROM is one the sources build, its source
debugs as a ROM module, and Model III and Model 4 BASIC has the BASIC thread, as Level II
does. The options are `ramKilobytes`, `disks` (JV1, JV3, DMK or IMD),
`diskController`, `cassette` and `fastCassette` (Model III and 4), `fastDisk` and
`bootRom` (Model II), `bootSeconds`, `screen` and `speed`. On the Model III family the
panel takes the Model I's keys; on the Model II it types ASCII, with **Escape** for
BREAK and buttons for HOLD, F1 and F2. See the
[Model III, 4 and II guide](../docs/Trs80Model3And2.md) for what is emulated.

## Breakpoints

Breakpoints work in `retrocore-asm` and `asm` files, and every kind in VS Code's
Breakpoints view is supported:

- **source** breakpoints in the gutter, in your program and the SDK's ROM sources;
- **function** breakpoints on a label or address expression, such as `DISPLAY_CHAR`
  or `$C600`, a scanline such as `scanline 192:0`, an Apple III SOS call such
  as `sos OPEN`, or an Apple Pascal procedure such as `pascal HELLO.2`;
- **instruction** breakpoints in the Disassembly view, which shows each
  instruction's bytes, label and source line;
- **data** breakpoints that watch memory, or a Z80 I/O port, for reads, writes or
  both, from the Variables view, a watch expression such as `[$0400]`, or **Add
  Data Breakpoint at Address**;
- **exception** filters: **Machine reset** (on by default) stops as the machine
  powers on and at each reset after; others stop at a 6502 `BRK` (on the Apple III,
  one that is not an SOS call), the video beam reaching a scanline, broken
  `;; Keeps:` contracts, and BASIC's program start, errors and program end.

Each can have a condition (`A == $0D`), a hit count (`5`, `>=5` or `%5`) and, apart
from data breakpoints, a log message (`char {A,c} at {HL}`), which writes to the
Debug Console instead of stopping. On the Apple III, `{sos}` describes the SOS call,
so `sos` with the message `{sos}` traces every call. A breakpoint's hover shows how often it has been
hit. **Retrocore: Show Breakpoint Hit Counts** and **Reset Breakpoint Hit Counts**
are in the Breakpoints view's title bar. Stepping over a call stops at a breakpoint
inside it, and the Disassembly view steps by instruction.

A launch configuration's `breakpoints` can carry `condition`, `hitCondition` and
`logMessage`, and `{ "function": "DISPLAY_CHAR" }` adds a function breakpoint. Logpoints write at most
`logpointLimit` lines a second (100 unless the launch configuration says otherwise, 0 for no limit) and report
how many they dropped.
[Breakpoints.md](../docs/Breakpoints.md) describes the expression syntax, what each
kind watches and the protocol.

## Memory

Memory opens in Microsoft's Hex Editor from the binary-data icon on any variable or
watch that holds an address, or from **Retrocore: Open Memory...** in the Variables
view's title bar. You can edit bytes there, and open views refresh at each stop and
while the machine runs. Eclipse CDT Cloud's Memory Inspector works too.

The IIe's soft switches map one address to several stores, so a memory reference
can name a bank: `main`, `aux`, `bank1`, `auxbank1` (the language cards' bank 1),
`rom`, and `slot1` to `slot7` while those slots' cards have ROMs. `aux:$0400` is auxiliary
RAM's text page whatever the switches map, and `[aux:$0400]` reads it in
expressions, conditions and data breakpoints. A function breakpoint such as
`bank1:$D000` stops only while the CPU runs that bank's code. The
Variables view's **Memory** scope lists each bank with where the switches map it
now. [Memory.md](../docs/Memory.md) describes memory references, banks and the
protocol.

## BASIC programs

**Retrocore: Open BASIC Program** opens the BASIC program in the running machine as
text: AppleSoft on the Apple II Plus and IIe, Integer BASIC on the II, Level II on the
Model I, and Color BASIC on the Color Computer 1 and 2, with Extended and Disk
Extended Color BASIC's words when their ROMs are fitted. Level I and the CoCo 3's
BASIC are not supported yet. It is in three places besides the Command Palette:

- the **BASIC program** button on the machine panel's key bar;
- the **BASIC program** row at the top of the Retro Devices view, which shows the
  dialect and how many lines the program has; click it, or its Open button;
- a `basic` launch, which opens the editor by itself once the program is in memory.

- **Saving** tokenizes the text exactly as the machine's ROM would if you typed it,
  writes it into memory, and clears the variables, as typing a line does. Lines
  that don't tokenize are listed in the Problems view, and nothing is written. If a
  program is running, BASIC goes back to its prompt with the new program, as it does
  when you edit a line; RUN it again.
- **The editor follows the machine.** A line typed on the emulated screen, a LOAD
  or CLOAD, or a program that changes itself shows up in the editor. If the editor
  has unsaved edits, you choose **Keep Mine**, **Take the Machine's** or
  **Compare**.
- **Import** and **Export** are in the editor's title bar. They cover text listings
  (`.bas`), tokenized programs as BASIC stores them, and on the Model I, CSAVE tapes
  (`.cas`). An exported AppleSoft program is named in CiderPress2's form, such as
  `PROGRAM#fc0801`.

When the session ends, an editor with no unsaved edits closes. One with edits
becomes an unsaved copy, and a message offers **Save As…**, so nothing typed is lost.

Characters a text file can't show are written as escapes: `{CTRL-D}` for a control
character, `{$84}` for any byte, and `{{` for a brace.

### The BASIC thread

A session running AppleSoft, Integer BASIC, Level II or Color BASIC has a **BASIC**
thread beside the CPU's.
Its call stack is the statement running, then each GOSUB in progress at the
statement that called it; it shows **BASIC: ready** at the prompt.

- **Breakpoints** in the machine's program stop at a line's first statement; an
  inline breakpoint (Shift+F9) stops at a later one. Conditions are BASIC
  expressions, such as `I>10 AND A$="Y"`, and log messages interpolate
  `{BASIC expression}`. They stay on their BASIC lines as the program changes: a
  line typed above moves them down, and a deleted line takes its breakpoint with
  it. When the program goes (NEW, a restart, another program loaded, or the end of
  the session), so do its breakpoints.
- **Step Over**, **Step Into** and **Step Out** go by statement: Over runs a GOSUB
  without stopping in it, Out runs to the statement after its RETURN, and Into on a
  CALL, USR or `&` stops at the machine code's first instruction. In Integer BASIC
  an IF's THEN statement is one statement; the statements after the next colon run
  either way, so a step goes to them.
- **Pause** stops at the next statement. **Jump to Cursor** (Set Next Statement)
  moves the program to another statement, as GOTO would.
- **Exception filters** in the Breakpoints view: **BASIC program start** (on by
  default) stops at the first statement RUN runs and where CONT resumes; **BASIC
  errors** (on by default) at errors no ONERR GOTO or ON ERROR GOTO will take;
  **Handled BASIC errors** at those they will; and **BASIC program end** at STOP,
  END, the end of the program and Ctrl-C or BREAK. Integer BASIC and Color BASIC
  have no error handler, so their errors, such as `*** BAD BRANCH ERR` or `?UL ERROR`,
  always stop.
- **Variables:** a BASIC frame has **Variables**, **Arrays** (each expanding to its
  elements), **Functions** (AppleSoft's DEF FN), **Loops** (the FOR loops in
  progress) and **Program** (where the program, variables, arrays and strings are).
  Set Value takes a BASIC expression and writes it as BASIC stores it; a string goes
  into string space. Watches, hovers and the Debug Console evaluate BASIC
  expressions without running BASIC, and **Break When Value Changes** on a variable
  stops after the statement that changes it.
- **Integer BASIC's variables** are 16-bit integers, -32767 to 32767, with names of any
  length; an array runs from element 0 to its DIM, and a string holds what its DIM
  gave room for. Expressions follow Integer BASIC: `/` drops the remainder, `MOD`
  and `#` (not equal) work, a comparison is 1 or 0, and `A$(2,4)` is characters 2 to
  4. Its Program scope shows its variables from LOMEM, and its program up to HIMEM.
- **Color BASIC** finds reserved words only in capitals, and never inside a name: a
  name runs from a capital through the letters and digits after it, so `IFA=BTHEN10`
  compares A with the variable BTHEN10. GOTO and GOSUB are stored as GO and then TO or
  SUB, and its numbers and pointers are high byte first, as the 6809 keeps them.

### BASIC files

`.applesoft.bas`, `.integer.bas`, `.apple1.bas`, `.business.bas`, `.level2.bas` and
`.colorbasic.bas` files are AppleSoft, Integer BASIC, Apple-1 BASIC, Business BASIC,
Level II BASIC and Color BASIC. Business BASIC takes a reserved word only between
separators, so its highlighting leaves `PRINTER` a name, and its names count in full,
dots included. A Color BASIC file may use every word of Disk Extended Color BASIC; a
machine without those ROMs stores the words they add as letters. A plain `.bas` file
takes its dialect from a first line such as `REM retrocore applesoft` or
`' retrocore level2`, else the `retrocore.basic.dialect` setting, else the BASIC of
the machine being debugged.

A file may leave out line numbers and use labels: a line of its own, `name:` or
`@name`, names the line after it, and `GOTO name`, `GOSUB @name`, `THEN name` and
the like use it. Lines without numbers are numbered after the line before them, in
steps of 10 or of the pragma's step (`REM retrocore applesoft step 5`); a numbered
line keeps its number, and indentation is only in the file. Integer BASIC's GOTO and
GOSUB take expressions, so there a name is a label only when one of that name is
defined; `GOSUB T` with no label T goes to the line in the variable T.

```basic
' retrocore level2
    CLS
loop:
    A = A + 1
    IF A < 3 THEN loop
    GOSUB @show
    END
@show
    PRINT "DONE"; A
    RETURN
```

A launch configuration's `basic` names a file to debug: the machine boots to BASIC's
prompt, the file is compiled into memory and RUN (`"run": false` leaves it at the
prompt), and `stopOnEntry` stops on its first statement. While the program in memory
is what the file compiles to, its frames, breakpoints, inline breakpoints and Jump to
Cursor are in the file itself, labels and all. On the Apple III, a `.business.bas` file
(or one with `REM retrocore business`) needs the Business BASIC disk in `disks`, which
**Retrocore: Start Machine** asks for: SOS boots it, BASIC runs the disk's HELLO, and the
program goes in once BASIC is at its prompt. BASIC files, the machine's program and opened listings
get:

- highlighting that finds reserved words where the ROM does, inside names too;
- problems: jumps to lines that don't exist, names BASIC splits around a reserved
  word (`SCORE` is `SC OR E`), another dialect's words, and lines too long to type;
  for Integer BASIC, also each line its grammar refuses, as `*** SYNTAX ERR` at the
  place its tokenizer stopped;
- hover help for every reserved word, and for variables, which names BASIC treats
  as the same variable (it keeps only two letters);
- go to definition and find all references for line numbers, variables and `FN`;
- completion of keywords, variables, and line numbers after `GOTO` and the like;
- an outline of REM-headed sections and the subroutines GOSUB calls.

**Retrocore: Renumber BASIC Program...** renumbers the lines and every reference to
them. **Retrocore: Open as BASIC Listing** (also on the Explorer's context menu for
`.cas` and CiderPress2 `#fc` and `#fa` files) opens a tokenized program or a Model I
tape as text; saving writes it back in the same form.

Integer BASIC checks a line's grammar as it is typed and gives one word a different token
for each place in its grammar, so Retrocore tokenizes Integer BASIC by running the
ROM's own matcher over the ROM's syntax tables, in C#: the bytes are the ones typing
the line would store, with no machine running. A test holds it to the ROM's own
tokenizing and to every program on the 1980 DOS 3.3 System Master. A listing types
back the same program, but for what typing cannot make: a constant RENUMBER changed
keeps the first digit it was typed with, which nothing reads, and a quote inside a
string shows as `{$A2}`.
[BasicDebugging.md](../docs/backlog/BasicDebugging.md) is the plan for the rest of
BASIC debugging.

## Retro Devices

With no session running, the **Retro Devices** view in the Run and Debug sidebar
offers **Start Machine** ([Starting a machine](#starting-a-machine)). While a
Retrocore session runs, it lists the machine's installed hardware and, under each part, its devices.
On the IIe that's the model, memory, the extended 80-column card every launch has,
and slots 1 to 7, empty ones included: the Mockingboard in slot 4, the Disk II and
its drives in slot 6, and block storage in slot 7 when the launch installs them. On
the Model I it's the ROM, memory, cassette, Expansion Interface, disk controller
with its drives, and the lowercase modification. Hovering a row says which launch
option installs or changes it.

On the IIe, a free slot's **Add Card** button puts a Disk II controller there
(16-sector, or 13-sector for DOS 3.2), even while the machine runs: `PR#5` boots it,
and a reset's startup scan finds it. Its two drives take disks like any other, and
**Remove Card** takes it out again, asking first if it has disks in. Slot 4 also
takes the Mockingboard; slot 3 belongs to the 80-column firmware. Any free slot
takes the mouse card (one per machine), as the `mouse` launch option does: click the
display to move it with your mouse, and press Escape to let go. Any free slot also takes
a ProFile card, as the `proFiles` launch option does, with Apple's ProFile hard disk:
insert a `.po` or `.hdv` image in its drive, and ProDOS boots it and lists it. On the
Apple III, slots 1 to 4 take ProFile cards, which SOS reaches through `.PROFILE`.
Any free Apple II slot also takes the 3.5 disk controller (one per machine), as the
`disk35` launch option does: a SmartPort with two SuperDrives that answers as Apple's
Apple II 3.5 Disk Controller Card, for 400K and 800K Apple disks and 720K and 1.44 MB
MFM disks (`.po`, `.2mg`, `.hdv`, `.img` or `.dsk`). `disk35Images` names the disks
in its drives; drive 1 boots, so `"disk35": 5` with an 800K ProDOS disk starts ProDOS
from it.

Each launch configuration remembers its machine. The cards you add or remove and
the disks and tapes you insert, eject or write-protect come back the next time you
launch the same configuration, by its `name`. launch.json stays as written: it sets
up the first launch, and changing one of its hardware or media options (such as
`diskImage`, `dos`, `model` or `mockingboard`) starts that configuration afresh.
**Retrocore: Reset Saved Machine** (also on the view's **...** menu) does the same by
hand. A disk a `dos` launch builds, and a tape being recorded, are not remembered;
the launch makes them again. Each device shows its media, its
track, side and sector or its tape position, whether it is write-protected or
changed, and whether it is seeking, reading or writing. Expanding a device lists
its state and what it is (its controller, formats and geometry). Its inline
buttons insert, record, eject and write-protect, as the device allows. What the
machine writes to an Apple disk stays in memory until you save it: **Save to Its
Image** (the disk icon on a changed drive) replaces the image it came from, after
asking, and **Save Disk As...** in its menu writes a `.woz`, `.dsk`, `.do` or `.po`.

[Devices.md](../docs/Devices.md) describes the device model and the
`retro/devices` and `retro/device` requests behind the view.

## Themes and optional colors

The grammar supplies scopes; your current theme selects their colors. Standard
`keyword`, `entity.name`, `variable`, `constant`, `string` and `comment` scope
families make the grammar work with existing themes. No theme or fixed colors
are installed or forced.

Use **Developer: Inspect Editor Tokens and Scopes** to inspect a token and the
theme rule that colors it. For additional contrast, the following is an
**optional** dark-background palette. Copy only the rules you want into your
settings and adjust the colors for your theme:

```json
{
  "editor.tokenColorCustomizations": {
    "textMateRules": [
      {
        "scope": "keyword.other.opcode.retrocore",
        "settings": { "foreground": "#569CD6" }
      },
      {
        "scope": "keyword.control.flow.retrocore",
        "settings": { "foreground": "#C586C0" }
      },
      {
        "scope": "keyword.control.directive.retrocore",
        "settings": { "foreground": "#C586C0" }
      },
      {
        "scope": "entity.name.label.retrocore",
        "settings": { "foreground": "#DCDCAA", "fontStyle": "bold" }
      },
      {
        "scope": "variable.other.constant.definition.retrocore",
        "settings": { "foreground": "#4FC1FF" }
      },
      {
        "scope": "variable.other.symbol.retrocore",
        "settings": { "foreground": "#9CDCFE" }
      },
      {
        "scope": "variable.language.register.retrocore",
        "settings": { "foreground": "#D7BA7D" }
      }
    ]
  }
}
```

Other useful scopes are `constant.language.processor.retrocore`,
`entity.name.type.retrocore`, `constant.numeric.hex.retrocore`,
`constant.numeric.binary.retrocore`, `constant.numeric.decimal.retrocore`,
`string.quoted.single.retrocore`, `string.quoted.double.retrocore` and
`comment.line.semicolon.retrocore`.

## Building and tests

```powershell
npm ci
npm run compile
npm run test:grammar
npm run test:language
```

`compile` regenerates [the TextMate grammar](syntaxes/retrocore.tmLanguage.json)
using [the generator](scripts/generate-grammar.mjs) and the canonical
[CPU definitions](../src/Retrocore.Cpu.M6502/OpcodeTables.txt), then compiles TypeScript.
Do not hand-edit the generated grammar. The generator expands inherited CPU
maps and numbered bit operations and rejects incomplete or duplicate definitions.
`test:grammar` rejects stale output and uses VS Code's TextMate/Oniguruma engines
to test scopes, not a JavaScript approximation of the patterns.

`test:language` launches an isolated VS Code extension-development host and checks
language registration/detection without a debug session, word selection,
comment toggling and bracket navigation. It needs VS Code but no ROMs or .NET
build. Set `RETROCORE_VSCODE` to override the test host executable path.

`npm test` builds and runs both tokenization and the full debugger integration
tests, which include booting the Model I to Level II's READY. The full integration suite also needs
`RETROCORE_IIE_ROMS`, a built Release debug host and the existing sample binary/debug
metadata. It checks source breakpoints with a `retrocore-asm` document alongside the
existing call-stack, video, cycle and beam behavior, and a function breakpoint's hit
count on the Model I, and reads and writes memory through VS Code's debug memory file
system. `node tools/Test-Breakpoints.mjs` checks every breakpoint kind through the
debug host directly, and `node tools/Test-Memory.mjs` its memory views and banks.

## External assembler reference tests

The .NET `Ca65DifferentialTests` run the cached `ca65` and `ld65` executables from
`%USERPROFILE%\Retrocore\m1-dependencies\cc65-source\src`. Set `RETROCORE_CC65` to use
another directory containing both tools. Tests are inconclusive when either tool
is absent; they never download tools or source corpora. An installed toolchain's
assembly or link failure is a test failure, not a skip.
The cached checkout's sibling `cfg` directory is passed to ld65 explicitly, so
`-t none` also works with the locally compiled executables.

```powershell
dotnet test tests\Retrocore.Tests -c Release --filter FullyQualifiedName~Ca65DifferentialTests
```

The harness compares file bytes and linked symbols, using the debugger's `.dbg`
parser. It builds the actual [IIe sample](../sample/iie/main.s) with its
[linker config](../sample/iie/link.cfg), matching
[Build-IIeSample.ps1](../tools/Build-IIeSample.ps1), and also exercises the built-in
`none` target. Each reference build uses an isolated temporary output directory,
which is removed after reading the results.

`Ca65FrontendTests` also compiles the unchanged IIe sample through the ca65 front
end and linker. Its optional corpus test expects all 37 `.s` files from the
rom4x/rom5x checkout at `N:\repos\rom4x`, or `RETROCORE_CA65_CORPUS`. It compares every
file byte, masking only source-mapped four-byte `.time` payloads. The included
XMODEM fragment uses its STANDALONE mode and the checkout's platform definitions;
the external sources are not modified or vendored.

Scope tests assemble the same source with ca65 and with the native assembler and
compare the bytes, covering qualified-namespace binding, cheap-local contexts and
the separate symbol and scope namespaces. A reference-only test also pins ca65
byte-extraction precedence for the ca65 front end.
