# Apple Pascal

Retrocore runs Apple's Pascal on both of its Apple machines and debugs the programs it runs:

- **Apple III Pascal** 1.1 on the Apple III, from Apple's three disks;
- **Apple Pascal** 1.1 and 1.2 on a 64K Apple II Plus, with the language card, and on the IIe.

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

Disks load write-protected. For the Editor and Compiler to write, take the protection off in the **Retro Devices**
view (**Unprotect** on the drive). What the machine writes stays in memory, and the image file does not change.
CONTROL-C, which ends an insertion in the Editor, is the panel's Ctrl+C.

Paste a program into the Editor a few lines at a time: keys pasted faster than a typist types can be lost while the
Editor scrolls, as Pascal's type-ahead overflows.

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
- `--pascal disassemble code [SEGMENT[.PROCEDURE]]` disassembles its p-code, and its assembled procedures as 6502
  code.

A code file is a file's path, or a disk and the file's name: `--pascal disassemble APPLE3.dsk HILBERT.CODE HILBERT.2`.

The libraries behind them are `PascalVolume`, `PascalCodeFile` and `PascalTextFile` in `Retrocore.Media`, and the
p-code and its disassembler in `Retrocore.Pascal`.

## Testing

- `PcodeTests`, `PascalListingTests` and `PascalMediaTests` need no files for most of their tests.
- With the disks, `PascalMediaTests` and `PcodeTests` read and disassemble every code file on them;
  `Apple3PascalTests` and `Apple2PascalTests` boot Pascal, compile and run a program, and read its frames, the latter
  for 1.1 and 1.2 on the II Plus and the IIe. Apple III Pascal's disks are with the other Apple III disks
  (`RETROCORE_APPLE3_DISKS`), and Apple Pascal's in `RETROCORE_APPLE2_PASCAL_DISKS` (by default
  `<cache>\apple2-pascal-disks`, as `UCSD Pascal 1.1_0.dsk` to `1.1_3.dsk` and `1.2_0.DSK` to `1.2_3.DSK`).
- `node tools/Test-PascalDap.mjs` drives the debug host on both machines, and on the Apple III compiles a program
  and stops in its source.

The [backlog plan](backlog/ApplePascal.md) says how this was built and what is still to come.
