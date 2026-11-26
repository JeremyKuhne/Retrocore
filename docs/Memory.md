# Memory views

The Retrocore debugger serves memory the standard Debug Adapter Protocol way, so VS Code's memory tools work with
it as they do with any debugger. A memory view reads and writes without side effects: reading a soft switch does
not flip it, and reading the keyboard does not take the key. Writes go to RAM only.

## Opening memory

Memory opens in **Retrocore Memory**, the extension's memory editor:

- **Memory** in the Retrocore sidebar's Machine view, while the machine runs. On a machine with banks it lists the
  CPU's 64K and each bank, with where the memory map reads and writes it now; a click opens one. On the Model I,
  which has none, a click on **Memory** opens the 64K.
- **Open in Retrocore Memory** on an assembly editor's context menu while debugging opens the label or address
  under the cursor, such as `TEXT_PAGE` or `$0400`, or the expression selected.
- **Retrocore: Open Memory...** is on the debug toolbar, in the Machine, Variables and Watch views' title bars and in the
  command palette. It asks for the CPU's memory or a bank, showing where the memory map reads and writes each bank now,
  then an address, label or expression, and opens it there. On a machine with banks, the list at the right of the
  editor's toolbar names the space it shows, and picking another opens that one in its place, at the cursor's address.
- **Open in Retrocore Memory** is the binary-data icon beside each variable that holds an address, such as PC, HL
  or a byte in the zero page or communication region, and on its context menu. The Watch view's context menu has
  it for every expression; one that holds no address says so.
