# Breakpoints

The Retrocore debugger supports every kind of breakpoint VS Code's **Breakpoints** view offers. Each can have a
condition, a hit count and a log message (though VS Code's UI does not offer **Edit Log Message** on data
breakpoints). The debugger counts each breakpoint's hits and shows them in the breakpoint's hover. All of this
works the same on the Apple II family, the Apple III and the Model I, in your program, in BASIC and in the SDK's ROM sources.

| Kind | Set it | Stops when |
| --- | --- | --- |
| Source | The editor's gutter (F9), Shift+F9 for a later BASIC statement on a line, or `breakpoints` in a launch configuration | The PC reaches the line's code in a module that applies there (a line in a macro body stops in every expansion), or BASIC starts that statement. |
| Function | **+** in the Breakpoints view: a label or an address expression, such as `DISPLAY_CHAR`, `$C600` or `COUT+3` | The PC reaches that address, from any code. |
| Scanline (Apple II) | The **Video beam reaches a scanline** checkbox in the Breakpoints view, with **Edit Condition** for the positions; or **+** with a name such as `scanline 192:0` | The video beam reaches that scanline and column, between any two cycles. See [Scanline breakpoints](#scanline-breakpoints). |
| SOS call (Apple III) | **+** with a name such as `sos OPEN`, `sos $C8`, or `sos` for every call | A program is about to make that SOS call. See [SOS call breakpoints](#sos-call-breakpoints). |
| Pascal (Apple II, Apple III) | **+** with a name such as `pascal HELLO.2`, `pascal HELLO.2+$0D` or `pascal 1.2` | Apple Pascal's interpreter is about to run that p-code of the procedure, on the Pascal thread. See [Pascal breakpoints](Pascal.md#pascal-breakpoints). |
| Instruction | The gutter of the **Disassembly** view (**Open Disassembly View** from the call stack or the editor's context menu) | The PC reaches that instruction. |
| Data | **Break on Value Read / Change / Access** on a memory variable or a watch expression, **Break on Value Change** on a BASIC variable or array element, or **Add Data Breakpoint at Address** in the Breakpoints view | The CPU reads or writes the watched bytes or Z80 I/O port (stopping after the instruction), or a BASIC statement changes the watched variable. |
| Exception | The checkboxes in the Breakpoints view | See [Exception filters](#exception-filters). |

## Exception filters

The Breakpoints view lists these checkboxes. Each one's hover says what it stops at.

| Checkbox | Machines | Default | Stops |
| --- | --- | --- | --- |
| **Machine reset** | both | on | As the machine powers on, at the reset handler's first instruction, or at a loaded program's entry. Then at each reset: RESET on the Apple II stops at the reset vector's handler (`RESET`, or DOS's handler once booted), and the Model I's reset button at its non-maskable interrupt's handler, `NMI` at `$0066`. A BASIC file's launch boots past reset during the launch, so it stops only at later resets. With `stopOnEntry`, the entry stop is the power-on stop. |
| **BRK instructions** | Apple II, Apple III | on | Before a 6502 `BRK` runs. On the Apple III, only before one that SOS would refuse as a call, and before SOS's debug call: see [SOS call breakpoints](#sos-call-breakpoints). |
| **Video beam reaches a scanline** | Apple II | off | See [Scanline breakpoints](#scanline-breakpoints). |
| **Routine broke its Keeps: promise** | both | off | Where a call returns having changed something its routine's `;; Keeps:` comment says it keeps. Listed when a source has such a comment and `checkContracts` is not `off`. |
| **BASIC program start** | both | on | On the BASIC thread, at the first statement each `RUN` runs, and where `CONT` resumes. A BASIC file's launch stops on its first statement as its entry instead. |
| **BASIC errors** | both | on | At the statement that fails, when no ONERR GOTO or ON ERROR GOTO will take the error. |
| **Handled BASIC errors** | both | off | Also when an error handler will take the error. |
| **BASIC program end** | both | off | At STOP, END, the end of the program, and Ctrl-C or BREAK. |

A breakpoint at the same instruction or statement as one of these stops there once, as the breakpoint.

## Conditions, hit counts and logpoints

Right-click a breakpoint and choose **Edit Condition**, **Edit Hit Count** or **Edit Log Message**.
Function and instruction breakpoints can be edited the same way in the Breakpoints view, and data breakpoints
offer **Edit Condition** and **Edit Hit Count** there.

- **Condition.** An expression in the debugger's expression syntax (or a BASIC expression on a BASIC breakpoint),
  the same one that evaluate and hover use,
  such as `A == $0D`, `[COUNT] > 3` or `HL >= SCREEN && B != 0`. The breakpoint does nothing while its condition
  is zero. A condition that cannot be evaluated, for instance because it names an unknown label, stops and says
  why.
- **Hit count.** A hit is a time the breakpoint is reached with its condition true. The hit count decides which
  hits stop:

  | Hit count | Stops on |
  | --- | --- |
  | `N` or `=N` | the Nth hit only |
  | `>N`, `>=N` | hits after the Nth, or from the Nth on |
  | `<N`, `<=N` | hits before the Nth, or up to the Nth |
  | `%N` | every Nth hit |

  A hit count in any other form leaves the breakpoint unverified, with a message saying so.
- **Log message.** A logpoint writes its message to the Debug Console, with a link to its line, instead of
  stopping, but only on the hits its condition and hit count let through. `{expression}` puts a value in the
  message, in hex like `$1F`. `{expression,d}` shows it in decimal, `,x` as bare hex, `,b` as binary and `,c` as
  an ASCII character. `{{` and `}}` are literal braces. For example, `char {A,c} at {HL}`. On the Apple III,
  `{sos}` describes the SOS call about to be made, such as `OPEN ".CONSOLE"`. A placeholder that cannot be
  evaluated shows the error in its place. A data breakpoint's log message ends with the access it saw.

  Logpoints write at most 100 lines a second between them, so one in a loop cannot flood the Debug Console. The
  lines past the limit are counted, and a line such as `Retrocore dropped 18 logpoint lines` reports them when
  the second ends or the machine stops. `logpointLimit` in the launch configuration changes the limit, and 0
  lifts it.

Expressions read registers, labels (with `scope::name` for scoped labels), numbers (`$1F`, `0x1F`, `31`),
memory (`[address]` for a byte, `[address].w` for a little-endian word), and C's arithmetic, comparison and
logical operators. Reading memory has no side effects, so a condition never triggers a soft switch.

## Hit counts

Every breakpoint counts its hits from when it is set. The hover on a breakpoint shows them ("Hit 3 times"),
updated at each stop and while the machine runs. Setting the breakpoint's condition or hit count again keeps its
count; launching starts every count over.

The Breakpoints view's title bar has two more buttons while a Retrocore session runs:

- **Retrocore: Show Breakpoint Hit Counts** lists every breakpoint with its hits, condition, hit count and log
  message, and opens a source breakpoint's line when you pick it;
- **Retrocore: Reset Breakpoint Hit Counts** sets every count to zero.

## Data breakpoints

What a data breakpoint watches depends on where it is set:

| From | Watches |
| --- | --- |
| A byte in the Variables view's memory scope (zero page on the Apple II, or the $4000-$40FF communication region on the Model I) | that byte |
| A watch expression `[address]` or `[address].w` | the byte, or both bytes of the word |
| A watch expression that is a label, such as `COUNT` | the byte at the label |
| A watch expression `port N` (Model I) | the Z80 I/O port N |
| A watch expression `[bank:$0400]`, or `bank:$0400` at an address (Apple II) | the byte in that memory bank, only when the memory map reaches it ([Memory.md](Memory.md)) |
| A variable or array element on the BASIC thread | its BASIC value, checked after each statement even if the variable moves in memory |
| **Add Data Breakpoint at Address** | the bytes it asks for, from an address expression |

Registers cannot be watched.

**Break on Value Change** stops on writes (or when a BASIC variable's value changes), **Break on Value Read** on
reads, and **Break on Value Access** on both. A memory write stops even when it writes the value already there,
since a write to a soft switch or video memory matters either way. Every bus access counts, including the 6502's
dummy reads and the second write of a read-modify-write instruction, but not opcode fetches. The stop's
description says what was read or written and where, such as `Wrote $41 to $3C05.`, and the exception peek in
the editor shows it. A port below `$100` matches whatever the Z80 drives on the address bus's high byte, as the
Model I decodes only the low byte.

## Scanline breakpoints

On the Apple II family the Breakpoints view always lists **Video beam reaches a scanline**. Ticked, it stops when the video
beam reaches a scanline and column, every frame, between any two cycles: mid-instruction if need be. Without a
condition it stops at 192:0, where vertical blanking starts. Right-click it and choose **Edit Condition** to pick
the positions, as `scanline:column` with scanlines 0-261 and columns 0-64, such as `100:25`, or several separated
by commas, such as `0:25, 192:0`. Visible fetches run from column 25 to 64 on scanlines 0 to 191. A condition that
does not read leaves the checkbox unverified, saying why. The stop's description names the position, such as
`The video beam reached scanline 192, column 0.`

For a position with its own hit count, condition or log message, add a function breakpoint (**+**) named
`scanline S:C`, `scanline S` (column 0) or `scanline vbl` (192:0); each is its own entry in the view. The Model I
has no beam to stop on, so it lists no such checkbox, and a `scanline` function breakpoint there stays unverified.

## SOS call breakpoints

An Apple III program calls SOS with `BRK`, then the call's number and its parameter list's address. A function
breakpoint (**+**) named `sos` and a call, by the SOS Reference Manual's name or by number, such as `sos OPEN`,
`sos get file info` or `sos $C8`, stops before the program makes that call; `sos` alone stops before every call.
The stop's description names the call, such as `SOS call OPEN ($C8) at $2077.` A name that is not a call leaves
the breakpoint unverified, saying why, and on another machine it stays unverified.

With a log message it traces calls instead of stopping. `{sos}` in the message describes the call with its main
parameters, read as SOS will read them: pathnames and device names, `ref_num`s, device numbers, and the byte
counts of reads and writes. For example, `sos` with the message `{sos} from {PC}` writes lines such as:

```text
OPEN ".D1/SOS.INTERP" from $2077
READ ref 1, 61704 bytes from $209A
GET_DEV_NUM ".CONSOLE" from $84FA
D_CONTROL device 8, code 2 from $8703
```

A call's result is not known until it returns, so the line cannot show it. The logpoint limit applies, and
`logpointLimit: 0` keeps every line of a busy trace.

The **BRK instructions** checkbox stops at the BRKs that are not calls: those SOS would refuse, such as `BRK $00`
from running into empty memory, or one made with zero page anywhere but `$1A00`, as in SOS itself or before it
has loaded. It also stops at SOS's debug call, `BRK $FE`, which a program makes to be stopped.

## Stepping

Stepping stops at breakpoints that are hit in the code it runs, so stepping over a `JSR` or `CALL` stops at a
breakpoint inside the routine. A step that ends on a breakpoint stops as a breakpoint: the hit counts, and the
breakpoint's condition, hit count and log message apply. The Disassembly view steps by instruction: step over
runs a call to its return, step into runs one instruction, and step out returns from the current routine.

Continuing or stepping from a breakpoint moves on without stopping at it again. A data breakpoint, or a scanline
breakpoint, stops between instructions, before the next instruction's breakpoints are checked; continuing
from there checks them first, so a breakpoint on that instruction stops at once.

## Breakpoints in a memory bank

On the Apple II family a function or instruction breakpoint can name a memory bank ([Memory.md](Memory.md)), such as
`bank1:$D000`, `aux:MOVE_DOWN` (on the IIe) or `rom:$FA62`. It stops only while the CPU runs that bank's code at the address,
so `bank1:$D000` does not stop while ROM or bank 2 is mapped there. Source breakpoints already apply only where
their module's memory is mapped.

## The Disassembly view

The Disassembly view decodes memory as it is mapped now, without side effects. Each instruction shows its
bytes, the label at its address, and the source line it came from, from your program or the SDK's ROM sources.
A byte that does not start an instruction shows as `.byte`. Scrolling up decodes backward from the earliest
start that lands on the instructions already shown.

## The debug protocol

The debugger answers the standard DAP requests: `setBreakpoints`, `setFunctionBreakpoints`,
`setInstructionBreakpoints`, `dataBreakpointInfo`, `setDataBreakpoints`, `setExceptionBreakpoints`,
`exceptionInfo` and `disassemble`, with `granularity` on the step requests. At launch it sends a
`capabilities` event with the launched machine's exception filters and `supportsDataBreakpointBytes`. Hit
counts go out as `breakpoint` events with the reason `changed`, whose `message` holds the count.

`dataBreakpointInfo` returns data ids `mem:ADDR:LENGTH`, `bank:BANK:ADDR:LENGTH`, `port:PORT:1` (with the
address in hex) and `basic:NAME` for BASIC variables and array elements. They stay valid across sessions, so
VS Code keeps data breakpoints between launches.

`retro/breakpoints` lists every breakpoint:

```json
{
  "breakpoints": [
    {
      "id": 1, "kind": "function breakpoint", "location": "DISPLAY_CHAR ($0033)",
      "path": null, "line": null, "address": "0x0033",
      "verified": true, "hits": 2, "condition": null, "hitCondition": "2", "logMessage": null, "message": null
    }
  ]
}
```

`{ "reset": true }` sets every count to zero first.

## Testing

`node tools/Test-Breakpoints.mjs` checks every kind on the Model I's Z80 sample and needs nothing external.
It covers hit counts and their events, malformed hit counts, conditions, logpoints, function, instruction and
data breakpoints, the disassembly, instruction stepping, a step stopping inside a call, and a failing
condition. The extension's editor test sets a function breakpoint with a hit count through VS Code's API and
reads its hits.
