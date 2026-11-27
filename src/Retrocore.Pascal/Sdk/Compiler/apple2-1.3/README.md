# Apple Pascal 1.3's Compiler

The source of `SYSTEM.COMPILER`, Apple Pascal 1.3's Compiler, which compiles, assembles and links back to the same
segments as the file on 1.3's APPLE2. It is written to the SDK's [Pascal style](../../../../../docs/PascalStyle.md);
[its conversion log](../../../../../docs/conversions/PascalCompiler13.md) says how it was made.

Start with `COMPILER.TEXT`: its doc says what the Compiler is and how its files are laid out, and it includes the
others in order. `SYSGLOBALS.TEXT`, the system's globals and procedure headings, is in
[`System/apple2-1.3`](../../System/apple2-1.3). `ASSEMBLED.TEXT` is `ScanIdentifier` and `SearchTree` in 6502 code,
for Apple's Assembler.

## Rebuilding it

On an emulated 128K IIe with Apple Pascal 1.3's disks, where `R` is `retrocore --pascal` (or
`dotnet Retrocore.Debug.dll --pascal`), `D` the disks' folder, and `APPLE1-128K.dsk` APPLE1 with APPLE3's 128K
system (`128K.APPLE` and `128K.PASCAL` as `SYSTEM.APPLE` and `SYSTEM.PASCAL`):

```sh
R compile COMPILER.TEXT APPLE1-128K.dsk "$D/UCSD Pascal 1.3_APPLE2.woz" HOST.CODE --includes . --includes ../../System/apple2-1.3 --iie
R assemble-native ASSEMBLED.TEXT "$D/UCSD Pascal 1.3_APPLE1.woz" "$D/UCSD Pascal 1.3_APPLE2.woz" ASM.CODE
R link HOST.CODE ASM.CODE "$D/UCSD Pascal 1.3_APPLE1.woz" "$D/UCSD Pascal 1.3_APPLE2.woz" LINKED.CODE
R extract "$D/UCSD Pascal 1.3_APPLE2.woz" SYSTEM.COMPILER COMPILER.CODE --raw
R compare COMPILER.CODE LINKED.CODE      # The code files' segments are the same.
```

`PascalCompilerSourceTests.CompilerRebuildsSystemCompiler` does the same with `RETROCORE_APPLE2_PASCAL_DISKS` set,
in about two minutes. Without the disks, `CompilerKeepsItsCode` checks the code's shape: names and comments may
change, the code may not.

## Editing it

Each file opens in Apple's Editor on any version: keep a file under about 15,000 bytes (the lint reports one over
16,348) and its lines within 80 columns. A new name follows the style's rules, distinct from the names around it
in its first 8 letters; the lint and the round trip check.
