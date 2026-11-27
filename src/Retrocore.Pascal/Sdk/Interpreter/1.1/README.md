# Apple Pascal 1.1's interpreter

`SYSTEM.APPLE`, the 6502 interpreter that runs Apple Pascal 1.1's p-code from the language card, as Retrocore native
assembly that assembles byte for byte to the file on 1.1's APPLE1 disk:

```text
Retrocore.Debug --assemble SYSTEM.APPLE.asm SYSTEM.APPLE --config SYSTEM.APPLE.cfg
```

`SYSTEM.APPLE.asm` includes the other files in address order. The file is the language card's 16K in three pieces:
bank 2 at `$D000` (the BIOS's drivers: Disk II, console, printer, remote, slot cards), `$E000`-`$FFFF` (calls,
segments, floating point, unit I/O, Restart and Initialize, the BIOS's stubs and the 6502's vectors) and bank 1 at
`$D000` (the fetch, the dispatch tables and most p-code handlers). The shared definitions are in `Constants.asm`,
`ZeroPage.asm` (the p-machine's registers), `Syscom.asm` (SYSCOM), `Memory.asm` and `Hardware.asm`; `Pcode.asm`, in
the SDK beside it, gives the p-codes' and standard procedures' numbers.

The p-code handlers are in the `Pcodes` scope and the standard procedures in `StandardProcedures`, named for what
they do; each carries its UCSD and Apple names in `Also:` (`ADI` reaches `Pcodes::AddIntegers`). Where the names came
from, and what was decided, is in Retrocore's `docs/conversions/PascalInterpreter.md`.
