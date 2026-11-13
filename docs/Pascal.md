# Apple Pascal

Retrocore runs Apple's Pascal on both of its Apple machines and debugs the programs it runs:

- **Apple III Pascal** 1.1 on the Apple III, from Apple's three disks;
- **Apple Pascal** 1.1 on a 64K Apple II Plus, with the language card.

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

Sector images load read-only, so to keep what the Editor and Compiler write, mount a `.woz` copy. CONTROL-C, which
ends an insertion in the Editor, is the panel's Ctrl+C.

## Debugging

Once the interpreter is running, the debugger finds it in memory, and a **Pascal** thread appears beside the CPU's.

- **Call stack.** The Pascal thread's frames are the procedures running, read from the p-machine's mark stack:
  the one about to run a p-code first, then each caller, down to the system's outer block. Each is named by its
  segment and procedure and its offset from the procedure's entry, as the compiler's listing counts, such as
  `HELLO.2+$0005: SLDC 7`. The top frame shows the p-code about to run.
- **Segment names** come from the code files on the disks in the drives: a segment in memory ends with the same
  bytes as its code file's segment. A segment no disk has is named by number, such as `1.2`.
- **Variables.** Each frame has **Locals**, its parameters and local variables as words numbered as `LDL` numbers
  them, and **Globals**, the program's. The top frame also shows the p-machine's registers: IPC, MP, BASE, JTAB and
  SEG. On the Apple III a register reaching another bank shows its X-byte, such as `x86:$4A3A`.
- **Stepping** on the Pascal thread goes by p-code: **Step Into** stops at the next p-code wherever it is, **Step
  Over** at the next one in the same procedure or a caller, and **Step Out** at the first one back in the caller.
  **Pause** stops at the next p-code.

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
- `--pascal disassemble code [SEGMENT[.PROCEDURE]]` disassembles its p-code, and its assembled procedures as 6502
  code.

A code file is a file's path, or a disk and the file's name: `--pascal disassemble APPLE3.dsk HILBERT.CODE HILBERT.2`.

The libraries behind them are `PascalVolume`, `PascalCodeFile` and `PascalTextFile` in `Retrocore.Media`, and the
p-code and its disassembler in `Retrocore.Pascal`.

## Testing

- `PcodeTests` and `PascalMediaTests` need no files for most of their tests.
- With the disks, `PascalMediaTests` and `PcodeTests` read and disassemble every code file on them;
  `Apple3PascalTests` and `Apple2PascalTests` boot Pascal, compile and run a program, and read its frames.
  Apple III Pascal's disks are with the other Apple III disks (`RETROCORE_APPLE3_DISKS`), and Apple Pascal's in
  `RETROCORE_APPLE2_PASCAL_DISKS` (by default `<cache>\apple2-pascal-disks`, as `UCSD Pascal 1.1_0.dsk` to `1.1_3.dsk`).
- `node tools/Test-PascalDap.mjs` drives the debug host on both machines.

The [backlog plan](backlog/ApplePascal.md) says how this was built and what is still to come.
