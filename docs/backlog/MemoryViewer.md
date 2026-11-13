# Backlog: a memory viewer and editor

Status: **step 1 built** ([Memory.md](../Memory.md#retrocore-memory)), with the debug host's `retro/memory/read`
reading past a bank's gaps. Before it, memory opened in Microsoft's Hex Editor through VS Code's debug memory file
system. That works, but the Hex Editor knows nothing about the machine: not its labels, its banks, its character
sets, which bytes are code, or what a byte means. This plan adds Retrocore's own memory editor, with the Hex Editor
as its baseline, that shows assembly at any address and says what the bytes under the cursor are.

## What others do

| Tool | What it does well |
| --- | --- |
| **VS Code Hex Editor** (the baseline) | A virtualized hex and text grid; overwrite editing with undo; go to offset; find and replace in hex, text or regex; a data inspector for the selection (signed and unsigned 8 to 64 bits, either byte order, floats, UTF-8, binary); a column-width setting. It reads through the debug memory file system, so it refreshes on `memory` events. |
| **Visual Studio memory window** | An address that is an expression, re-evaluated at each stop (follow `ESP`); four windows at once; changed bytes in red; columns of 1, 2, 4 or 8 bytes as hex, signed, unsigned or float. |
| **Eclipse CDT Memory Inspector** | Several views side by side, each pinned or following an expression; a column naming the variable that owns each byte; groups by word size and byte order; storing a range and comparing it later; import and export as Intel HEX. |
| **WinDbg, x64dbg** | Dump panes that follow a pointer into another pane; "follow in disassembler"; pattern search; showing a range as a structure; highlighting a selection's value everywhere it appears. |
| **IDA, Ghidra** | The hex view and the listing are one model, so moving in one moves the other; bytes are code, data or unexplored, and the user changes which; data types and structures laid over memory; cross-references to any address. Ghidra's byte viewer shows several formats side by side. |
| **ImHex, 010 Editor** | Patterns or templates that lay named structures over bytes and color them; a data inspector; bookmarks; diffing two buffers; an entropy and value overview of the whole file. |
| **Mesen** (NES, SNES) | Bytes colored by their last read, write and execute, fading with time; code and data known from a code/data log; labels in the grid; freezing a byte; a memory type picker (CPU, PRG ROM, work RAM, video RAM); setting breakpoints from a selection. |
| **C64 Debugger, Altirra** | The whole 64K as a picture, each pixel lit by reads and writes as they happen, clicked to jump there. |
| **MAME debugger** | Any address space (program, data, I/O) and logical or physical addresses; chunk sizes; floats; an expression as the address. |
| **VICE monitor, AppleWin** | Bank selection (RAM, ROM, I/O) for every command; memory as hex with Apple text or PETSCII; hunt, compare, fill and transfer; dump as text the monitor can read back. |
| **BizHawk, Cheat Engine, Stella** | Memory domains; RAM search (find the bytes that changed, stayed, rose or fell since a snapshot), a watch list of what was found, and freezing values. |

What Retrocore can add that most of them cannot: the SDK's ROM sources, with their `;;` doc comments, name nearly
every byte the firmware uses; the assembler's debug files say which bytes are code and which are data, and where
they came from; the analysis engine (`AnalysisEngine`) can separate code from data in memory nobody described; and
each machine target knows its memory map, banks, character set, screen layout and BASIC.

## The editor

A custom editor, **Retrocore Memory**, in a webview, for one memory reference in one debug session. It has
four parts, each of which can be hidden:

```
┌ Map ────────────────────────────────────────────────────────────────────────────────────────┐
│ [zp][stack][text1][text2]  RAM ...........  [hgr1........][hgr2........] ...[I/O][ROM......] │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
┌ Bytes ─────────────────────────────────────────┬ Listing ────────────────┬ Inspector ────────┐
│ 0300 START  A9 C1 20 ED FD 60 00 00  A)m}`..  │ START  LDA #'A'         │ $0302 main RAM     │
│ 0308        C8 C5 CC CC CF A0 A0 A0  HELLO     │        JSR COUT         │ COUT ($FDED), the  │
│ 0310 MSG    ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ········  │        RTS              │ Monitor's output   │
│                                                │ MSG    .byte "HELLO   " │ routine (doc ...)  │
│                                                │                         │ u16 $FDED  65005   │
│                                                │                         │ last write: never  │
└────────────────────────────────────────────────┴─────────────────────────┴────────────────────┘
```

### Bytes

The Hex Editor's grid, kept as people know it: hex and text columns, a virtualized scroll over the whole space,
keyboard and mouse selection, overwrite editing, undo and redo, go to, find, copy. Then:

- **Labels in the gutter**, from the session's symbols (SDK modules, assembled sources, `.dbg` files, VICE labels), so `COUT`
  sits beside $FDED. A row breaks where a label starts when **Align rows to labels** is on.
- **The machine's text.** The text column decodes as the machine shows it: the Apple II's high-bit ASCII with
  inverse and flashing ranges, the Model I's graphics characters, the VDG's inverted lowercase, drawn from the
  machine's own character generator rather than guessed in Unicode. Typing in the text column writes the
  machine's codes, so `A` on an Apple II writes $C1.
- **Code, data and unknown** shade the bytes: what a debug file or analysis says is code, what is data, what no
  one has described. Each instruction's bytes are grouped, so an operand reads as part of its opcode.
- **Read-only bytes** (ROM, a slot's firmware, I/O) are shaded and refuse typing before a write is sent.
- **Changes**: bytes that changed since the last stop are colored, as Visual Studio does; while running, bytes
  that change fade out over a second, as Mesen does.
- **Column groups** of 1, 2 or 4 bytes, shown as hex, decimal or signed, in the CPU's byte order: little-endian
  for the 6502, Z80 and 8080, big-endian for the 6809.
- **Markers** in the gutter: the PC, the stack pointer, breakpoints, data breakpoints and bookmarks.

### Listing

Assembly for any address: the listing pane decodes from the selection, and moving in either pane moves the other.

- **Where to start.** Instruction boundaries are ambiguous in memory nobody described, so the listing starts at
  the nearest known boundary before the selection: a debug file's statement, a label, an analysis result, or
  failing those the selection itself. **Decode from here** (a key and a context menu item) forces a start, as
  every monitor's `L` command does.
- **Code and data.** Statements a debug file marks as data list as `.byte`, `.word` or text, not as nonsense
  instructions. Memory with no debug information runs through `AnalysisEngine` from the known entry points
  (vectors, labels, the PC, call targets) for a code/data guess, shown as a guess. **Mark as code** and **Mark
  as data** on a selection overrule it. **Name** and **Comment** on an address add a label or a comment. All four
  are kept in the session's hints file (decision 6).
- **The CPU's dialect**, as the Disassembly view shows it: 6502, 65C02 on an enhanced IIe, Z80, 6809 or 8080,
  with labels for operands and the source line, when there is one, beside each instruction. Clicking a source
  line opens it; clicking an operand's label goes there.
- **Assemble in place.** Typing over an instruction assembles one line, as the Monitor's mini-assembler does,
  through `Retrocore.Assembler` with the session's symbols, and writes the bytes. If the new instruction is
  shorter, the rest is padded with NOPs after asking; if longer, the editor says what it overwrites.
- **Breakpoints** from the listing's gutter, the same instruction breakpoints the Disassembly view sets.

### Inspector

What the bytes at the cursor or selection are and mean:

- **Where it is**: the address, the bank and what the memory map sends it to now ("auxiliary RAM; ALTZP on"),
  the region it is in ("text page 1, row 3, column 12", "hi-res page 1, row 64, byte 5"), the label it is in
  plus an offset, and the source line that emitted it.
- **What the firmware says about it**: the doc comment of its label from the SDK sources, so selecting $24
  explains `CH`, the cursor's horizontal position, and selecting $C030 explains the speaker.
- **Values**: 8 and 16 bit, signed and unsigned, in either byte order; binary with the bits named for a soft
  switch or flag byte the sources describe; BCD; the machine's text; the BASIC's floating point (AppleSoft's and
  Color BASIC's five-byte, Level II's four- and eight-byte Microsoft formats); a pointer, with **Go to** and its
  label. Each value can be edited in place, which writes the bytes.
- **As an instruction**: the instruction starting here, its size, cycles and flags it changes.
- **History** (with access tracking on, below): the last read, write and execute of the byte, each with the PC
  that did it, its label and the cycle, with **Go to** for the PC.
- **References**: the instructions in code the session knows that read, write or jump to the address.

### Map

A bar across the top for the whole address space, divided into the target's regions (zero page, stack, text and
graphics pages, I/O, slot ROMs, firmware) and colored by what is mapped there now. The visible window is drawn on
it. With access tracking on it becomes a heat map, each address lit by reads, writes and execution, as the C64
Debugger shows it. Clicking goes there.

## Moving around

- **Go to** takes an address, a label or an expression, in a bank or not, as **Open Memory** does today.
- **Follow**: a view can follow an expression, re-evaluated at each stop, such as `PC`, `S+$100`, `HL` or
  `[$06].w`. A pinned view stays put.
- **Back and forward** through go-tos and followed pointers, with the mouse's back and forward buttons.
- **Bookmarks** with names, listed in a quick pick and kept in VS Code's workspace state, since they record where
  someone was looking rather than anything about the program.
- **Find**: bytes (with wildcards), the machine's text, a number in any inspector format, or an instruction
  pattern such as `STA $C0??`.
- **Several views**: each editor is its own view, so two can sit side by side, such as main and auxiliary RAM at
  the same address.

## Opening it

- **Retrocore: Open Memory...** opens Retrocore Memory. It no longer opens the Hex Editor or offers to install it.
- **Open in Retrocore Memory** on the Variables and Watch views' context menu, beside VS Code's binary-data icon,
  which keeps opening the Hex Editor; VS Code decides that one.
- **Reopen Editor With...** switches an open Hex Editor tab to Retrocore Memory and back, since both open the same
  `vscode-debug-memory` URI.
- From the listing of the Disassembly view's address, and from the debug toolbar while stopped.

## Searching and comparing

- **Snapshots**: take one, then show the bytes that differ from it, or compare two banks.
- **RAM search**, as BizHawk and Cheat Engine do: start from all of RAM, then keep the bytes that changed, did
  not change, rose, fell or equal a value since the last snapshot, and narrow until a game's lives counter is
  found. Results go to a watch list, which becomes watch expressions or data breakpoints.
- **Freeze**: hold a byte at a value while running, written back each frame. This is cheap from the debugger's
  frame loop and needs no CPU hook.

## Import, export, copy

- **Copy as** hex, the Monitor's input format (`0300: A9 C1 20 ED FD`), so it can be typed into the machine,
  native `.byte` lines, BASIC `DATA` statements, a C array or base64.
- **Paste** hex text or bytes.
- **Fill** a range with a byte or pattern.
- **Save** a range as a binary, Intel HEX or a native `.asm` disassembly (through the disassembler's exporter);
  **Load** a binary or Intel HEX at an address.

## Structures

Overlays that lay named fields over memory, as ImHex's patterns and Ghidra's data types do, colored in the
bytes and listed in the inspector:

- **Built in**: the stack page, with return addresses found and labeled; the BASIC program, with each line's link,
  number and listing (the dialects already read it); BASIC's variable tables; DOS 3.3's VTOC and file buffers;
  vectors such as $3F0-$3FF and the 6809's at $FFF0.
- **From source**: a `.struct` in a native or ca65 source becomes a type that can be laid at any address.

## Access tracking

The byte history, heat map and fading changes need to know when each byte was last read, written and executed,
and by which PC. That costs time on every bus access, which the core is tuned to avoid
([CoreOptimization.md](CoreOptimization.md)), so it is off until a view asks for it, per address space, and costs
nothing when off. When on, the memory keeps for each byte the cycle and PC of its last read, write and execute.
Whether that is a separate bus path or a hook in the existing one is decided with measurements.

## The debug protocol

Bytes keep coming through `readMemory` and `writeMemory`, so every client and the Hex Editor keep working. The
editor's extras are custom requests, so other clients can use them too:

| Request | Returns |
| --- | --- |
| `retro/memory/map` | The address space's regions, with names, kinds (RAM, ROM, I/O, video), and what is mapped there now. |
| `retro/memory/annotations` | For a range: labels, code/data spans and instruction starts from debug files and analysis, source lines, changes since the last stop and, with tracking on, the access stamps. |
| `retro/memory/inspect` | For an address and length: its region, label and doc comment, the target's interpretations (screen positions, floating point, named bits) and references. |
| `retro/memory/assemble` | The bytes of one line assembled at an address, without writing them. |
| `retro/memory/mark` | Sets a range's code/data kind, or an address's name or comment, in the hints file. |
| `retro/memory/track` | Turns access tracking on or off for a space. |
| `retro/memory/freeze` | Freezes or thaws bytes. |

The listing uses `disassemble`, which already takes banks. The editor watches the session's `memory` events
through a debug adapter tracker, as the file system does, and adds a `retro/memory/changed` event with the
changed ranges so it can color them without reading everything again.

## Decisions

1. **Our own editor replaces the Hex Editor.** The Hex Editor has no extension points for gutters, panes or
   decoders, and its data inspector cannot learn MBF floats or Apple text. Everything Retrocore opens memory in
   is Retrocore Memory, and the Hex Editor is no longer suggested. It keeps working through the standard
   protocol, for VS Code's binary-data icon and **Reopen Editor With...**, but nothing is added for it.
2. **One webview per view, with no framework.** The display panel already renders in a webview; the grid is
   virtualized by hand, since a 64K space is 4096 rows of 16.
3. **The debugger knows, the editor shows.** Labels, regions, interpretation and analysis come from the debug
   host, which has the symbols and the target. The editor draws and edits.
4. **64K is small.** The editor may keep a whole 64K space in memory, so search, snapshots and comparison run in
   the webview. Larger spaces (below) are searched by the debug host.
5. **Overwrite only.** Memory has no insert; the Hex Editor's insert mode is not carried over.
6. **What a person learns goes in a hints file.** Marks, names and comments are written to the disassembler's
   JSON hints file (`DisassemblyHints`, `--hints`), which already holds entry points, data ranges, names and
   comments. The debugger loads it as one more symbol source, whose names win over the sources', as they do when
   disassembling, so annotating memory while debugging leads straight to `--disassemble`, and the file can be
   checked in, diffed and shared. The launch's `hints` setting names it; without one it is `<program>.hints.json`
   beside the program or source, created at the first mark, and a session with no program asks where to save it
   the first time. An address in a bank keeps its prefix, as memory references do (`"aux:$0400"`); the
   disassembler ignores those, since it reads one image.

## Larger spaces

The Apple III's extended addressing, the CoCo 3's 512K behind its MMU and the Model 4's 128K exceed 64K, and
memory references stop at $FFFF today. A physical space, as MAME separates logical and physical addresses, would
name these, such as `phys:0x1A000`, with the Map showing the MMU's current mapping onto it. It follows once the
editor is built for 64K, and needs the references, `readMemory` and banks to take wider addresses.

## Steps

The order builds each piece once and reuses it. Step 1's whole-space buffer serves find, snapshots and search;
step 2's change coloring is a comparison with a snapshot taken at each stop, so snapshots, RAM search and
freezing come right after it, while that code is fresh; the listing's decoder then serves instruction search,
assembling in place and the inspector's instruction.

1. **Hex Editor parity**: the custom editor with the bytes grid, editing, undo, go to, find of bytes and text,
   copy and a basic inspector, opened by **Open Memory** and the context menu, refreshed by memory events.
   **Open Memory** switches to it. `tools/Test-Memory.mjs` gains the new requests, and the extension's test
   suite opens and edits a view.
2. **Labels and the machine's text**: labels in the gutter and inspector, the character sets from the machines'
   generators, read-only shading and change coloring.
3. **Snapshots and RAM search**: snapshots and comparing, RAM search with its watch list, and freezing.
4. **The listing**: decoding in sync with the bytes, code and data from debug files, analysis for the rest,
   marking, naming and comments saved to the hints file and loaded as symbols, breakpoints from the gutter, and
   find by instruction pattern.
5. **The inspector and map**: regions, doc comments, the machines' interpretations, find by value, follow
   expressions, back and forward, bookmarks.
6. **Editing more**: assembling in place, values written from the inspector, fill, paste, copy as, import and
   export.
7. **Access tracking**: measured first, then the history, heat map and fading changes.
8. **Structures**: the built-in overlays, then `.struct` types.
9. **Larger spaces.**
