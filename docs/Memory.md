# Memory views

The Retrocore debugger serves memory the standard Debug Adapter Protocol way, so VS Code's memory tools work with
it as they do with any debugger. A memory view reads and writes without side effects: reading a soft switch does
not flip it, and reading the keyboard does not take the key. Writes go to RAM only.

## Opening memory

Memory opens in **Retrocore Memory**, the extension's memory editor:

- **Retrocore: Open Memory...** is in the Variables view's title bar and the command palette. It asks for the
  CPU's memory or a bank, then an address, label or expression, and opens it there.
- **Open in Retrocore Memory** is on the context menu of anything in the Variables and Watch views that holds an
  address: a register such as PC or HL, a byte in the memory scope, a watch expression and each entry of the
  **Memory** scope.
- **Reopen Editor With...** switches between Retrocore Memory and any other editor for the same memory.
- **Other memory tools** keep working through the standard protocol: VS Code's own binary-data icon on those
  variables opens Microsoft's [Hex Editor](https://marketplace.visualstudio.com/items?itemName=ms-vscode.hexeditor),
  and Eclipse CDT Cloud's
  [Memory Inspector](https://marketplace.visualstudio.com/items?itemName=eclipse-cdt.memory-inspector) takes any
  memory reference below as its address.

A memory view stays current: at each stop, about four times a second while the machine runs, and after a write
through another view, the debugger tells the view to read again if the bytes it has read have changed. Bytes you
edit are written at once, and the Variables view updates to match.

## Retrocore Memory

Retrocore Memory shows the whole 64K of memory as the CPU maps it, or of one bank, in hex and as text, opened at
the address asked for. A bank's gaps show as `··`. The design for what comes next is in
[MemoryViewer.md](backlog/MemoryViewer.md).

- **Labels** from the program and the SDK's ROM sources name the bytes: the first label in each row shows in a
  gutter beside the address (dimmed when it starts partway along the row), and a mark on the byte where each
  starts. A label counts where its code or data is in memory now, so a ROM's labels go when RAM is mapped over it.
- **The machine's characters.** On the Apple II, the TRS-80 Models I, II, III and 4 and the CoCo 1 and 2, the
  text column draws each byte as the machine's own character generator does under its current modes: the Apple
  II's inverse and flashing text, flashing as it does, the Model I's block graphics, the CoCo's semigraphics.
  Elsewhere it shows each byte's low seven bits as ASCII, so the Apple II's text, kept with bit 7 set, still reads.
  **Machine text** in the toolbar turns this off to show ASCII instead, for typing, finding and copying too; each
  editor remembers the choice.
- **Read-only bytes** (ROM, I/O, keyboard and unmapped addresses) are shaded, and typing there is refused before
  anything is written.
- **Changes.** Bytes that differ from what they held at the stop before are highlighted at each stop, and the
  inspector shows what they were.
- **Editing.** Type two hex digits in the hex column to write a byte, or a character in the text column. Writes
  go to RAM at once; a read-only bank or byte refuses typing. **Ctrl+Z** undoes and **Ctrl+Y** or
  **Ctrl+Shift+Z** redoes, by writing the bytes back. Typing a character writes a code the machine shows it with,
  keeping the byte's style where the machine has several, such as the Apple II's normal, inverse and flashing
  text; so `A` over normal text on an Apple II writes $C1, and over inverse text $01.
- **Go to** (**Ctrl+G**) takes an address, label or expression, in the editor's bank. Digits alone are hex.
- **Find** (**Ctrl+F**) takes hex bytes, with `??` for any byte, such as `A9 ?? 20`, or text in quotes, such as
  `"HELLO"`, which matches each character in any of the machine's codes for it (or, without the machine's
  characters, with bit 7 clear or set). **Enter** or **F3** finds the next, with **Shift** the one before,
  wrapping around.
- **The inspector** beside the bytes shows the address with the label it is in, such as `COUT+3`, the byte at
  the cursor as unsigned, signed, binary and the character it shows, and the word there with either byte first.
- **Moving and selecting.** The arrow keys, **Page Up**, **Page Down**, **Home** and **End** (with **Ctrl**, the
  ends of memory) move; **Shift** or dragging selects; **Tab** switches between the hex and text columns.
  **Ctrl+C** copies the selection as hex bytes, or as the characters it shows from the text column.

## Memory references

A memory reference is an address, optionally naming a bank first:

| Reference | Means |
| --- | --- |
| `0x0400`, `0400` | The CPU's address $0400 as the memory map maps it now. Digits alone are hex. |
| `$0400`, `TEXT_PAGE`, `HL+2` | An expression, in the debugger's expression syntax, evaluated when the view opens. |
| `aux:0x0400`, `aux:TEXT_PAGE` | The byte auxiliary RAM holds for $0400, whatever the soft switches map. |

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

The **Memory** scope in the Variables view lists the CPU's memory and each bank with where the memory map reads
and writes it now, such as `Auxiliary RAM: read at $0000-$01FF; written at $0000-$01FF` with ALTZP on.
`retro/memoryBanks` returns the same list. The Model I maps each address to one place, so it has no banks.

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

The debugger answers `readMemory` and `writeMemory`, and its launch `capabilities` event adds
`supportsWriteMemoryRequest`. `readMemory` returns the bytes up to the first it cannot read, and counts the rest
of the request as `unreadableBytes`, as VS Code expects.

Retrocore Memory uses three more requests:

| Request | Returns |
| --- | --- |
| `retro/memory/read` | For a `memoryReference`, `offset` and `count`, all `count` bytes in `data`, reading past unreadable bytes, which read as zero. `unreadable` lists their runs as `{ offset, count }`, so a bank shows where it is inside the CPU's 64K, and `readOnly` the runs a write cannot reach now. Memory events track its reads as they do `readMemory`'s. |
| `retro/memory/labels` | For a `memoryReference`, the labels in its space as `{ address, name }`, from the debug modules that apply at each address now. |
| `retro/memory/characters` | The machine's character set as its screen shows it now: each character's `width` and `height`, every code's rows in `glyphs` (one byte a row, leftmost pixel in bit 7), the other phase of flashing characters in `flashed`, and in `text` the character each code shows, NUL for graphics. Empty for a machine the debugger cannot draw. |

The debugger keeps, for each reference a view has read, the range read and a hash of its bytes. After each stop,
every eighth running frame and each `writeMemory`, it sends a `memory` event for each view whose bytes have
changed, naming the view's reference exactly, as VS Code requires, with offset 0 and the end of the range read as
its count. The view that wrote is not told. A `writeMemory` also
sends `invalidated` for the variables.

Variables carry a `memoryReference` when they hold an address: the 6502's PC and S (into page one), the Z80's
16-bit registers except AF, and the memory scope's bytes.

## Testing

`node tools/Test-Memory.mjs` checks memory references, unreadable bytes, `retro/memory/read`'s gaps and read-only
runs, labels and the character set, writes and their rollback, memory events for changed views and variables on
the Model I, which needs nothing external, along with resuming after a data breakpoint, a step landing on a
breakpoint and the logpoint limit. With `RETROCORE_IIE_ROMS` set, it checks the IIe's banks, their mapping, bank
expressions, disassembly and data, function and instruction breakpoints. The extension's editor test reads and
writes the Model I's video memory through VS Code's debug memory file system, as the Hex Editor does, then opens it
in Retrocore Memory and types, undoes and inspects bytes there, with their labels, characters and read-only ROM.
`npm run test:grammar` runs the editor page's script with a stand-in DOM, for reading, writing, undo, read-only
banks and bytes, labels and changes since the last stop.
