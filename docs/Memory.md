# Memory views

The Retrocore debugger serves memory the standard Debug Adapter Protocol way, so VS Code's memory tools work with
it as they do with any debugger. A memory view reads and writes without side effects: reading a soft switch does
not flip it, and reading the keyboard does not take the key. Writes go to RAM only.

## Opening memory

- **View Binary Data.** A register that holds an address, a byte in the memory scope, a watch expression and each
  entry of the **Memory** scope all have a binary-data icon in the Variables and Watch views. Clicking it opens
  that address in Microsoft's [Hex Editor](https://marketplace.visualstudio.com/items?itemName=ms-vscode.hexeditor),
  which VS Code offers to install the first time.
- **Retrocore: Open Memory...** is in the Variables view's title bar and the command palette. It asks for the
  CPU's memory or a bank, then an address, label or expression, and opens it in the Hex Editor.
- **Other memory tools**, such as Eclipse CDT Cloud's
  [Memory Inspector](https://marketplace.visualstudio.com/items?itemName=eclipse-cdt.memory-inspector), work too.
  Type any memory reference below as their address.

A memory view stays current: at each stop, about four times a second while the machine runs, and after a write
through another view, the debugger tells VS Code to read it again if the bytes it has read have changed. You can edit bytes in the
Hex Editor, and the Variables view updates to match.

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
| `slot6` | all | Slot 6's Disk II boot ROM, when installed at launch (read-only) | $C600-$C6FF |
| `slot7` | all | Slot 7's ROM, when block storage or a Disk II is in slot 7 at launch (read-only) | $C700-$C7FF |

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
of the request as `unreadableBytes`, as VS Code expects. It keeps, for each reference a view has read, the range
read and a hash of its bytes. After each stop, every eighth running frame and each `writeMemory`, it sends a
`memory` event for each view whose bytes have changed, naming the view's reference exactly, as VS Code requires,
with offset 0 and the end of the range read as its count. The view that wrote is not told. A `writeMemory` also
sends `invalidated` for the variables.

Variables carry a `memoryReference` when they hold an address: the 6502's PC and S (into page one), the Z80's
16-bit registers except AF, and the memory scope's bytes.

## Testing

`node tools/Test-Memory.mjs` checks memory references, unreadable bytes, writes and their rollback, memory events
for changed views and variables on the Model I, which needs nothing external, along with resuming after a data
breakpoint, a step landing on a breakpoint and the logpoint limit. With `RETROCORE_IIE_ROMS` set, it checks the
IIe's banks, their mapping, bank expressions, disassembly and data, function and instruction breakpoints. The extension's editor test reads and writes the
Model I's video memory through VS Code's debug memory file system, as the Hex Editor does.