- **Other memory tools** keep working through the standard protocol, such as Eclipse CDT Cloud's
  [Memory Inspector](https://marketplace.visualstudio.com/items?itemName=eclipse-cdt.memory-inspector), which takes
  any address, label or expression. VS Code's own binary-data icon, which opens only Microsoft's Hex Editor, does
  not appear: VS Code shows it on variables that carry a memory reference, and the debugger sends its views none.

A memory view stays current: at each stop, about four times a second while the machine runs, after a write
through another view, and when a card goes in or out or the machine resets while stopped, the debugger tells the
view to read again if the bytes it has read have changed. Retrocore Memory also reads its labels, characters and
frozen bytes again at each stop and at such a change, and the Machine view its banks. Bytes you
edit are written at once, and the Variables view updates to match. When the session ends, its memory editors
close; restarting it keeps them open, and they read the restarted machine.

## Retrocore Memory

Retrocore Memory shows the whole 64K of memory as the CPU maps it, or of one bank, in hex and as text, opened at
the address asked for. A bank's gaps show as `··`. The design for what comes next is in
[MemoryViewer.md](backlog/MemoryViewer.md).

- **Labels** from the program and the SDK's ROM sources name the bytes: the first label in each row shows in a
  gutter beside the address (dimmed when it starts partway along the row, with **+N** where more start in the row,
  which its tooltip lists with each one's kind: a routine or code, data, or a named address), and a small corner
  on the byte where each starts, which the tag toggle in the Label heading hides. A label's kind is what
  its documentation declares it, such as a routine or table, else code or data by the statement at it, or a
  constant; the bytes of a label on data, its data statements and the bytes marked as data up to the next name,
  are shaded, two shades by turns so one table next to another shows where it starts. Hovering a name marks its byte, and clicking
  it goes there. Headings over the bytes name the columns, with each byte's offset in its row, and stay in view
  as the bytes scroll. A label counts where its code or data is in memory now, so a ROM's labels go when RAM is mapped over it.
  Equates that the CPU's instructions address memory through name those bytes too, whatever is mapped there: an
  equate counts where an instruction's bytes access its value, while that code is installed, so the Monitor's `STA CursorColumn` names $24 `CursorColumn`, and the
  6809's `LDA [Vector]` names `Vector`, but `CMP #CR` does not make `CR` a name for $0D, nor does an index's offset
  or a term added to another address. A label at the same address comes first.
- **Align to labels**, the toggle in the Label heading, shown once there are labels, starts a row where each label starts, so a
  label's bytes begin a row of their own; each byte stays in its column, and **Up** and **Down** keep the column,
  or go to the nearest byte the row has. Each editor remembers the choice.
- **The machine's characters.** On the Apple-1, the Apple II, the Apple III, the TRS-80 Models I, II, III and 4
  and the CoCo 1, 2 and 3, the text column draws each byte as the machine's own character generator does under its
  current modes: the Apple II's inverse and flashing text, flashing as it does, the Apple III's character set as
  SOS loaded it, the Model I's block graphics, the CoCo's semigraphics, and the CoCo 3's GIME text once it is on.
  The Apple-1 keeps its screen in the terminal rather than memory, so a byte draws as the terminal would show it
  written to the display.
  Elsewhere it shows each byte's low seven bits as ASCII, so the Apple II's text, kept with bit 7 set, still reads.
  **ASCII**, the toggle in the Text heading, shows ASCII instead, for typing, finding and copying too; each
  editor remembers the choice.
- **The listing**, beside the bytes, shows the bytes in view as instructions and data, in the CPU's own syntax,
  as the Disassembly view does. It starts at the nearest place an instruction is known to start: the statement a
  debug file or source describes, or a label. A statement the sources make data, such as `.byte`, lists as data,
  eight bytes a line. Where no source describes the bytes, analysis guesses: from the PC of the CPU that runs the
  space (none for a bank of RAM), each **Decode from here** start and the sources' code, it follows calls, jumps
  and branches into undescribed memory, and lists what it reaches as code and the pointers and vectors those read
  as data, in italics, as guesses. It keeps out of the sources' data, never splits a Decode from here start's
  instruction, and never reads a pointer from bytes that cannot be read. Bytes nothing reaches are dimmed, as they
  may not be code. Operands name their labels, such as `LDA Keyboard`, and
  clicking one goes to its address; clicking a line selects its bytes, and its source, such as `main.s:12`, opens
  beside the editor. Where the listing decodes from the wrong byte, **Decode from here** in the inspector
  (**Ctrl+D**) starts an instruction at the cursor, even in data, and it holds as the view scrolls. The listing
  scrolls with the lines the bytes in view decode to, keeps the cursor's line in view, and decodes again after
  typing or undo. It takes one tab stop: **Up** and **Down** move between lines, **Left** and **Right** to a line's
  operand and source, **Enter** does what a click does, and **Escape** goes back to the bytes. Its **Disassembly**
  heading collapses it, as **Label**, the byte offsets and **Text** collapse theirs: each column folds into a narrow
  strip with its name turned on its side between two triangles, reading upward, or downward for Disassembly, and
  clicking the strip expands it again. Each editor remembers which are collapsed. The listing fills the room the bytes and
  the inspector leave, and only an editor too narrow for it leaves it out.
- **Breakpoints from the listing.** A dot in the listing's gutter shows where a breakpoint stops, set from any
  source, the Breakpoints view or the Disassembly view. Clicking the gutter, or **F9** on a line or in the bytes,
  sets a function breakpoint named by the address, such as `$6000` or, in a bank's editor, `aux:$0400`, which
  stops only while the CPU runs that bank's code there; it shows in the Breakpoints view and stays between
  sessions. Clicking a dot takes away the breakpoints that stop there, except the Disassembly view's, which are
  taken away there.
- **Values, fill and paste.** Clicking a value in the inspector (the byte as hex, unsigned, signed or binary,
  either word, or the BASIC's float) asks for a new one and writes it at the cursor: `$1234` as a word low first is
  `34 12`, and `1000` as AppleSoft's float `8A 7A 00 00 00`, which the debugger encodes. **Fill** in the inspector
  repeats a byte, bytes or text in quotes over the selection, such as `EA`, `01 02` or `"*"`. **Ctrl+V** pastes the
  clipboard at the cursor: hex bytes, which may be the Monitor's lines with their addresses (`0300: A9 C1`); or, in
  the text column, characters, each written as typing writes it. Each is one edit, which **Undo** takes back.
- **Copy as, save and load.** **Copy as** in the inspector copies the selection as hex, the Monitor's lines
  (`0300: A9 C1 20`), which can be typed into the machine, native `.byte` lines, BASIC `DATA` statements, a C array
  or base64. **Save** writes the selection to a file, as its extension says: Intel HEX for `.hex` or `.ihx`, native
  assembly for `.asm` or `.s`, and the bytes as they are for anything else. Assembly comes from the debugger's
  `retro/memory/export`, through the disassembler's exporter: what the listing knows of code and data, the
  session's labels, with equates for those outside the range the code uses, and the hints file's comments. The
  debugger assembles it again, and where it would not give the same bytes saves `.byte` lines instead, and says so.
  **Load** writes a binary's bytes at the cursor, or Intel HEX's at the addresses it gives, as one edit.
- **Assemble in place.** **F2** in the bytes or the listing, **Assemble** in the inspector, or a double-click on a
  listing line asks for an instruction to type over the line at the cursor, as the Monitor's mini-assembler takes
  one: `LDA KBD`, `JSR COUT` or `BNE *+4`, in the CPU's native syntax with the session's labels and the hints file's
  names. The box shows the bytes and what they decode to as you type, or why the line does not assemble. A shorter
  instruction asks whether to pad the rest of the old one with NOPs; a longer one says which instructions it
  overwrites and writes only on **Write**. The write is one edit, which **Undo** takes back.
- **Marks, names and comments.** **Mark code** in the inspector starts an instruction at the cursor, **Mark data**
  makes the selection data, even over a source's instructions, and **Unmark** takes either off; analysis and the
  listing take them as given, a marked instruction listing as one line whatever label or statement
  starts inside it, and a mark takes out the other kind where an instruction would overlap it.
  **Name** labels the cursor's address with a name the disassembler takes, unique among its space's names and labels, winning over the
  sources' labels in the gutter, the inspector and the listing's operands, and **Comment** puts a comment after its
  line in the listing; an empty one takes it away.
  A name is a symbol in expressions too, in Watch, Go to, conditions and function breakpoints, winning over the
  sources' labels; a bank's names are in that bank only, so `aux:AUXTEXT` and `[aux:AUXTEXT]` read auxiliary RAM. Function breakpoints bind again when a name
  changes, so one on a name moves with it.
  All of them are kept in the launch's hints file, the disassembler's (`--hints`), so what you learn while
  debugging leads straight to `--disassemble`: the launch's `hints` setting names it, and without one it is
  `<name>.hints.json` beside the source, program or debug file, made at the first mark (a project launch's is
  `<project>.<target>.hints.json` in the project's folder); a launch with none of those asks where at the first mark. Each mark is made to the file as it is then, so edits to it are kept, and
  a file that cannot be read is left alone and marks nothing. A bank's marks keep its name, such as
  `"aux:$0400"`, and the disassembler, reading one image, leaves those and any outside its image out.
- **Read-only bytes** (ROM, I/O, keyboard and unmapped addresses) are shaded, and typing there is refused before
  anything is written.
- **Changes.** Bytes that differ from what they held at the stop before are highlighted at each stop, and the
  inspector shows what they were.
- **Comparing.** **Compare with**, the list in the toolbar, with the diff toggle beside it that turns the highlighting off and on, picks what the highlighted bytes differ from: what they held at
  the last stop, a snapshot, or another bank's bytes at the same addresses, such as auxiliary RAM beside main RAM,
  read again at each stop. **Snapshot** keeps a copy of every byte and compares with it. The inspector shows what
  the byte at the cursor holds in the snapshot or the other bank.
- **Editing.** Type two hex digits in the hex column to write a byte, or a character in the text column. Writes
  go to RAM at once; a read-only bank or byte refuses typing. **Ctrl+Z** undoes and **Ctrl+Y** or
  **Ctrl+Shift+Z** redoes, by writing the bytes back. Typing a character writes a code the machine shows it with,
  keeping the byte's style where the machine has several, such as the Apple II's normal, inverse and flashing
  text; so `A` over normal text on an Apple II writes $C1, and over inverse text $01.
- **Go to** (**Ctrl+G**) takes an address, label or expression, in the editor's bank. Digits alone are hex. A
  register reads as the focused frame shows it, so `PC` in the SoftCard's `z80` editor is the Z80's while its
  frame is focused, and `SP` in a caller's frame is the caller's; an address that frame puts in another bank, such
  as `$0400` in the CPU's editor while the Z80's frame is focused, reads as the CPU's, as an address does while
  a BASIC frame is focused. Opening a label or a Watch expression does the same.
- **Follow**, the eye toggle in the Go to box, goes to Go to's expression again at each stop, such as `PC`, `S+$100`, `HL` or
  `[$06].w`, so the view keeps up with a register or pointer; a new Go to while following follows that instead.
  Clearing it leaves the view where it is. Each editor remembers what it follows.
- **Back** and **Forward** (**Alt+Left** and **Alt+Right** wherever focus is in the editor, or the mouse's back and forward buttons) go through
  where Go to, the map, the listing's operands, bookmarks, search results and following have moved the view.
- **Bookmark** in the inspector names the cursor's address, or renames or removes its bookmark; **Bookmarks** in
  the toolbar lists them in a quick pick, to go to one or remove it. They are kept in the workspace's state for each
  launch configuration, since they record where someone was looking rather than anything about the program. A
  bookmarked byte is underlined. One in another bank goes there in that bank's editor, opening one if none is open.
- **Find** (**Ctrl+F**) takes hex bytes, with `??` for any byte, such as `A9 ?? 20`; text in quotes, such as
  `"HELLO"`, which matches each character in any of the machine's codes for it (or, without the machine's
  characters, with bit 7 clear or set); or an instruction, as the listing shows it, with `?` for any character and
  `*` for any run, such as `STA $C0??`, `JSR COUT` or `LD A,(*)`. An instruction's operand matches as a number or
  as its label, ignoring case and the spaces around commas, and every byte is tried as an instruction's start;
  text that reads as hex bytes, such as `ADDA`, is found as bytes. A number after `=`, such as `=1000`,
  `=$C000` or `=-2.5`, is found in any of the inspector's forms: a byte when it fits one, else a word low first or
  high first, and the BASIC's floats, as BASIC rounds the number; the nearest wins, and the status says which form
  it was. **Enter** or **F3** finds the next, with **Shift** the one before, wrapping around.
- **The map** across the top is the whole space, colored by what memory reads there now (RAM, ROM, I/O, video,
  or nothing), with a line where each of the machine's regions starts and a box around the bytes in view. In a
  bank's editor it shows what the CPU does with the bank now: bright where the CPU reads it, striped where it only
  writes it, as with the IIe's RAMWRT on and RAMRD off, and dimmed where it does neither. The IIe's main and
  auxiliary RAM are split into the parts one switch puts in the CPU's view, which hovering names, such as the
  alternate zero page and stack (ALTZP), text page 1 (80STORE with PAGE2), RAM from $0200 (RAMRD and RAMWRT) and the
  language card. Hovering names the address, its region and what reads there, and a click goes there. It is read
  again at each stop.
- **The inspector** is beside the bytes, or under them: the layout icons at the right of its tabs move it, the one
  for where it is now showing pressed, and the splitter between it and the bytes, dragged or moved with the arrow keys,
  sizes it. Each editor remembers both. It shows the address with the label it is in, such as `COUT+3`, the byte at
  the cursor as unsigned, signed, binary and the character it shows, and the word there with either byte first.
  It says which part of the machine's map the address is in and where in it, such as *Text page 1, row 10,
  column 0* or *Hi-res page 1, line 83, byte 5*; on a machine with banks, what the memory map does with it now,
  such as *Reads main language card* or, in auxiliary RAM's editor, *Not mapped now*; the documentation of its
  label from the sources, so `$24` explains `CursorColumn` and `$C030` the speaker; the source line that emitted it, which
  opens on a click; and the BASIC's floating point number starting there (five bytes for AppleSoft and Color
  BASIC, four for Business BASIC, Level II's single and double). It says these in short lines under **Where**
  (the address, its name and what kind of name, such as a *named address* for an equate naming RAM), **Value**
  (the byte as hex, unsigned, signed and binary, and its character only where it is one), **Code**, **Used by**
  and **As a number**, which shows the word in the CPU's byte order (**Both byte orders** adds the other) and the
  floats, and is left out where an instruction starts, as its bytes are no number. Its buttons are what debugging
  uses most, **Watch**, **Freeze**, **Name** and **Comment**; the **Mark**, **Edit** and **Export** menus hold the
  rest, and right-clicking the bytes (or **Shift+F10**) lists them all by group, each acting on the selection.
- **Bits, the instruction and references.** For a soft switch or flag byte, the inspector names the bits its
  documentation describes, with each one's value now: the masks it links to, as the CoCo 3's `INIT0` lists `MMUEN`
  and the rest, and what it says of a bit by number, as the IIe's `AuxReadState` "reports in bit 7 whether RAMRD is on".
  Where code is known to start, from the sources, analysis, **Decode from here** or **Mark code**, it shows the
  instruction there with its size, cycles (and when a branch is taken), the flags it changes and what it does; the
  Z80's and 8080's cycles come from their instruction sets, and the 6502's and 6809's, whose indexed operands and
  register lists add to a base, from running the instruction once on a processor of its own. **References** lists the instructions in the code the debugger knows that read,
  write, call or jump to the address, each with the label it is in; a click goes there.
- **Watch** adds the selection to VS Code's Watch view: a byte as `[$4100]` (in a bank, `[aux:$0400]`), two bytes
  as the word `[$4100].w`, in the CPU's byte order, and more as each byte, up to 16. VS Code evaluates a watch in the focused frame, so on
  a machine with a SoftCard the CPU's editor watches `[cpu:$4100]`, which stays the 6502's while the Z80's frame is
  focused. There **Break on Value Change** sets a data breakpoint
  on it, and a frozen byte's value says `(frozen)`. The editor adds watches through VS Code's own **Add to Watch**
  command, as extensions have no API for it; remove them in the Watch view.
- **RAM search**, a tab beside the inspector, finds the byte that holds a value, such as a game's lives, or the
  16-bit word that holds a score, in the CPU's byte order: low byte first, but high byte first on the 6809.
  **Start with all RAM** takes every byte or word a write can reach; then, after the value changes in the game,
  keep the values that changed, did not change, rose or fell since the step before, or that equal or do not equal
  a value (hex with `$`, binary with `%`, or decimal). Each step reads all of memory again. **Back a step** undoes
  one, and **Start over** chooses bytes or words again; at 200 or fewer they are listed, with what they were and
  are, to go to or watch.
- **Freezing** holds a byte at a value while the machine runs, as for a game's lives: as each instruction that
  writes ends, any frozen byte that changed is put back, however the write reached it, so the program never reads a
  value of its own there, and the debugger writes them back before each slice it runs, every few milliseconds, for a
  device's writes. With more than 256 bytes frozen, they are held at each slice only, as checking that many after
  every store would slow the machine many times over. Frozen bytes
  show in blue, and the **Frozen** tab lists them to watch or thaw;
  typing over one changes the value it is held at. Only RAM can be frozen. Frozen bytes are the session's, so
  every editor on that memory shows them. A byte frozen in the CPU's memory is held in the RAM it was frozen in,
  such as the language card's bank 2 at $D000, and waits while the program switches other memory there.
- **Moving and selecting.** The arrow keys, **Page Up**, **Page Down**, **Home** and **End** (with **Ctrl**, the
  ends of memory) move; **Shift** or dragging selects. **Tab** moves from the hex column to the text column and
  **Shift+Tab** back; past them, they move focus on to the side panel or the toolbar as usual.
  **Ctrl+C** copies the selection as hex bytes, or as the characters it shows from the text column, and **Ctrl+V**
  pastes there.

## Memory references

A memory reference is an address, optionally naming a bank first:

| Reference | Means |
| --- | --- |
| `0x0400`, `0400` | The CPU's address $0400 as the memory map maps it now. Digits alone are hex. |
| `$0400`, `TEXT_PAGE`, `HL+2` | An expression, in the debugger's expression syntax, evaluated when the view opens. |
| `aux:0x0400`, `aux:TEXT_PAGE` | The byte auxiliary RAM holds for $0400, whatever the soft switches map. |
| `cpu:0x0400`, `[cpu:$0400]` | The machine's own CPU's $0400, as a reference with no bank is, even in an expression evaluated in a coprocessor's frame, such as the SoftCard Z80's, where `[$0400]` is the Z80's. |

Bytes a reference cannot reach read as unreadable, such as past $FFFF or in a gap in a bank. Writes that cannot
finish, such as one that reaches ROM, are refused without changing anything, unless the client allows a partial
write.

## Memory banks

On the Apple II family one address can mean several bytes: $D000 may be ROM, a slot-0 firmware card or either of
two language-card banks, $C600 may be a slot's ROM or the IIe's internal firmware, and on the IIe $0000-$BFFF and
$D000-$FFFF also exist in auxiliary RAM. Soft switches choose which one the CPU sees. A memory view of the CPU's
memory follows the switches. A bank names one store directly, so you can look at or change memory the program has
switched out.

| Bank | Models | Holds | At |
| --- | --- | --- | --- |
| `main` | all | Main RAM, with the language card's bank 2 at $D000-$DFFF | $0000-$BFFF, $D000-$FFFF |
| `aux` | IIe | Auxiliary RAM, with its language card's bank 2 | $0000-$BFFF, $D000-$FFFF |
| `bank1` | all | Main RAM's language-card bank 1 | $D000-$DFFF |
| `auxbank1` | IIe | Auxiliary RAM's language-card bank 1 | $D000-$DFFF |
| `rom` | all | The system ROM (read-only): the IIe's internal firmware, AppleSoft and Monitor; on the II and II Plus, the board's ROM (or the slot-0 firmware card's while active) | $C100-$FFFF (IIe); $D000-$FFFF (II, II Plus) |
| `slot1`-`slot7` | all | A slot's ROM, while its card has one: a Disk II's boot ROM, the mouse or ProFile card's firmware, or slot 7's block storage (read-only) | $Cn00-$CnFF |
| `z80` | all, with the SoftCard | Memory as the Z80 SoftCard's Z80 sees it, through the card's address translation; it disassembles as Z80 code | $0000-$FFFF |

A bank's addresses are the CPU addresses its bytes answer at when it is mapped, so `aux:$0400` is auxiliary
RAM's text page one and `bank1:$D000` is the first byte of bank 1. On the IIe, `rom:$C600` is the internal
firmware even while slot 6's ROM is mapped there, and `slot6:$C600` is the slot's ROM even while INTCXROM maps
the internal firmware. Bank names are not case-sensitive.

A tab is titled by where it opened, such as **Memory $3C00** or **Memory aux:$0400**. Its URI,
`retrocore-memory://<session>/<reference>/<title>`, names the debug session and memory reference; there is no file
behind it, and the bytes come from the debugger.

The Machine view's **Memory** rows and **Open Memory** list the CPU's memory and each bank with where the memory
map reads and writes it now, such as `Auxiliary RAM: at $0000-$01FF` with ALTZP on, and read again at each stop.
`retro/memoryBanks` returns the same list, with `coprocessor` true for a coprocessor's address space, such as
`z80`, and `bigEndian` true where its CPU keeps a word's high byte first, as the 6809 does. The Model I maps each address to one place, so it has no banks.

Banks work anywhere an address does:

- **Expressions:** `[aux:$0400]` reads auxiliary RAM's byte and `[bank1:$D000].w` a word from bank 1, in watch
  expressions, hovers, breakpoint conditions and log messages. `aux:$0400` alone evaluates to the address with a
  memory reference into the bank.
- **Data breakpoints:** a watch expression `[aux:$0400]`, or `aux:$0400` in **Add Data Breakpoint at Address**,
  stops only on accesses the memory map sends to auxiliary RAM. A write to $0400 that reaches main RAM does not
  stop it. Its data id is `bank:aux:0400:1`.
- **Function and instruction breakpoints:** `bank1:$D000` stops only while the CPU runs bank 1's code at $D000
  ([Breakpoints.md](Breakpoints.md)).
- **Disassembly:** a `disassemble` request for a bank reference decodes the bank as if it were mapped, with the
  lines and labels of the source whose code is in it. VS Code's Disassembly view follows the CPU, so it shows
  memory as the CPU maps it; other clients can ask for a bank.

A program the launch loads with a `.dbg` file applies to the memory it was loaded into (main RAM on the IIe), so
its labels and lines do not show for auxiliary RAM switched in at the same addresses.

## The debug protocol

The debugger answers `readMemory` and `writeMemory`, and lists both in its capabilities. `readMemory` returns the
bytes up to the first it cannot read, and counts the rest of the request as `unreadableBytes`, as VS Code expects.

VS Code draws its Hex Editor icon on any variable or watch with a `memoryReference`, so the debugger sends none
there. A variable that holds an address has the menu context `memory` (`__vscodeVariableMenuContext`) in its
place, which **Open in Retrocore Memory** shows on, and `retro/memory/variable` gives its reference. An
`evaluate` result has its `memoryReference` except in the `watch`, `hover` and `variables` contexts; Retrocore
Memory evaluates with the context `retrocore`.

Retrocore Memory uses these requests:

| Request | Returns |
| --- | --- |
| `retro/memory/read` | For a `memoryReference`, `offset` and `count`, all `count` bytes in `data`, reading past unreadable bytes, which read as zero. `unreadable` lists their runs as `{ offset, count }`, so a bank shows where it is inside the CPU's 64K, and `readOnly` the runs a write cannot reach now. Memory events track its reads as they do `readMemory`'s. |
| `retro/memory/unsubscribe` | Removes the reads associated with a `subscriber` supplied to `retro/memory/read`, without removing other subscribers or standard DAP reads. |
| `retro/memory/labels` | For a `memoryReference`, the labels in its space as `{ address, name }`, from the debug modules that apply at each address now, then the equates its CPU's instructions address memory through, from the modules whose code is installed: in the bank its area is in, so a ROM's while RAM is mapped over it, but not a card's firmware without the card. |
| `retro/memory/listing` | For a `memoryReference`, `address` and `count` of bytes, the `lines` of instructions and data from the nearest known instruction start at or before `address`, which `starts` adds to (a start in `starts` or a label up to 4096 bytes back still counts, and a start in `starts` decodes an instruction even in data): each line's `address`, `size`, `text`, `kind` (`code`, `data` or `unknown`), whether that kind is analysis's `guess` where no source describes the bytes, `label`, the `target` its operand names (a restart's implied address; for a 6809 direct-page operand, in the page DP holds at the stop, and none in another CPU's memory), the source `path` and `line`, the hints file's `comment` on the line's bytes, with `comments` giving each one's `address` and `text` (a comment starts a data line), and the ids of the `breakpoints` that stop at its address, a bank's only in that bank's listing, or null. |
| `retro/memory/mark` | For a `memoryReference` and `address`, one of `kind` (`code`, `data` or `clear`, for `count` bytes), `name` or `comment`, an empty one taking it away; writes the launch's hints file as it is now and answers its `path`, or, where the launch has no file, `needsFile` until a request names one as `hints`; it also answers the `address` and `count` of the bytes the mark covers, a code mark's being its instruction's. The file is written beside the old and then takes its place, and one whose parts are not the shapes the disassembler takes is refused. |
| `retro/memory/note` | For a `memoryReference` and `address`, the `name` and `comment` the hints file gives it now, or null. |
| `retro/memory/starts` | For a `memoryReference`, a mark's `address` and `count`, and an editor's Decode from here `starts`, the `starts` left: each whose instruction is in those bytes or runs into them goes, except `keep`, a code mark's own. |
| `retro/memory/find` | For a `memoryReference` and an instruction `pattern` (`?` any character, `*` any run; case and the spaces around commas ignored), the nearest instruction from `from`, or back from it with `backward`, wrapping once, whose text matches with its operand as a number or as its label: its `address`, `size` and `text`, or a null `address`. |
| `retro/memory/map` | For a `memoryReference`: the machine's `regions`, each with its `start`, `length`, `name` and `kind`, as `retro/memory/inspect` gives them; and the `areas`, the runs of addresses that read the same part of the machine now, to the byte, each with its `start`, `length`, `name`, `kind` (`ram`, `rom`, `io`, `video` or `none`) and whether it is `mapped`: always in the CPU's view, and in a bank's whether the CPU reads the bank there now. A bank's gaps are `none`; a coprocessor's view has neither. |
| `retro/memory/assemble` | For a `memoryReference`, an `address` and a `line`, such as `LDA KBD`: the `bytes` it assembles to there, in the space's CPU's native syntax with the session's symbols (the hints file's names in the space first), the `text` they decode to with operands named, and the CPU's `nop`. Nothing is written. A line that does not assemble is an error with the assembler's message. |
| `retro/memory/numbers` | For a `memoryReference` and a `value`, as BASIC writes numbers: `formats`, each with the `label` the inspector gives it and the `bytes` in memory order, rounded once from the decimal text as BASIC stores the value, so Level II's double keeps all 56 bits. None in a coprocessor's view, with an integer BASIC, or where the value is too large for a format. |
| `retro/memory/inspect` | For a `memoryReference` and an `address`: the `region` of the machine's map it is in, with its `kind` (`ram`, `rom`, `io`, `video`, or `none` where nothing is mapped) and the `detail` of where in it, such as a text screen's row and column; what the memory map does with it now, `mapped`, on a machine with banks; the `label` it is or is in, with the `offset` past it and its documentation's `summary`; the source `path` and `line` that emitted it; the BASIC's floating point `values` starting there, each a `label` and `value`; the `bits` its name's documentation describes, each a `bit`, the `name` of the mask linked for it or null, and its `meaning`; the `instruction` starting there where code is known to start, with its `text`, `size`, `cycles`, `cyclesTaken` for a branch, the `flags` it changes and its `summary`; and up to 32 `references` from known code, each the instruction's `address`, `text`, `label` and `kind` (`reads`, `writes`, `changes`, `jumps`, `calls`, `branches`, `jumps through` or `vector`), with their `referenceCount`. It takes the editor's Decode from here `starts`, as the listing does. Anything unknown is null. |
| `retro/memory/freeze` | For a `memoryReference`, freezes `freeze`'s `{ offset, value }` bytes and thaws `thaw`'s offsets, then lists the space's frozen bytes as `{ address, value }` in `frozen`. A frozen byte is written at once, again as each instruction that writes ends while 256 or fewer are frozen, and before each slice the machine runs. Only bytes a write can reach now can be frozen, each at a value from 0 to 255; a request with any other value, or a byte with no offset, changes nothing. An `evaluate` of `[address]` or `[address].w` that reads a frozen byte adds `(frozen)` to its result. |
| `retro/memory/variable` | For a `variablesReference` and a variable's `name` in it, the `memoryReference` VS Code was not sent. An error for a variable that holds no address. |
| `retro/memory/characters` | The machine's character set as its screen shows it now: each character's `width` and `height`, every code's rows in `glyphs` (one byte a row, leftmost pixel in bit 7), the other phase of flashing characters in `flashed`, and in `text` the character each code shows, NUL for graphics. Empty for a machine the debugger cannot draw. |

The debugger keeps the disjoint ranges each view has read and a hash of their bytes. Retrocore Memory supplies an
editor-specific `subscriber` with each `retro/memory/read`, and unsubscribes it when the editor closes. Reads without
a subscriber, including standard `readMemory` reads, are tracked separately. The `initialize` capability
`supportsRetrocoreMemorySubscriptions` advertises this support. Unscoped DAP reader references use a 32-entry
least-recently used limit; live editor subscriptions remain until their editor closes. Each editor's ranges include
all the pages it has cached, including pages scrolled out of view, so changes to those pages still invalidate the
cache. Scrolling through the whole space or searching all of RAM can therefore leave the whole space tracked and
hashed until the editor closes. After each stop, every eighth running frame and each `writeMemory`, the debugger
sends a `memory` event for each reference whose tracked bytes have
changed, with offset 0 and the end of the changed view's last range as its count, as VS Code requires. The view
that wrote is not told. A `writeMemory` also
sends `invalidated` for the variables. A `retro/hardware` change or `retro/reset` while stopped sends the same
`memory` events and then `invalidated` for everything, which Retrocore Memory and the Machine view take as the
sign to read their labels and banks again.

Variables hold an address, which `retro/memory/variable` gives, for the 6502's PC and S (into page one), the
Z80's 16-bit registers except AF, the memory scope's bytes and Pascal's variables.

## Testing

`node tools/Test-Memory.mjs` checks memory references, unreadable bytes, `retro/memory/read`'s gaps and read-only
runs, labels and the character set, Level II's floats for find by value, freezing, writes and their rollback, memory events for changed views and variables on
the Model I, which needs nothing external, along with resuming after a data breakpoint, a step landing on a
breakpoint and the logpoint limit. With `RETROCORE_IIE_ROMS` set, it checks the IIe's banks, their mapping, bank
expressions, disassembly and data, function and instruction breakpoints. The extension's editor test opens the
Model I's video memory in Retrocore Memory and types, undoes and inspects bytes there, with their labels, characters and read-only ROM.
On the IIe it built from the SDK's sources, it also checks `retro/memory/inspect`'s regions, screen positions,
mapping, documented labels, source lines and floats, `retro/memory/map`'s regions and areas, and
`retro/memory/numbers`' AppleSoft floats.
It checks the instruction at the cursor, with cycles measured on the 65C02 and a branch's when taken, the references
to an address, and a soft switch's bits; on the Model I, the Z80's T-states; and `Test-CocoDap.mjs` the CoCo 3's
`INIT0` and `INIT1` bits. It assembles lines with the session's labels on the IIe and in the Z80's syntax on the
Model I, and checks that assembling writes nothing, the kinds and data sizes `retro/memory/labels` gives, and that `retro/memory/export` saves the IIe program and the
Model I's ROM as assembly that assembles back to the same bytes.
`npm run test:grammar` runs the editor page's script with a stand-in DOM, for reading, writing, undo, read-only
banks and bytes, labels, changes since the last stop, snapshots, RAM search, watching and freezing, the listing's
breakpoints and finding instructions, the inspector with its bits, instruction and references, assembling in place, writing
the inspector's values, fill and paste, copy as, save and load, the map, back and forward, following, bookmarks and finding numbers.
