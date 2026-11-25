# Microsoft 6502 BASIC, AppleSoft and PET BASIC: conversion log

The BASIC sources (plan item B5): the shared Microsoft modules
`src/Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.*.asm`, AppleSoft's
`src/Retrocore.Machines.Apple2/Roms/AppleSoft/AppleSoft*.asm`, and Commodore's
`src/Retrocore.Machines.Commodore/Roms/Basic/{Basic1,Basic2,Basic4,Commodore.*}.asm`. Together they assemble eight
ROMs byte for byte:

| Tag | Build | Root and switches |
| --- | --- | --- |
| II+ | AppleSoft, Apple II Plus | `AppleSoft.asm`, ENHNCD = 0, APLPLS = 1 |
| IIe | AppleSoft, original IIe | `AppleSoft.asm`, ENHNCD = 0, APLPLS = 0 |
| IIeE | AppleSoft, enhanced IIe | `AppleSoft.asm`, ENHNCD = 1 |
| P1 | PET BASIC 1, original | `Basic1.asm`, REVISD = 0 |
| P1R | PET BASIC 1, revised | `Basic1.asm`, REVISD = 1 |
| P2 | PET BASIC 2 | `Basic2.asm` |
| P4 | PET BASIC 4, original | `Basic4.asm`, REVISD = 0 |
| P4R | PET BASIC 4, revised | `Basic4.asm`, REVISD = 1 |

"AS" is the three AppleSoft builds, "PET" the five PET builds, "all" the eight. The unconverted sources keep
Microsoft's six-letter names. This log covers steps 1 to 3 of [the method](../ConvertingSources.md): the inventory, the
sources and citations, and the rename table, [BasicRenames.md](BasicRenames.md), a draft for the owner's review.
The conversion itself (step 4) is logged below, under "Step 4: the conversion", one step of X8 at a time.

## Decisions accepted by the owner

- D1. Code several vendors inherited from Microsoft stays in one shared module; each difference is a named switch or
  parameter with a one-line reason.
- D2. The modules keep their macros. A tool change (since merged, #132) makes an `Also:` in a macro that is expanded
  once per build apply at that expansion; a macro expanded more than once gives its old names in prose.
- D3. Historical names take the standard form, `;; Also: NAME (KEY)`, with bibliography keys only for documents in
  hand and checked. A vendor's old name on shared code must resolve only in that vendor's builds, so it goes in the
  vendor's own file as an alias with `Also:`. Each build is tested to resolve only its own names.
- D4. Rename to full words; Microsoft's and each vendor's names stay in `Also:`.
- D5. In a shared module, an inline `.if` on a named switch carries a comment naming which builds take which branch.
  A shared routine states the contract that holds in every build; a variant that keeps less is its own `.proc`.
- D6. The MACRO-10 overlays (`applesoft.mac`, `Basic1.mac`, `Basic2.mac`, `Basic4.mac`) stay as the per-module byte
  oracle.
- D7. Shared sources are found by a general rule, not by folder name.
- D8. Microsoft's code is MIT, with its license kept and shipped. Listings used for checking stay out of the
  repository.

## Step 1: the inventory

Made by script, from the sources before the conversion, with the repository's assembler. Nothing from it is committed.

- **Per build:** each of the eight builds was assembled with the repository's assembler (the native roots, with
  the switches above), and its symbol table dumped with each symbol's defining file and line, and its source map
  with each statement's macro-expansion chain.
- **Per file:** every definition in the native files was listed by a text scan: labels (column 0), equates,
  `.ifndef` defaults (switches), `.set` names, macros and macro parameters, with the macro each is inside.
- **Coverage:** every symbol of every build matched a text definition at the same file and line, except the
  predefined switches (ENHNCD, APLPLS, REVISD). 138 text definitions are in no build's table: 124 lines of the
  `.set` counter Q and AppleSoft's first `BUFOFS .set` (the table keeps a name's last value), nine `.ifndef` defaults that the builds predefine or override,
  three alternate equates (Commodore's CHARAC and TEMPPT for other layouts) and one label (`LIST_QUOTE_CHECK`, in a
  branch no build takes).
- **Macros:** each macro's expansion sites per build come from the source maps. Every macro that defines a label is
  expanded once in each build that has it (x1), so D2's tool change covers all of them. FLOAT_ONE is expanded
  three times and defines no label.
- **Rows:** one row per name per file (a name defined on several lines of one file, under `.if`, is one row):
  2,566 text definitions, 2,411 rows, 2,083 distinct names.
- **Bytes:** the AppleSoft native builds equal the overlay builds over the whole 64 KiB image; the PET builds equal
  theirs over the ROM ranges, differing only in the page-zero initial values the overlays emit.

Definitions per build (each row counted once per build it is in):

| Build | Labels | Equates | Switches | `.set` | Macros | Macro parameters | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| II+ | 903 | 294 | 6 | 2 | 76 | 108 | 1389 |
| IIe | 903 | 294 | 6 | 2 | 76 | 108 | 1389 |
| IIeE | 913 | 294 | 7 | 2 | 76 | 108 | 1400 |
| P1 | 771 | 197 | 86 | 0 | 97 | 168 | 1319 |
| P1R | 771 | 197 | 86 | 0 | 97 | 168 | 1319 |
| P2 | 757 | 201 | 23 | 0 | 94 | 167 | 1242 |
| P4 | 1032 | 306 | 23 | 0 | 104 | 167 | 1632 |
| P4R | 1040 | 306 | 23 | 0 | 104 | 167 | 1640 |

Rows per module (each row once; "Builds" is the build set most of the module's rows are in):

| Module | Builds | Labels | Equates | Switches | `.set` | Macros | Parameters | Rows |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MsBasic.AdditionCore | all | 37 | 0 | 0 | 0 | 2 | 0 | 39 |
| MsBasic.ArithmeticCore | all | 30 | 0 | 0 | 0 | 1 | 1 | 32 |
| MsBasic.ArrayMultiplication | all | 5 | 0 | 0 | 0 | 0 | 0 | 5 |
| MsBasic.Arrays | all | 30 | 0 | 0 | 0 | 1 | 3 | 34 |
| MsBasic.Assignment | all | 11 | 0 | 0 | 0 | 2 | 2 | 15 |
| MsBasic.CharacterReader | all | 5 | 0 | 0 | 0 | 2 | 1 | 8 |
| MsBasic.CommandCore | all | 12 | 0 | 0 | 0 | 4 | 4 | 20 |
| MsBasic.ConversionCore | all | 22 | 0 | 0 | 0 | 1 | 0 | 23 |
| MsBasic.DecimalInputCore | all | 23 | 0 | 0 | 0 | 1 | 1 | 25 |
| MsBasic.Dim | all | 4 | 0 | 0 | 0 | 0 | 0 | 4 |
| MsBasic.ExpressionCore | all | 24 | 0 | 0 | 0 | 1 | 1 | 26 |
| MsBasic.FloatConstants | all | 21 | 0 | 0 | 0 | 7 | 3 | 31 |
| MsBasic.FloatingPoint | AS | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| MsBasic.For | all | 5 | 0 | 0 | 0 | 0 | 0 | 5 |
| MsBasic.IntegerConversion | all | 6 | 0 | 0 | 0 | 2 | 2 | 10 |
| MsBasic.LineNumber | all | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| MsBasic.LineSearch | all | 6 | 0 | 0 | 0 | 0 | 0 | 6 |
| MsBasic.Lister | all | 22 | 0 | 0 | 0 | 4 | 12 | 38 |
| MsBasic.Logarithm | all | 4 | 0 | 0 | 0 | 1 | 0 | 5 |
| MsBasic.MemoryAccess | all | 11 | 0 | 0 | 0 | 4 | 6 | 21 |
| MsBasic.MemoryManagement | all | 17 | 0 | 0 | 0 | 1 | 1 | 19 |
| MsBasic.MovementCore | all | 16 | 0 | 0 | 0 | 1 | 0 | 17 |
| MsBasic.Next | all | 15 | 0 | 0 | 0 | 1 | 2 | 18 |
| MsBasic.OperandEvaluation | all | 31 | 0 | 0 | 0 | 4 | 4 | 39 |
| MsBasic.OperatorTable | all | 4 | 0 | 0 | 0 | 1 | 3 | 8 |
| MsBasic.OutputCore | all | 37 | 0 | 0 | 0 | 1 | 2 | 40 |
| MsBasic.Print | all | 5 | 0 | 0 | 0 | 1 | 4 | 10 |
| MsBasic.ProgramReset | all | 12 | 0 | 0 | 0 | 5 | 12 | 29 |
| MsBasic.ProgramTransfers | all | 26 | 0 | 0 | 0 | 5 | 6 | 37 |
| MsBasic.RandomCore | all | 7 | 0 | 0 | 0 | 1 | 1 | 9 |
| MsBasic.Relational | all | 8 | 0 | 0 | 0 | 1 | 1 | 10 |
| MsBasic.SimpleFunctions | all | 5 | 0 | 0 | 0 | 1 | 1 | 7 |
| MsBasic.StatementFlow | all | 18 | 0 | 0 | 0 | 3 | 2 | 23 |
| MsBasic.StringConcatenation | all | 19 | 0 | 0 | 0 | 1 | 1 | 21 |
| MsBasic.StringConversion | all | 2 | 0 | 0 | 0 | 1 | 0 | 3 |
| MsBasic.StringFunctions | all | 25 | 0 | 0 | 0 | 1 | 4 | 30 |
| MsBasic.StringGarbageCollection | AS P1 P1R P2 | 20 | 0 | 0 | 0 | 1 | 3 | 24 |
| MsBasic.StringOutput | all | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| MsBasic.StringStorage | all | 14 | 0 | 0 | 0 | 2 | 3 | 19 |
| MsBasic.StringStorage.Classic | AS P1 P1R P2 | 4 | 0 | 0 | 0 | 1 | 0 | 5 |
| MsBasic.StringStorage.Linked | P4 P4R | 6 | 0 | 0 | 0 | 1 | 0 | 7 |
| MsBasic.Switches | all | 0 | 0 | 7 | 0 | 0 | 0 | 7 |
| MsBasic.TranscendentalCore | all | 32 | 0 | 0 | 0 | 5 | 0 | 37 |
| MsBasic.UserFunctions | all | 9 | 0 | 0 | 0 | 1 | 1 | 11 |
| MsBasic.VariableInput | all | 25 | 0 | 0 | 0 | 2 | 8 | 35 |
| MsBasic.VariableLookup | all | 45 | 0 | 0 | 0 | 3 | 14 | 62 |
| AppleSoft | none | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| AppleSoft.AppleCommands | AS | 41 | 0 | 0 | 0 | 0 | 0 | 41 |
| AppleSoft.ControlFlow | AS | 23 | 0 | 0 | 0 | 0 | 0 | 23 |
| AppleSoft.DispatchTables | AS | 7 | 45 | 0 | 1 | 0 | 0 | 53 |
| AppleSoft.Equates | AS | 0 | 243 | 0 | 0 | 0 | 0 | 243 |
| AppleSoft.ErrorAndInput | AS | 37 | 0 | 0 | 1 | 0 | 0 | 38 |
| AppleSoft.Expressions | AS | 7 | 0 | 0 | 0 | 0 | 0 | 7 |
| AppleSoft.FloatAliases | AS | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| AppleSoft.HighResolution | AS | 80 | 2 | 0 | 0 | 0 | 0 | 82 |
| AppleSoft.Initialization | AS | 5 | 0 | 0 | 0 | 0 | 0 | 5 |
| AppleSoft.InputOutput | AS | 16 | 0 | 0 | 0 | 0 | 0 | 16 |
| AppleSoft.InterpreterAliases | AS | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| AppleSoft.NumericConversion | AS | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| AppleSoft.PlatformHelpers | IIeE | 27 | 0 | 0 | 0 | 0 | 0 | 27 |
| AppleSoft.Print | AS | 21 | 1 | 0 | 0 | 0 | 0 | 22 |
| Basic1 | P1 P1R | 0 | 2 | 76 | 0 | 0 | 0 | 78 |
| Basic2 | P2 | 1 | 7 | 0 | 0 | 0 | 0 | 8 |
| Basic4 | P4 P4R | 1 | 7 | 4 | 0 | 0 | 0 | 12 |
| Commodore.Basic1Patches | P1 P1R | 15 | 0 | 0 | 0 | 2 | 0 | 17 |
| Commodore.Basic4DiskCommands | P4 P4R | 108 | 7 | 0 | 0 | 1 | 0 | 116 |
| Commodore.Basic4DiskParser | P4 P4R | 49 | 0 | 0 | 0 | 1 | 0 | 50 |
| Commodore.Basic4Extension | none | 0 | 0 | 3 | 0 | 1 | 1 | 5 |
| Commodore.Basic4Monitor | P4 P4R | 77 | 0 | 0 | 0 | 1 | 0 | 78 |
| Commodore.Basic4Patches | P4R | 9 | 0 | 0 | 0 | 1 | 1 | 11 |
| Commodore.Basic4Record | P4 P4R | 13 | 0 | 0 | 0 | 1 | 0 | 14 |
| Commodore.Basic4RomEnd | P4 P4R | 3 | 0 | 0 | 0 | 1 | 0 | 4 |
| Commodore.Basic4SystemEquates | P4 P4R | 0 | 85 | 0 | 0 | 0 | 0 | 85 |
| Commodore.ChannelInput | PET | 18 | 0 | 0 | 0 | 3 | 7 | 28 |
| Commodore.ChannelPrint | PET | 30 | 0 | 0 | 0 | 4 | 9 | 43 |
| Commodore.CommandInput | PET | 34 | 0 | 0 | 0 | 4 | 9 | 47 |
| Commodore.DispatchTables | PET | 13 | 38 | 0 | 0 | 1 | 4 | 56 |
| Commodore.Equates | PET | 0 | 160 | 17 | 0 | 0 | 0 | 177 |
| Commodore.FloatAliases | PET | 0 | 8 | 0 | 0 | 0 | 0 | 8 |
| Commodore.FloatingPoint | P2 | 6 | 0 | 0 | 0 | 0 | 0 | 6 |
| Commodore.Initialization | PET | 11 | 0 | 0 | 0 | 4 | 19 | 34 |
| Commodore.InterpreterAliases | PET | 0 | 6 | 0 | 0 | 0 | 0 | 6 |
| Commodore.StatementDispatch | PET | 12 | 0 | 0 | 0 | 2 | 7 | 21 |
| Commodore.StringAssignment | P4 P4R | 12 | 0 | 0 | 0 | 3 | 1 | 16 |
| Commodore.StringGarbageCollection | P4 P4R | 21 | 0 | 2 | 0 | 1 | 0 | 24 |
| Commodore.TimeAssignment | PET | 6 | 0 | 0 | 0 | 1 | 1 | 8 |
| Commodore.VariableEvaluation | PET | 12 | 0 | 0 | 0 | 1 | 3 | 16 |
| **All** | | 1402 | 614 | 111 | 2 | 111 | 171 | 2411 |

## Step 2: sources and citations

Documents fetched for checking are in a private scratch folder only; none of their text is in the repository. A name
is cited only where the check below found that the document gives that name for that thing.

| Proposed key | Document | How it was checked | Rows cited |
| --- | --- | --- | ---: |
| M6502 | Microsoft's BASIC M6502 8K version 1.1 source (MACRO-10), the repository's `m6502.asm` (the same text, but for whitespace, as cbmsrc's `BASIC_PET_V2_MICROSOFT/M6502.MAC`) | Each overlay build (`.mac` on `m6502.asm`) assembled; a name is cited for a build when `m6502.asm` defines it and the overlay build gives it the same value as the native build. Where the overlay's definition is in the vendor's `.mac` (973 build-names), the value match proves only that the overlay kept Microsoft's label on the code that replaced Microsoft's; the review checked each such case for the `.mac` replacing the very line that defines the name, and removed M6502 from the nine rows where it does not (BASIC 4's array-creation code, BASIC 1's patch routines). No name had a different value. | 1,242 |
| ASTIL | Apple II Technical Information Library, "Applesoft: Internals" articles (index to routines 1-4, page zero memory map 1-2, and the routine articles) | Names and addresses parsed from the index, the page-zero map and the routine articles' name-and-address lists; cited where the address equals the AppleSoft builds' value. Names found only in prose are "spelling only". | 181 |
| AS82 | Apple's Applesoft source listing, dated 5/26/1982 (Roger Wagner Publishing's reference copy, scanned for KansasFest) | Only the archive's OCR text could be fetched (the scan's files are on a host the network refuses). The OCR is heavily damaged: a name is cited only where its symbol tables give the same value (19 rows), and 13 other names at native addresses were read from them by hand (MISMTCH, NXLINK, BILLION ...); 249 rows' names appear in the text but could not be tied to the thing, and are "spelling only". The listing's header limits it to the owner of the copy of Applesoft it came from, and Apple as author and the date rest on the archive's description. | 19 |
| ASRM78 | Apple's Applesoft II Reference Manual (Extended Precision Floating Point BASIC Language), August 1978 | OCR text: its memory map gives CHRGET at $B1. It also names ERRFLG, the ONERR flag, but at location 222, where the ROM's is 216 (the Applesoft II BASIC Programming Reference Manual's example uses 216): a candidate for X12's kind of question, not cited. The IIe Applesoft BASIC Programmer's Reference Manuals (1982, vols. 1 and 2) give no internal names. | 1 |
| CBM4S79 | Commodore PET BASIC 4 source, listing dated July 23, 1979: a pre-release, OCRed and reconstructed by Martin Hoffmann-Vetter (cbmsrc `BASIC_PET_V4_1979-07-23`) | Its addresses differ from the ROMs, so page-zero names are checked by value and code labels by the code at the label (the review compared each label's first instructions and data bytes, and added 29 rows the first check had missed). | 897 |
| K4S79 | Commodore PET 2001 operating system, version 4.0 (July 25, 1979), listing of October 23, 1979 (cbmsrc `KERNAL_PET_4.0_1979-10-23`): the whole operating system, including BASIC 4's $D000 ROM (the monitor and the disk-command code) | Assembled for RAM ($8000 lower); cited where the address plus $8000 (or the page-zero value) equals the native build's. | 365 |
| HV1, HV1R, HV2, HV4, HV4R | Martin Hoffmann-Vetter's reconstructions of PET BASIC 1, 1 revised, 2, 4 and 4 revised (cbmsrc `BASIC_PET_V1_REC` ... `BASIC_PET_V4R_REC`), which build the ROMs | Assembled by a script of ours that reads their text (Commodore's assembler was not run) and reproduces the ROMs' bytes, but for the checksum bytes. A name is cited for its build where its address or value equals the native one. 15 names differ in value and are not cited: 12 name the kernal's jump-table entries there (DOPEN, APPEND ...), not BASIC 4's routines; ISVAR, GETDTL and NUMLEV differ for other reasons. | 869-903 each |
| HVK4 | Hoffmann-Vetter's reconstruction of the PET 4.0 operating system (cbmsrc `KERNAL_PET_4.0_REC`) | As HV*: names at the BASIC 4 ROMs' addresses. | 366 |

cbmsrc is <https://github.com/mist64/cbmsrc>, checked at commit 01bd60f162ef92212ef0cb67546ae8f42be34168.
Its reconstructions of BASIC 1 name the ROMs they build 901439-01, -05, -02, -06 and -03 (-09 for the revised first
ROM), where the repository, its C# and its docs name the chips it builds 901447-01 to -05 (and -09). Assembled, HV1
and HV1R equal the repository's original and revised BASIC 1 builds in every byte they share, $C000 to $E1E0: the
BASIC code in the two series is the same. The reconstructions do not cover the rest of the last chip (the editor
after $E1E0), and the documents in hand do not say how the two series differ. Its notes
say that Microsoft built BASIC 1, 1 revised and 2, and that the reconstructions of BASIC 1 in Commodore's assembler
format "never existed": they carry Commodore's later names back to BASIC 1's code for comparison. HV1 and HV1R are
still documents that give those names for that code, but their names are a reconstructor's, not Commodore's or
Microsoft's of 1977. They are cited on that understanding (decision X12).

Not used: the 1985 edition of Scot Kamins' Applesoft BASIC Programmer's Reference Manual (Apple's official manual;
the 1982 IIe volumes, also his, were read) is lending-only at the archive and could not be read. Apple Orchard's "Applesoft Internal Entry Points" and S-C's Applesoft
disassembly were not fetched; the sources' comments do not cite them, and no name in the table depends on them.

### Proposed bibliography rows

The rows as proposed. All are now in `docs/Bibliography.md`, whose rows, with some titles worded differently,
are the ones that count: all but ASRM78 from #133, and ASRM78 from the workspace step, whose AppleSoft.Equates.asm
is the first converted source to cite it.

| Key | Title | Year | Publisher | Link |
| --- | --- | --- | --- | --- |
| M6502 | BASIC M6502 8K version 1.1 source (MACRO-10), published under the MIT license | 1978 | Microsoft | <https://github.com/microsoft/BASIC-M6502> |
| ASTIL | Apple II Technical Information Library: "Applesoft: Internals" articles | | Apple Computer | <https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Companies/Apple/Documentation/Apple%20Technical%20Information%20Library/> |
| AS82 | Applesoft source listing, May 26, 1982 (Roger Wagner Publishing's reference copy) | 1982 | Apple Computer | <https://archive.org/details/roger_wagner_applesoft_source> |
| ASRM78 | Applesoft II Reference Manual | 1978 | Apple Computer | <https://archive.org/details/Applesoft_II_Reference_Manual_1978-08_Apple> |
| CBM4S79 | PET BASIC version 4 source, listing of July 23, 1979 (OCRed and reconstructed by Martin Hoffmann-Vetter) | 1979 | Commodore | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_1979-07-23> |
| K4S79 | PET 2001 operating system version 4.0 (July 25, 1979), listing of October 23, 1979 (OCRed and reconstructed by Martin Hoffmann-Vetter) | 1979 | Commodore | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/KERNAL_PET_4.0_1979-10-23> |
| HV1 | PET BASIC 1 (original first ROM), reconstructed source (the document names its ROMs 901439-01 ...; it assembles to the same bytes as the repository's 901447-01 build) | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V1_REC> |
| HV1R | PET BASIC 1 (revised first ROM), reconstructed source (the document names its ROMs 901439-09 ...; it assembles to the same bytes as the repository's 901447-09 build) | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V1R_REC> |
| HV2 | PET BASIC 2 (901465-01, -02, 901447-24), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V2_REC> |
| HV4 | PET BASIC 4 (901465-19, -20, -21), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_REC> |
| HV4R | PET BASIC 4 revised (901465-23, -20, -21), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4R_REC> |
| HVK4 | PET operating system 4.0 (901465-21, 901447-29, 901465-22), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/KERNAL_PET_4.0_REC> |

The sources' comments cited "Apple TIL 76/79" and "Commodore BASIC 4 code18" in prose; #133 cites them in the alias
files by these keys, with the locator in prose beside each (`COMBYTE (ASTIL, AS82), in ASTIL's article 76`), and the
conversion moves them into `Also:` entries.

## Step 3: the rename table

[BasicRenames.md](BasicRenames.md) has all 2,411 rows. It was drafted in seven parts with one set of rules and one
glossary for the shared workspace (below), then merged, then corrected after two independent reviews (below). Of the
rows, 2,142 get a new name, 254 keep theirs (the SDK's own switches and macro parameters, and the names C# predefines:
REVISD, ENHNCD, APLPLS, TIME, EXTIO, DISKO, REALIO; X15 settled the names tests predefine) and 15 are dropped. A DROP
removes the definition: either nothing uses it and no document names it; or it duplicates another definition, whose
`Also:` then takes its documented name (KIMY, TRMNO1); or its uses can do without it, and its documented name goes in
prose (ZSTORD, whose WAIT call can pass STORDO's new name, A-Q6; Q, an assembly-time counter, C-Q8); or it is a question
(REDDY and GOTK, C-Q8; LINWID, D-Q3). Apart from the 139 renamed rows with no Documents entry (SDK macros, macro
parameters and switches), 352 renamed rows have no checked document name, the rows W2 cites as UNKN: 249 that no listed
document gives, 67 that a document matches only in spelling, and 36 whose documents give only other names. 287 of them
are in AppleSoft's builds only (AS, IIeE, II+ IIe): AppleSoft's copies of Monitor and IIe names (which carry the Apple
manuals' names once they come from IIeEquates, decision X10), AppleSoft-only labels the damaged AS82 text could not
confirm, and the SDK's own labels.

The parts: A, the floating-point package; B1, the shared program and statement modules; B2, the shared expression,
variable and string modules; C, the vendors' own copies of the interpreter (AppleSoft and Commodore side by side);
D, the workspace and build switches; E, AppleSoft's statements and graphics; F, BASIC 4's disk, monitor and string
code and BASIC 1's patches. Their own questions follow the cross-cutting ones, numbered by part (A-Q1 ...).

## Cross-cutting decisions

Settled by the owner on 2026-11-23, each as recommended in the question below it. The table follows them.

- X1. Top level holds the documented entries, the dispatch targets several modules share, the error entries
  (`SyntaxError`, `ReportError` ...), the shared workspace and the kernal and Monitor entries. The families are scopes:
  `Statements` (handlers named for their keyword), `Functions`, `Operators`, `Float`, `Strings`, `Variables`,
  `HighRes`, `Disk` and `Monitor`. A family cut by the ROM layout is opened and continued in the vendors' composition
  files around the macro calls; where one macro emits a family's piece, the macro opens and closes the scope itself.
- X2. A label another routine enters in the middle of a routine is an entry of the routine it sits in
  (`FindLine::Done`), listed in its `Entry:` section; a separate `.proc` only where the code before it is another
  routine or a table needs the address.
- X3. One shared file of layouts: `Variable`, `ArrayHeader`, `StringDescriptor` (`DESCRIPTOR_SIZE`), `ForFrame`
  (`FOR_FRAME_SIZE`), `GosubFrame`, `OperatorEntry`, `ProgramLine`, `FunctionDefinition`; BASIC 4's string back-link
  in Commodore's file.
- X4. Tokens are `TOKEN_<KEYWORD>`, with role names for range bounds (`TOKEN_FIRST_FUNCTION`); error codes are
  `ERROR_<MESSAGE>`, which are also the message offsets (ERRBD, BAD DATA in BASIC 1 and FILE DATA later, is
  `ERROR_FILE_DATA`); message labels are `<Name>Message`; precedences are `PRECEDENCE_*` and input modes
  `INPUT_MODE_*`. Each token and error code is defined once, in its table's file, and the workspace files' copies
  join it.
- X5. Each vendor's names for shared definitions go in one historical-names file per vendor
  (`AppleSoft.HistoricalNames.asm`, `Commodore.HistoricalNames.asm`), replacing the alias files: a scoped alias per
  entry (`Commodore::SquareRootOfHalf = Float::SquareRootOfHalf`) with `Inherit:` and the vendor's `Also:`. Where an
  Apple name and Microsoft's name for different definitions clash in one build, Microsoft's keeps `Also:` and
  Apple's is in prose. The vendors' Monitor and kernal synonyms (CQINLN, MPLOT ...) go in the same file; a vendor's
  own files need none, since their `Also:` goes on their definitions.
  The file holds the alias files' entries and also every vendor-only name the table lists under "other names here"
  on a shared definition (its D3 column: "aliases: ..."), which becomes a new entry at conversion: for example
  `AppleSoft::Billion` for BILLION (AS82, at NZMIL's $ED14 in every AppleSoft build), `AppleSoft::DivideArg` for
  FIDVT (ASTIL) and `AppleSoft::Mismatch` for MISMTCH (AS82, at `RequireType::Mismatch`).
- X6. The vendor-only files convert in the same effort, each right after the shared modules it calls, referring to
  converted names by their old ones meanwhile (they resolve through `Also:`).
- X7. One job, one name in both vendors' files; each build's definition carries that build's documents' names, and a
  shared definition's vendor-only names go in the vendor's file (X5). Address-generated reconstruction names
  (LCA5A) are dropped; HV's PATCHn names are kept.
- X8. The PRs go: the prerequisites (`Also:` in macros, B4's helper, lookups by `Also:` in the debug hosts), the
  workspace, the math package, the shared program modules, the shared expression and string modules, the vendors'
  interpreter copies, then AppleSoft's and Commodore's own files.
- X9. B4's helper resolves either name through `Also:`, the debug hosts use the same lookup, and each moves to the
  new names in the PR that renames the definition.
- X10. Revised by the owner (2026-11-24), after including MonitorEntries.asm brought in Monitor names that clash with
  AppleSoft's (E-8): after DOS's X7 pattern, AppleSoft defines the Monitor entries it calls itself, with `Inherit:`, but
  unlike DOS it includes `IIeEquates.asm` only; AppleSoft.Equates otherwise keeps only BASIC's workspace. For
  IIeEquates' clashes, RNDX is `RandomValue` and the unused KIMY is dropped.
- X11. The accumulators keep the field's short terms: `Fac`, `FacExponent`, `FacMantissa1`-`4`, `FacSign`,
  `FacExtension`, the same for `Arg`, and `ResultSign`; the `Float` routines name their operands by these
  (`AddPacked`, `AddArg`, `LoadFac`).
- X12. HV1 and HV1R are cited where they give a name, with their origin noted in the bibliography.
- X13. A statement keeps its keyword, split at the words a reader sees in it: `GoSub`, `GoTo`, `OnErr`, `HColor`,
  `DOpen`, `DClose`, `DLoad`, `DSave`.
- X14. The kernal's jump-table entries and the kernal routines BASIC calls are top level with a `Kernal` prefix
  (`KernalOpen`, `KernalTalk`); the three vectors shared code calls are `CheckStop`, `GetCharacter` and
  `CloseAllFiles`. The screen editor's PRT keeps the Monitor's `ScreenOut`.
- X15. The switches the tests predefine are renamed as drafted, and the tests change in the PR that renames each;
  the roots may assert that no old name is predefined.
- X16. The table writes every local by its full path (`Statements::Let::Number`, `Strings::CollectGarbage::NextArray`).

The table was normalized on 2026-11-23: 21 rows for X13 (6 statement names and their locals), 122 for X16 (locals
given their scope) and 26 for X14 (the kernal routines BASIC 4 calls, such as `KernalTalk`, which the draft had left
unprefixed).


## The cross-cutting questions, as put

Each had a recommendation and its alternatives; the parts' own questions below go into more detail.

### X1. Scopes, and what stays top level

- **Recommendation:**
  - **Top level** holds what other code and programs reach: the documented entries (ASTIL's index, Microsoft's
    math-package entry list), the dispatch targets shared by several modules, the error entries (`SyntaxError`,
    `ReportError` ...), the shared workspace, and the kernal and Monitor entries.
  - **Family scopes:** `Statements` (handlers named for their keyword, as DOS's `Commands::Catalog`), `Functions`,
    `Operators`, `Float` (the math package, the style guide's own example of a scope), `Strings` (the string
    package and both collectors), `Variables` (variable and array internals), `HighRes` (AppleSoft, beside the
    Monitor's `LowRes`), `Disk` (BASIC 4's disk helpers) and `Monitor` (BASIC 4's machine-language monitor).
  - **Routines** are `.proc`s; their labels are locals (`FindLine::Done`).
  - **Placement:** the scopes open and continue in the vendors' composition files around the macro calls where a
    family is cut by the ROM layout (part A-Q2), or inside the macro where one macro emits a family's piece
    (B1-Q9).
- **Alternatives:** top-level names for the documented entries (about 70 in the math package alone, all needing a
  prefix), per Monitor decision 9; or fewer scopes (`Statements` and `Functions` only).
- Monitor decision 18 (a subsystem's routines stay in their family even when programs call them) is the precedent
  for `Float`, `Strings` and `HighRes` holding ASTIL entries (`Float::AddPacked`, `HighRes::Position`).

### X2. Labels other routines enter in the middle of a routine

Every part met this: Microsoft branches into another routine's `rts`, loop or tail far more than the Monitor or DOS
do (FLNRTS, STKRTS, CONTRT, NOTABR, ERRGO2 ...). The settled rule says such a label is a separate `.proc` or a
scope-level label.

- **Recommendation:** write a mid-routine target as an entry of the routine it sits in (`FindLine::Done`,
  `Float::Round::Increment`), listed in that routine's `Entry:` section. Split off a separate `.proc` only where the
  code before the label is another statement or routine, or a dispatch table needs the address (as each part did:
  `Statements::StopOrEnd`, `Float::AddArg` ...).
- **Alternative:** follow the rule literally: one-instruction procs for shared `rts` exits, and scope-level labels in
  `Float` and `Statements` for the rest. That splits loops across procs.
- This is a new kind of precedent for the conversions. Settled; adding it to ConvertingSources' structure techniques is
  a follow-up for ConvertingSources.md.

### X3. Structs for the data layouts

- **Recommendation:** one shared file of layouts, included by both vendors:
  - `Variable` (7 bytes): `NAME` (2; bit 7 of each byte gives the type), `VALUE` (5);
  - `ArrayHeader` (5 bytes): `NAME` (2), `LENGTH` (2), `DIMENSIONS` (1), then the bounds, high byte first;
  - `StringDescriptor` (3 bytes): `LENGTH`, `ADDRESS`; `DESCRIPTOR_SIZE` is its `.sizeof`, `Also: STRSIZ (M6502)`;
  - `ForFrame` (18 bytes): `TOKEN`, `VARIABLE`, `STEP` (5), `STEP_SIGN`, `LIMIT` (5), `LINE`, then the text
    pointer stored high byte first (`TEXT_POINTER_HIGH`, `TEXT_POINTER`), with `FOR_FRAME_SIZE`,
    `Also: FORSIZ (M6502)`;
  - `GosubFrame` (5 bytes), `OperatorEntry` (3 bytes: `PRECEDENCE`, `HANDLER` minus one), `ProgramLine` (`LINK`,
    `NUMBER`, text) and `FunctionDefinition` (DEF FN's value);
  - BASIC 4's string back-link (2 bytes after a string), in Commodore's file.
  - The stack-relative offsets (`$0109,x`) become `Stack + 1 + ForFrame::STEP_SIGN`, and so on.
- **Alternatives:** only the four the plan names (variable entry, array header, string descriptor, FOR frame), the
  rest as constants; or no structs, with named offsets.

### X4. Named constants for tokens, error codes and message offsets

- **Recommendation:**
  - **Tokens:** `TOKEN_<KEYWORD>` (`TOKEN_FOR`, `TOKEN_GOSUB`), with role names where the code uses a token as a
    range bound (`TOKEN_FIRST_FUNCTION` for ONEFUN, `TOKEN_LAST_SIMPLE_FUNCTION` for LASNUM).
  - **Error codes:** `ERROR_<MESSAGE>` (`ERROR_NEXT_WITHOUT_FOR`, `ERROR_SYNTAX`). In BASIC the error code is the
    message's offset in the message table, so one set serves both, unlike DOS's ERROR_*/MESSAGE_* (X11 in the DOS log,
    `docs/conversions/Dos.md`, which comes with the DOS conversion). The message labels are `<Name>Message`
    (`ReadyMessage`, `BreakMessage`).
  - **Placement:** one definition each, in the dispatch-tables file where the table defines it. The workspace files'
    copies (PI, PLUSTK, MINUTK, ERROV, ERRDV0) join them.
  - **Precedences:** `PRECEDENCE_*` for the operator table (B1-Q2).
  - **Input modes:** `INPUT_MODE_*` for InputMode's values (B2-Q10).
- **Alternatives:** keyword names for the range bounds (`TOKEN_SGN`); MESSAGE_* for the offsets, as DOS.
- ERRBD is BAD DATA in BASIC 1 and FILE DATA later: `ERROR_FILE_DATA` (C-Q5).

### X5. What the alias files become

Today `AppleSoft.FloatAliases`, `AppleSoft.InterpreterAliases`, `Commodore.FloatAliases` and
`Commodore.InterpreterAliases` define equates (`SQR05 = SQRHLF`) for vendors' names of shared code.

- **Recommendation:** each vendor gets one file of its historical names for shared definitions
  (`AppleSoft.HistoricalNames.asm`, `Commodore.HistoricalNames.asm`), replacing the alias files. Each entry is a
  scoped alias that carries the vendor's names in `Also:` and inherits the target's documentation:

  ```asm
  ;; Inherit: <Float::SquareRootOfHalf>
  ;; Also: SQR05 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
  Commodore::SquareRootOfHalf = Float::SquareRootOfHalf
  ```

  The old name then resolves only in that vendor's builds (D3). The scope keeps the alias names out of the top
  level. The table gives each alias-file entry its scoped name (`Commodore::SquareRootOfHalf`, `AppleSoft::PrintFac`),
  and its D3 column marks each shared definition that has one.
- **Alternatives:**
  - a directive that attaches an `Also:` to another definition, without a second name (a tool change);
  - plain equates (`SQR05 = Float::SquareRootOfHalf`). This works today, but the editor would treat the old names as
    ordinary symbols: no historical-name hover, no quick fix.
- The vendor files' own names (`HighRes`, `Disk` ...) need no such file: their `Also:` goes on their definitions.
- The vendors' Monitor and kernal synonyms (AppleSoft's CQINLN, MPLOT ...; D-Q1) go in the same file.
- **Clash:** Apple's COPY and GARBAG name other definitions than Microsoft's COPY and GARBAG in AppleSoft builds
  (B2-Q8). Recommend that Microsoft's keep `Also:` and Apple's go in prose, as DOS's X8 did for RD1-RD5.

### X6. Whether the vendor-only files convert on the shared modules' schedule

The vendor-only files are `AppleSoft.HighResolution`, `AppleSoft.AppleCommands`, `AppleSoft.PlatformHelpers`,
Commodore's BASIC 4 disk, monitor and record files, BASIC 1's patches, and the string and TI$ files.

- **Recommendation:** convert them in the same effort, each right after the shared modules it calls. Until then
  they reference the converted names by their old ones, which resolve through `Also:` (the method's step 4). They
  depend on the shared modules, not the other way round, so they never block a shared module.
- **Alternative:** convert the shared modules and the vendors' interpreter copies first, and the vendor-only files
  later, as their own items.
- **Related:** BASIC 2's monitor (Kernal2) has the same code under the same names, so it should take part F's names
  when it is converted (F's notes).

### X7. Names that differ between vendors for the same routine

- **Same job, same name:** the vendors' copies of one routine (AppleSoft.Print and Commodore.ChannelPrint, both
  Equates files ...) take one new name, as the settled rule says; part C checked this by script.
- **Old names:** each build's definition carries that build's documents' names, and a shared definition's
  vendor-only names go in the vendor's historical-names file (X5). Examples:
  - FDIVT is FIDVT in ASTIL;
  - COMBYT is COMBYTE in ASTIL;
  - CHZGOT and CHZRTS are CHDGOT and CHDRTS in the HV reconstructions;
  - SQRHLF is SQR05 in CBM4S79.
- **The same old name for different jobs:** names like QSTATV, NTHIS1, TRMNO1 and LINCHK get a name per job (part
  C's table). Each keeps its old name in its own builds, where only one definition has it.
- **Generated names:** names the reconstructions generate from addresses (LCA5A, LE082) are dropped. HV's PATCH1 ...
  PATCH7 and PATCHG ... PATCHI are kept as HV's names.

### X8. The order of the module PRs

- **Recommendation:**
  1. **Prerequisites:** the tool change for `Also:` in macros (D2), plan item B4's rename-proof test helper, and
     symbol lookups by `Also:` in the debug hosts (X9). The first is merged (#132); the other two are in place
     (`tests/Retrocore.Tests/BasicNames.cs`, and `SymbolsWithHistoricalNames` in the hosts).
  2. **The workspace:** both Equates files, the layouts (X3), and the tokens and error codes in both dispatch-tables
     files.
  3. **The math package (part A),** with the vendors' float alias files becoming historical-names entries.
  4. **The shared program and statement modules (B1).**
  5. **The shared expression, variable and string modules (B2).**
  6. **The vendors' interpreter copies (C),** AppleSoft and Commodore together, since their names must agree.
  7. **AppleSoft's own files (E) and Commodore's own files (F),** in parallel.
- **Size:** each step is one or two PRs of a few modules, checked against all eight builds and the overlays (D6).
- **Alternative:** convert by vendor (all of AppleSoft first), using the shared modules' old names on the
  Commodore side meanwhile. This doubles the integration work on the shared modules.

### X9. C# and tests that look up the old names

- `Retrocore.Debug/BasicRom.cs`, `PetDebugTarget.Basic.cs` and `Apple2DebugTarget.cs` look up CURLIN, TXTPTR,
  CHRGET, CHRRTS, ERRTAB, TEMPPT, TEMPST, SUBFLG, OLDTXT, STKEND, NEWSTT, GONE, ERROR, MAIN and others by name.
- About 40 test files read the BASIC builds' symbol tables, mostly by Microsoft's names.
- **Recommendation:** B4's helper resolves either name through `Also:`, and the debug hosts use the same lookup.
  They move to the new names in the PR that renames the definition.
- **Alternative:** keep those names as plain labels. That breaks D4.

### X10. AppleSoft's copies of Apple's Monitor and IIe names

AppleSoft.Equates redefines about 90 names that the converted IIeEquates and MonitorEntries define.

- **Recommendation:** AppleSoft includes `IIeEquates.asm` and `MonitorEntries.asm`. MonitorEntries grows the
  entries AppleSoft calls, including the scoped `LowRes` and `Cassette` ones, and AppleSoft.Equates keeps only
  BASIC's workspace (D-Q1).
- **Clashes this causes:**
  - IIeEquates' `RandomSeed` (RNDL): AppleSoft's RNDX becomes `RandomValue` (settled below);
  - IIeEquates' `SavedOutputY`: AppleSoft's unused KIMY is dropped.
- **Alternatives:**
  - DOS's X7: include IIeEquates only, and define the missing entries with `Inherit:`;
  - keep AppleSoft's own copies under the converted names.

### X11. The floating-point accumulators

- **Recommendation:** keep the field's own short terms, as the hardware's are kept (`Aux`, `Irq`):
  - `Fac`, `FacExponent`, `FacMantissa1` to `FacMantissa4`, `FacSign` and `FacExtension`;
  - `Arg*` likewise, with `ResultSign`;
  - `Float` routines name their operands by these (`AddPacked`, `AddArg`, `LoadFac`; A-Q5).
- **Alternatives:**
  - full words (`FloatAccumulator`, `FloatAccumulatorSign` ...), which are long in arithmetic code;
  - an `UnpackedFloat` struct, with the two registers as locations of it.

### X12. Which Commodore documents to cite for BASIC 1

- **Recommendation:** cite HV1 and HV1R where they give a name (X7), noting their origin in the bibliography.
  Microsoft's name (M6502) is on almost all of the same definitions anyway: of the 869 rows HV1 confirms, all but
  14 are also Microsoft's.
- **Alternative:** cite only Microsoft and the BASIC 2/4 documents, and give HV1's own names in prose.

### X13. Statement names

- **The question:** should a keyword name keep the keyword whole, or split it at its words? The draft is not yet
  consistent:
  - B1 wrote `Statements::Gosub` and `Goto`;
  - E wrote `OnErr`, `HColor`, `XDraw`, `ShLoad`, `HGr2`;
  - F wrote `Dopen`, `Dclose`.
- **Recommendation:** split at the words a reader sees in the keyword: `GoSub`, `GoTo`, `OnErr`, `HColor`,
  `DOpen`, `DClose`. Keep the keyword rather than a description, since the keyword is what a reader searches for
  (DOS's `Commands::PrNumber`).
- **Alternatives:**
  - one capital (`Gosub`, `Dopen`);
  - descriptive names (`Statements::DiskOpen`, `Statements::Continue`).
- Settled as recommended; the table is normalized.

### X14. The PET operating system's names

- **Recommendation:**
  - The kernal's jump-table entries, and the kernal routines BASIC calls, take a `Kernal` prefix at top level:
    `KernalOpen`, `KernalCharacterOut`, `KernalRestoreChannels`. "Kernal" is Commodore's term.
  - The three vectors shared code calls take names both vendors define: `CheckStop` (ISCNTC), `GetCharacter`
    (CZGETL) and `CloseAllFiles` (CQCALL).
- **Alternatives:**
  - a `Kernal` scope;
  - leave the kernal's names for its own conversion, with only `Also:` meanwhile.

### X15. Switches the tests predefine

The tests predefine more build switches than the seven C# does: BUFPAG, BUFLEN, NULCMD, LOCAL_TRMPOS,
VARTXT_IN_LINNUM, INTIDX_USE_FRMNUM, SHORT_FMUL_ZERO, PRECISE_FOUT_LIMIT, INTPRC, ADDPRC, LNGERR, NUMLEV and STKEND
(BasicSharedMemoryManagementTests, PetNativeEquatesTests, Basic1IndependentSwitchTests). The table renames them. An
`.ifndef` default is not reached through `Also:`, so a test that predefines the old name would silently get the
default.

- **Recommendation:** rename them as drafted, and change the tests in the PR that renames each (the tests are the
  SDK's own; B4's helper can map an old switch name to the new one). The roots could assert that no old name is
  predefined, so that a stale predefinition fails loudly.
- **Alternative:** KEEP every switch a test or C# predefines, as the seven are kept.

### X16. How locals of scoped routines are written

The parts wrote a scoped routine's locals two ways: in full (`Float::AlignAndAdd::ArgSmaller`, part A) or without
the scope (`Let::Number`, `CollectGarbage::NextArray`).

- **Recommendation:** write the full path in the table (as code outside the scope reaches it); the table is
  normalized (settled as recommended).
- **Alternative:** the routine's own name only, the scope implied by the routine's row.

## Where the drafts disagreed

Settled in the merge (the table has the settled names):

- K1. The macro NEXT_ENTRIES is `NextEntries`, not `NextStatement`, which is NEWSTT's name (B1, C).
- K2. ISCNTC is `CheckStop` in both vendors (D), not `CheckBreak` (C).
- K3. LASTWR is `InterpreterEnd` in every root (D, F), not `BasicEnd` (E).
- K4. GARBA2 is `Strings::CollectGarbage` in the classic and the linked collector (B2), not top-level
  `CollectGarbage` (F).
- K5. COPYZC is `StoreDescriptor` in the shared and BASIC 4's copies (B2), not `AssignString::StoreDescriptor` (F).
  F's stand-ins for GETSPT and INPCOM's locals take B2's `StoreString::` and `AssignString::`.
- K6. INPSTP is `StopEmptyInput` in BASIC 1's patch and BASIC 4 (C), not `StopOnBlankInput` (F).
- K7. ZERO is `ZeroValue` in FloatConstants and VariableLookup (A), not `ZeroBytes` (B2); AppleSoft's SIMZER is
  `ZeroVariable`.
- K8. NCMPOS is `LAST_COMMA_COLUMN`, following the glossary's `LastCommaColumn` (C), not `LAST_ZONE_COLUMN` (D).
- K9. BUFOFS is the value `INPUT_BUFFER_BASE` in both vendors (C), not the location-cased `InputBufferBase` (D).
- K10. The kernal's ERMSG and CLRCH/CLRCHN are `KernalReportMessage` and `KernalRestoreChannels`, leaving
  BASIC's ERRFIN `ReportMessage` and IODONE `RestoreChannels`.
- K11. BASIC 4's SIGNON is `Basic4SignOnMessage`; FREMES, which BASIC 4 also keeps, is `SignOnMessage`.
- K12. Left as drafted: one old name with two new names where the jobs differ, by build: ARYGET and its family
  (the collector, and BASIC 4's array creation); GETDTL (BASIC 1's editor patch, and a local elsewhere); NTHIS1;
  GETRTS; LINCHK.

### The glossary, corrected

The shared workspace was named first, so that every part used the same names. The parts checked it against the
code; these were wrong and are changed in the table:

- LSTPNT is `ListOffset`: the lister saves its line offset (Y) there; it is not a pointer.
- SUBFLG is `SubscriptMode`: nonzero means subscripts are not allowed.
- DECCNT is `DigitCount`: FIN counts the digits after the point there, FOUT those before it.
- RNDX is `RandomValue`, because of IIeEquates' `RandomSeed`.

Still open (used as glossary names in the table, with scoped aliases proposed in the parts' notes):

- SIZE and OLDOV: the collector's offset and the math package's guard byte, not a jump's operand (D-Q3, A,
  B2).
- GRBTOP and GRBPNT: the collector's best candidate so far (B2).
- COUNT, INTEGR and CURTOL: reused by the PET's AND/OR and by CreateArray (B2).
- LOWTR: `FoundLine` as FindLine's alias (B1).
- AppleSoft's LINWID and NCMWID: unused or misnamed there (D-Q3).

## Corrected after the independent reviews

Two reviews were run on the draft, one checking the inventory and the table against the code (rebuilding all eight
builds), one checking every citation against the documents. Their findings, as corrected:

- R1. Coverage, the counts, every row's builds and about 150 reasons were confirmed. M6502 was removed from nine
  rows where the overlay's label is on Commodore's own code (BASIC 4's array creation, BASIC 1's patches).
- R2. Citations the first checks missed were added: CBM4S79 on 29 rows of identical code or data; K4S79 and HVK4 on
  the kernal routines outside $D000-$DFFF (the first address pass drifted there; the reviewer's byte-exact one is
  used); M6502 where `m6502.asm` defines a name inside an `IFN`/`IFE` bracket (DIRCON, ARGMOH); ASTIL's routine
  articles (FDIVT); the reconstructions' names for the kernal jump table (COPEN ... CCALL, DCAT, SCRATC, READDS),
  and TKSA for SECND; 13 names from AS82's symbol tables, read by hand.
- R3. Names that would shadow a name their own routine uses were changed (`Disk::ReadErrorChannel::SendTalk`, not
  `::Talk`, which calls Talk; `Functions::Peek::ToReturnByte`; the disk parser's `Read*` and the command builder's
  `Put*` locals; `Statements::ShLoad::SetShapeTable`; `CheckStop::ConsumeKey`; `LinkProgram::StoreLink`, beside the
  macro LinkLine; and others).
- R4. Rows where one old name labels different things by build now give a name per build: ANDOP
  (`Operators::And` on the PET, `Operators::Or` in AppleSoft), AppleSoft's LINCHK and TABER (dropped in II+ and IIe,
  where they fall inside instructions), SNERR1 (inside NextStatement in BASIC 1).
- R5. QNUM is `ClassifyCharacter` and CHRRTS `CharacterReaderReturn` (B1-Q3); Commodore's TI$ code calls QNUM and the
  PET debug host looks up CHRRTS.
- R6. AppleSoft's CV keeps the Monitor's definition, CV (the DOS log's X7), rather than D's `CursorLine`.
- R7. The alias files' entries take scoped names (X5), and the shared definitions they target show them in D3.
- R8. Stale names after the merge were fixed (CheckBreak, NextStatement, BasicEnd), as were the facts in this log
  (the $F530 byte count, the `.set` split, PRECEDENCE_UNARY on the PET, K4S79's date, ASRM78's title, the
  reconstructions' differing names).
- R9. Raised by the reviews: X15 (renamed switches tests predefine) and X16 (how locals are written), both since
  settled; and the remaining DROPs that drop a documented name (C-Q8, D-Q3), still open.
- R10. One row per name per file has three exceptions: parameters of the same name in two macros of one file
  (rows 296/315, 1933/1943, 1956/1972).

## Step 4: the conversion

Each step of X8 converts some files and leaves the rest unconverted: those keep using the old names, which resolve
through the converted definitions' `Also:` sections. Every step keeps all eight builds byte-identical.

### W. The workspace (X8 step 2)

Converted, with `; retrocore: style=strict`:

- `AppleSoft.Equates.asm` and `Commodore.Equates.asm`: BASIC's workspace, page zero, the build constants and, on
  the PET, the kernal's jump table (X14's `Kernal` prefix, and the three shared vectors `CheckStop`, `GetCharacter`
  and `CloseAllFiles`).
- `MsBasic.Layouts.asm`, new and shared (X3): `Stack`, `Variable`, `ArrayHeader`, `StringDescriptor` with
  `DESCRIPTOR_SIZE` (STRSIZ), `ForFrame` with `FOR_FRAME_SIZE` (FORSIZ), `GosubFrame`, `OperatorEntry`,
  `ProgramLine` and `FunctionDefinition`. Both vendors' Equates include it; the copies of STRSIZ and FORSIZ in the
  Equates and dispatch tables join it. The FOR frame's stack-relative offsets in `MsBasic.MemoryManagement.asm`
  (FNDFOR) and `MsBasic.Next.asm` (NEXT) are written through it (`Stack + 1 + ForFrame::STEP_SIGN,x`); those two
  files are otherwise unconverted. Their other frame arithmetic stays literal until their own steps: NEXT's
  `adc #$04` and `adc #$06` (or the `inx` runs) to the step and the limit, its `adc #$11` that pops the frame, and
  FOR's `FORSIZ-3`.
- `AppleSoft.DispatchTables.asm` and `Commodore.DispatchTables.asm`: the tokens (`TOKEN_*`), the error offsets
  (`ERROR_*`) and the messages (`ErrorSuffix`, `LineNumberPrefix`, `BreakMessage`, and the PET's `ReadyMessage`),
  X4. The tables themselves (STMDSP, FUNDSP, RESLST, ERRTAB) and the PET's COMMODORE_DISPATCH_TABLES macro keep
  their names for their own step. The Commodore
  macro's body is indented as the strict lint asks of a macro.

Decisions and how the table was applied:

- W1. Every renamed definition's old name is in its `Also:` with the table's keys, the brackets of a key's builds
  dropped (the Equates and dispatch tables are vendor files, so each name already resolves only in its vendor's
  builds). The shared layouts cite Microsoft's source alone, since every build has them. The table's "other names here" go in the same `Also:`, each on one definition: the location where the
  table lists it on a location and its aliases (TEMP3 on `FunctionPointer`, ARRYPT on `DestinationEnd`).
- W2. A row whose documents give no name (its Documents column "none found", or only "spelling only" or "other names
  here") cites its old name as `UNKN`, so the unconverted files' uses of it still resolve. The bibliography has UNKN,
  which ConvertingSources.md describes (#120), and gains ASRM78, as proposed in step 2. This is the owner's open choice
  between UNKN and no `Also:` (the table's introduction); UNKN is the one that keeps the old names working.
- W3. Names two definitions shared in one file are one definition with both old names (INDEX1 and INDEX are
  `Pointer1`). KIMY is dropped into `Dimensioning`'s `Also:`.
- W4. Names left in prose because they would clash with another definition in the same build, or in a build the lineage
  rule reaches: BASIC 4's INCHR (CBM4S79, HV4, HV4R) for `KernalCharacterIn` (BASIC 1's and 2's own INCHR is another
  routine). Microsoft's REDDY and GOTK in AppleSoft (C-Q8), Q (the table counter, which the tables no longer use) and
  AppleSoft's LINWID and NCMWID (D-Q3) are named in prose and not defined; NCMWID's one use is written `FRETOP+1`, the
  same byte.
- W5. The tokens and error offsets the PET's Equates copied for the math package (PLUSTK, MINUTK, ERROV, ERRDV0) are
  defined once, with their tables (X4), so an assembly of the math package with the Equates but without the tables
  must supply them, as the workspace test now does; `TOKEN_PI` stays in the Equates, since the table has no spelling for it.
  The AppleSoft error offsets are computed from their messages (`* - ERRTAB`), as the PET's were, each with an
  `.assert` of its value.
- W6. AppleSoft's copies of the Monitor's, the IIe's and the firmware's names keep their names and definitions in
  AppleSoft.Equates, in their own section, until X10 replaces them (E-8). Their
  trailing comments are moved above them, as the strict lint asks. This covers Microsoft's CQ* synonyms, BUF and OUTCH.
  The table's other names for them join their `Also:` with X10; ASTIL's HBAS, its name for the hi-res byte address,
  went to `HighRes::ByteAddress` (X-4).
- W7. Switches (X15): the seven a test predefines and the Equates define (BUFPAG, BUFLEN, NULCMD, NUMLEV, STKEND,
  LOCAL_TRMPOS, VARTXT_IN_LINNUM) are renamed as drafted everywhere they are used, since an `.ifndef` default is
  not reached through `Also:`, and the tests predefine the new names. Microsoft's five keep `Also:`; the SDK's two
  (LOCAL_TRMPOS, VARTXT_IN_LINNUM) are not historical and get none. Each PET root asserts that none of the seven old
  names is predefined; AppleSoft, which fixes Microsoft's five, rejects those five as values it fixes. The
  switches C# sets keep their names. BASIC 1's root sets three of the five itself
  (INPUT_BUFFER_PAGE, INPUT_BUFFER_LENGTH, NULL_COMMAND), so there the Equates' definitions are skipped; nothing
  uses the old names any more. Since the statement step (S11), BASIC 1's own three carry the same `Also:` as the
  Equates'.
- W8. D-Q3: SIZE is `CollectorOffset`, as recommended (the string collector's offset; the recommendation's scoped
  alias waits for the collector's step); LSTPNT is `ListOffset` and DECCNT `DigitCount`, as the table has them.
  OLDOV keeps the table's `FunctionJumpHigh`: the recommended `ArgExtension` rests on D-Q3's reading that FADD keeps
  the smaller operand's extension there, but it keeps the unshifted operand's (FAC's, or zero), with the shifted
  one's in FacExtension, and EXP keeps a rounding byte there; neither is the argument's. A new question for the
  owner: a name for the byte's floating-point uses (`UnshiftedExtension`, or scoped aliases in FADD and EXP when
  the math package converts). The table's rows are updated to match.
- W9. C# lookups (X9): the debug hosts keep Microsoft's names, which reach the native builds through `Also:` and
  are the MACRO-10 builds' own names, so one lookup serves both sources. The tests likewise look the old names up
  through `BasicNames`; they move when the MACRO-10 comparisons no longer need them.
- W10. Prose writes in backticks the words that are also documented labels: BASIC's keywords (`FOR`, `DATA`), whose
  handlers have those names, and words of the messages (`ZERO`, `ERROR`, `BREAK`), so the lint does not ask for a
  link to an unrelated routine.

Checked: the full suite, the rename gate, the lint tests, and `BasicWorkspaceConversionTests`, which compares every
old name in the converted files with the MACRO-10 overlay's value in each build, checks that a vendor's old names
resolve only in its builds, and that every citation's key is in the bibliography. The debugger's contract checking
ran clean over a program using FOR, NEXT, GOSUB, DEF FN, arrays and strings on PET BASIC 2, PET BASIC 4 and the
enhanced IIe's AppleSoft, built from these sources.

### M. The math package (X8 step 3)

Converted, with `; retrocore: style=strict`:

- The thirteen shared modules of part A: `MsBasic.AdditionCore`, `ArithmeticCore`, `MovementCore`, `ConversionCore`,
  `DecimalInputCore`, `OutputCore`, `FloatConstants`, `Logarithm`, `TranscendentalCore`, `RandomCore`,
  `IntegerConversion`, `Relational` and `SimpleFunctions`. Each routine is a `.proc` in `Float` or `Functions`
  (A-Q2, A-Q3), or top level where the table puts it (A-Q9), its locals and the labels other routines enter written
  by their full paths (X16, A-Q4).
- AppleSoft's six compositions (`MsBasic.FloatingPoint`, `FloatArithmetic`, `FloatMovement`, `FloatConversion`,
  `FloatOutput`, `Transcendental`) and `Commodore.FloatingPoint.asm`: their headers, and Commodore's own routine.
- `MsBasic.Families.asm`, new and shared: it declares `Float` and `Functions`, empty, so each macro can add its piece
  with `.scope Name continued` (B1-Q9). Each module that adds to them includes it, and a guard
  (`FAMILIES_DECLARED`) makes only the first inclusion declare them, so a build or a test can include the modules
  alone and in any order.
- `AppleSoft.HistoricalNames.asm` and `Commodore.HistoricalNames.asm`, new, replace the two float alias files (X5).

Decisions and how the table was applied:

- M1. The old names are in `Also:` as in W1, each definition expanded once per build (D2). A name the table gives
  only for one vendor's builds (Microsoft's MULLN2 and GFDIV, which M6502 has for the PET only; Apple's PRNTFAC,
  OVERFLOW, FIDVT, INSRTDIG, LOGSER, BILLION and MISMTCH; Commodore's SQR05, SQR20, TENC, N0999, N9999, NMIL, RMULC
  and RADDC) is an entry of its vendor's historical-names file instead: a scoped alias (`Commodore::SquareRootOfHalf
  = Float::SquareRootOfHalf`) that inherits its target's documentation and gives the name in its `Also:`. Since the
  assembler takes no qualified definition, each file opens its vendor's scope. MISMTCH's target is CHKERR in the
  unconverted `MsBasic.Next.asm`, which gains a summary so the alias has documentation to inherit.
- M2. FOUT13, which only the SDK's AppleSoft overlay gives (the table: no document), is AppleSoft's alias
  `AppleSoft::SignDone` with `Also: FOUT13 (UNKN)`, since the label is in AppleSoft's build only and the overlay's
  callers keep it. LINPRT_FOUT, the SDK's own name, which nothing uses, gets no `Also:`, as the table says.
- M3. OLDOV (W8): the byte keeps `FunctionJumpHigh` with its `Also:`; its floating-point uses read it through scoped
  aliases, `Float::UnshiftedExtension` (AddArg and AlignAndAdd set it; AddMantissas and AlignAndAdd's Subtract read
  it) and `Functions::Exp::RoundingByte`,
  each saying in prose that Microsoft names it OLDOV there too.
- M4. ZERO (A-Q7): `ZeroValue` is top level. `OutputTables` closes `Float` around it, and the three bytes are
  emitted outside the scope in every build, labeled only where `defineZero` is 1. BASIC 1's ZERO in
  `MsBasic.VariableLookup` keeps its name until that module's step. A-Q7's note of a bug in LDZR's comment was
  mistaken: AppleSoft passes `inlineZero = 1` and `useSimzer = 1`, so it has its own zero bytes there (SIMZER),
  besides those in `Float::Half`, and the comment stands.
- M5. A-Q6: AppleSoft's `ZSTORD = STORDO` is dropped and its WAIT passes `STORDO`; ZSTORDO is named in prose.
  BASIC 2's hidden-message routine, in Commodore.FloatingPoint and selected by `WAIT_EASTER_EGG`, is
  `WaitHiddenMessage` (Also: ZSTORD (M6502), STORD1 (HV2)), with its locals, `HiddenMessageText`
  and two constants for its length and screen-code mask. BASIC 4's checksum byte is `RomChecksumAdjustment` (Also:
  CHSUMC (HV4, HV4R)).
- M6. A-Q10: the macros take PascalCase names with full words (`AddEntries`, `LogarithmRoutine`,
  `ExponentialConstants`, `TrigonometricRoutines`, `SignAndIntegerRoutines` ...), and every invocation, root and test
  follows; DecimalInput's `limitAt120` is `earlyExponentLimit`. Macros take no `Also:`, so nothing keeps the old
  macro names.
- M7. Switches (X15, W7): Microsoft's INTPRC, ADDPRC and LNGERR are `INTEGER_VARIABLES`, `ADDITIONAL_PRECISION` and
  `LONG_ERRORS` with `Also:`, and the PET's SHORT_FMUL_ZERO, EARLY_FIN_LIMIT, PRECISE_FOUT_LIMIT and ZERO_AT_FHALF
  are `SHORT_MULTIPLY_ZERO`, `EARLY_INPUT_EXPONENT_LIMIT`, `PRECISE_OUTPUT_LIMIT` and `ZERO_IN_HALF_CONSTANT`
  (SDK names, no `Also:`). Their uses (FOR's `8+ADDITIONAL_PRECISION`, the collector's, BASIC 1's stack reserve)
  take the new names. The PET roots reject the seven old names predefined, and AppleSoft the three it fixes.
- M8. A-Q8: the line-number printers stay in `Float`.
- M9. Links elsewhere: the unconverted modules' documentation links to the math labels by their new names (a link
  does not resolve through `Also:`), so a renamed label does not leave a broken link.
- M10. The interpreter alias files (`AppleSoft.InterpreterAliases`, `Commodore.InterpreterAliases`) wait for the
  steps of the code they alias, and join the historical-names files then.
- M11. Tests: a module built alone gets the names its dependencies now have from `BasicNames.WithCurrentNames`, but
  a scoped name (`Float::LoadArg`) cannot be predefined, so `BasicNames.ScopedNames` writes those as constants in
  pieces of their scopes in the test's source. The PET float alias test predefines only the current names its
  model's build has: BASIC 1 keeps ZERO, so another build's ZeroValue would be a second definition.

Checked: the full suite, the rename gate, the lint tests, and `BasicMathConversionTests`, which compares every old name
in the math files with the MACRO-10 overlay's value in each of the eight builds, checks that each definition reaches the
overlay by its name or an old name, that a vendor's names resolve only in its builds and through its aliases, and that
every citation's key is in the bibliography. `BasicMathRoutineTests` runs AddPacked, SubtractFromPacked, MultiplyPacked,
DividePacked, Compare, GetSign, LoadFac, StoreFac, ToLongInteger, ShiftRight and FormatFac in the enhanced IIe's
AppleSoft and PET BASIC 4 and checks their results and `Out:` values; the math modules claim no `Keeps:`. It also pins a
quirk the review found in Microsoft's multiplication, now documented on `Float::ShiftProductByte`: a zero multiplier
byte after another zero byte shifts the partial product nine bits, halving it, so 1 + 2^-31 times 1 leaves its low bit
at half weight in FacExtension, and only rounding restores it. The debugger's contract checking ran clean over the W
program, which uses FOR with STEP, DEF FN, VAL, INT, SQR and SIN, on PET BASIC 2, PET BASIC 4 and the enhanced IIe's
AppleSoft, and reported a false `Keeps: Y` added to `Float::LoadFac` as a control.

### S. The program and statement modules (X8 step 4)

Converted, with `; retrocore: style=strict`, part B1's fifteen shared modules: `MsBasic.CharacterReader`,
`CommandCore`, `For`, `LineNumber`, `LineSearch`, `Lister`, `MemoryAccess`, `MemoryManagement`, `Next`,
`OperatorTable`, `Print`, `ProgramReset`, `ProgramTransfers`, `StatementFlow` and `UserFunctions`. Each statement
handler is a `.proc` in `Statements`, which `MsBasic.Families.asm` now declares after `Float` and `Functions`; each
macro opens and closes the scope around the handlers it emits (B1-Q9), except that the lister's `ListRange` opens
the scope and `.proc List` in it, and `ListTokens` closes both (S2). The other routines are top level, as the table
puts them. The bytes are unchanged in all eight builds.

Decisions and how the table was applied:

- S1. Entries inside a routine (B1-Q1) are its labels, listed in its `Entry:` section and documented where they are,
  each with its old name in `Also:`. A label that only some builds define (FN's UndefinedFunction) is named in the
  routine's prose instead, since an `Entry:` item must exist in every build.
- S2. The character reader's template is `.proc CharacterReaderTemplate` with `GetCurrent` (CHZGOT) and `Done`
  (CHZRTS) (B1-Q3). The lister is one `.proc List` in `Statements`, opened in `ListRange` and closed in `ListTokens`
  (B1-Q4). BLTU is `MoveRangeUp`, with `MoveRangeUp::Unchecked` (B1-Q5).
- S3. B1-Q6's quirk is documented on `ReadLineNumber` and `Statements::On::RequireGoto`, and
  `ReadLineNumberSendsAGotoTokenHighByteIntoOn` pins it: in AppleSoft 437760 and 440319 reach ON's loop, 440320 is a
  syntax error; on the PET, 350720 reaches it.
- S4. B1-Q7: `ProgramReset` loses `newAlias` and `RunStatement` loses `runLabel` (and RUN1); NEW is AppleSoft's alias
  of `Statements::New`. The vendors' invocations follow; the bytes do not change.
- S5. The macros take the names in B1-Q10 and the table (`LetterTest`, `CharacterReader`, `ErrorFinish`, `ListRange`,
  `ListLines`, `ListNextTableByte`, `ListTokens`, `DeleteOldLine`, `LinkLine`, `TokenStore`, `AddressConversion`,
  `PeekFunction`, `PokeStatement`, `WaitStatement`, `MemoryManagement`, `NextEntries`, `OperatorEntries`, `PrintItems`,
  `ProgramReset`, `ClearStatement`, `NullStatement`, `ClearStorage`, `ExecutionReset`, `RestoreStatement`,
  `StopAndContinue`, `RunStatement`, `GosubAndGoto`, `ReturnStatement`, `StatementScan`, `ConditionalStatements`,
  `OnStatement`, `UserFunctions`), and every invocation, root and test follows.
- S6. Names only a vendor's documents give are entries of its historical-names file, as M1 has them, since a shared
  definition cites only Microsoft's names (`AssertSharedNamesAreMicrosofts`):
  - AppleSoft: NEW (ASTIL, AS82), which `ProgramReset`'s dropped `newAlias` defined (S4), and COMBYTE (ASTIL, AS82),
    which leaves `AppleSoft.InterpreterAliases.asm` (deleted, M10), and the overlay's own labels GOLST1, GRODY1,
    GRODY2, PRIT31, PRIT32 and REMER1, cited UNKN as FOUT13 is (M2). The table says "no Also" for these, but
    `applesoft.mac` defines them, and its callers and the label comparisons keep them. COMBYTE's alias targets
    `::ReadCommaAndByte`, since its own name would hide the top-level routine.
  - Commodore: CHDGOT and CHDRTS (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), Commodore's spellings of CHZGOT and CHZRTS,
    in every PET build. The rename table leaves CBM4S79 out; its `code26` names both labels, as the HV
    reconstructions do (checked in mist64/cbmsrc at the bibliography's commit). BASIC 4's lister labels RESCR2 and
    PRIT3B (CBM4S79, HV4, HV4R) are each under `.ifdef` its target.
  - The SDK's own names that no overlay or document gives get no `Also:`, as the table says: CONT1, and
    LIST_QUOTE_CHECK, which no build assembles.
- S7. BSTOP, the name Commodore's BASIC 4 kernal listing (K4S79) and Hoffmann-Vetter's reconstruction of it (HVK4)
  give `Statements::Stop` as an equate of the kernal's, is in prose: a Commodore alias must cite one of its build's
  BASIC documents (`BasicAttribution.PetKeys`), and neither kernal listing is one, so it cannot be an alias's
  citation. Whether the kernal's documents should count for that rule is a question for the owner.
- S8. CommandCore's labels that are locals of part C's routines (TYPERR, MAIN1, QDECT1, MLOOP, CZLOOP, GETBPT,
  STUFFH, COLIS, NODATT, STR1 and STRNG) keep their names until part C converts those routines.
- S9. Contracts from the code: `IsLetter` keeps A, X and Y (its two subtractions take $100 in all); the character
  reader's copy keeps X and Y. STOP, END and StopOrEnd are described from the code. `EraseProgram` adds the incoming
  carry where `clearCarry` is 0, so AppleSoft's and, by default, BASIC 1's `NEW`, which arrives with carry set, puts
  VariablesStart three bytes past ProgramStart; `EraseProgramAddsTheCarryOnlyWhereTheBuildDoesNotClearIt` pins
  AppleSoft's and PET BASIC 4's. The flags routines depend on are stated: ReadLineNumber's zero (so `LIST 10-X` lists to
  the end), FindForFrame's carry and A, the zero New, Clear and Return take, Return's Y (POP), and that
  ResetProgramState clears by falling into the next entry.
- S10. Tests and their helpers:
  - The rename gate renames STROUT and PTRGET (top level, and in a macro's body), since FNDLIN and BLTU are
    converted. It found that `MathUsesNativeWorkspaceAndMatchesTheLegacyBytes` declared its external labels by
    their old names only; they now go through `BasicNames.Label` and `ScopedNames`.
  - `BasicNames.CurrentNames` follows a vendor's alias to its target, so a standalone build predefines the name the
    modules use (`Statements::PopFinish`, not `AppleSoft::PopFinish`). `BasicNames.IsVendorName` lets a standalone
    region's label comparison skip the vendor's names, which the whole builds' tests compare.
  - `BasicSharedAliasConsistencyTests` reads the `.ifdef Target` guards in a historical-names file and expects a
    guarded alias exactly where its build defines the target, and there checks its citations against the build's
    documents; RESCR2 and PRIT3B are checked so only in the BASIC 4 builds. `BasicSharedFloatAliasesTests`, whose PET
    regions hold no lister, leaves them out.
  - The editor probe in `LanguageAnalysisTests.Macros` gives COMBYTE as a user file's own old name. Once the SDK gave
    the same name, the editor's merge of the file's and the SDK modules' `Also:` names cancelled it, and the file lost
    its hint and quick fix. When the file assembles, its own name now takes precedence where the assembler's own table
    of historical names gives it to the definition the hint would name (`LanguageWorkspace.HistoricalNames`); anywhere
    else, and whenever the file has errors, the merge behaves as before. The text alone cannot say what the assembler
    would make of conditions, repeats, macros and scoped includes, and every rule the reviews tried for files with
    errors gave some case a hint naming the wrong definition, so while a file has errors its own name that an SDK module
    also gives loses its hint until the errors are fixed. The unchanged COMBYTE probe fails without the change; the
    others guard against the wrong hints earlier versions of it gave: `OldNamesInAnOmittedBranchDoNotHint` (with and
    without an error), `OldNamesOfTheOtherBranchDoNotHint` (a label documented in both branches),
    `OldNamesUnderConditionsTheEditorCannotReadDoNotHint` (an `.ifdef` of a later symbol, a computed condition),
    `OldNamesHintOnlyTheDefinitionTheAssemblerGivesThemTo` (a root routine sharing its name with a macro's expansion, a
    macro expanded twice) and `OldNamesOfAMacroDoNotHintWhileTheFileHasAnError`. The doc set's `FindAlso` returns a
    single topic without its per-build filter, so a file whose other branch gives a name no SDK module gives still gets
    a hint naming the label; that predates this step and is left for a change of its own. A macro-body name whose label
    shares a root routine's name, in a macro expanded once, hints the expansion (`Basic::Reader`), the definition the
    assembler gives it to, through the doc set's name-aware lookup (#132).
- S11. Two rules the owner settled on the Monitor's PR, which apply here from this step on:
  - D5, narrowed: a mid-routine `.if` shows how builds differ, better than whole per-build routines; a routine's
    contract holds in every build, or says which build differs. The statement modules already show their builds'
    differences this way, inside the shared macros.
  - Lineage citations: a definition that descends through a vendor's builds cites every document of that line whose
    listing names it, not only its own build's. Within the PET line, checked against mist64/cbmsrc, that adds CBM4S79 to
    the kernal vectors, to the three disk vectors the BASIC 4 documents name apart from BASIC's own routines, and to the
    RND timer in `Commodore.Equates.asm` (from the workspace step); K4S79 to TIL; every PET document and M6502 to
    BUFLEN, in both BASIC 1's `Basic1.asm` and the other builds' `Commodore.Equates.asm`, and to the shared FORSIZ and
    STRSIZ in `MsBasic.Layouts.asm`; and the BASIC documents' CTIMR and CSTAT to the jiffy clock and I/O status. The
    kernal's TIME and SATUS are in prose, since the builds define both names themselves. NUMLEV cites the whole line on
    BASIC 1's 19 levels too, with prose saying the documents give it as 23: HV1 and HV1R write the build's 54-byte stack
    reserve as 23 levels plus eight bytes. BASIC 4's INCHR (CBM4S79, HV4, HV4R) is in prose on the kernal's character
    input, since BASIC 1 and 2 give the name to another routine and the lineage rule would cite it in their builds too.
    The workspace step's `VendorOldNamesResolveOnlyInTheirVendorsBuilds` required the shared layouts to cite M6502
    alone, which forbade the lineage; it now requires exactly M6502 and the PET line's documents there. The
    bibliography's method states the rule too. BASIC 1's own BUFPAG and NULCMD switches, like its BUFLEN, now cite what
    the Equates' do. A shared module's comment that names a build describes it with its root's default switches, as the
    shared folder's README now says; some say "by default" where the reviews asked. The statement modules' and the
    historical names' citations already followed the rule. BASIC 1's ZERO is a definition of its own in
    `MsBasic.VariableLookup.asm` (M4), whose step will cite the line on it. The AppleSoft documents (ASTIL, AS82) are
    not available here to check. One test rule would forbid a lineage-only alias: a Commodore alias without M6502 must
    cite one of its own build's documents (`BasicAttribution.PetKeys`). No alias needs that yet; changing the rule is a
    question for the owner.

Checked: the full suite, the rename gate, the lint tests, and `BasicStatementsConversionTests`, which compares every old
name in the fifteen files and the vendors' historical names with the MACRO-10 overlay's value in each of the eight
builds (about 150 per build), checks that each definition reaches the overlay by its name or an old name, that a
vendor's names resolve only in its builds and through its aliases, and that every citation's key is in the bibliography.
`BasicStatementRoutineTests` runs IsLetter, the character reader's copy, ReadLineNumber, FindLine, FindStatementEnd,
FindLineEnd, EraseProgram and GOTO's search start in the enhanced IIe's AppleSoft and PET BASIC 4 and checks their
`Out:` values and, for IsLetter and the character reader, their `Keeps:` claims; the existing BasicShared*Tests run the
rest (FindForFrame, MoveRangeUp, CheckStack, CheckFreeMemory, the statements). The debugger's contract checking ran
clean on PET BASIC 2, PET BASIC 4 and the enhanced IIe's AppleSoft over a program that adds IF, POKE and PEEK, ON GOSUB
and ON GOTO, RETURN from inside FOR, RESTORE, READ and DATA, REM, CLEAR (CLR) and LIST with a range to the math step's,
and reported a false `Keeps: X` added to `FindLine` as a control (a first control, `Keeps: A` on IsLetter, was not
reported because the claim is true).

### E. The expression, variable and string modules (X8 step 5)

Converted, with `; retrocore: style=strict`, part B2's sixteen shared modules: `MsBasic.ArrayMultiplication`, `Arrays`,
`Assignment`, `Dim`, `ExpressionCore`, `OperandEvaluation`, `VariableInput`, `VariableLookup`, `StringStorage`,
`StringStorage.Classic`, `StringStorage.Linked`, `StringConcatenation`, `StringConversion`, `StringFunctions`,
`StringGarbageCollection` and `StringOutput`. The string package is the scope `Strings` (B2-Q1), the variable and
array internals `Variables` (B2-Q2) and the logical operators `Operators` (B2-Q4). `MsBasic.Families.asm` now
declares all three. `OperatorTable` is now a `.proc`, so B1's operator entries are its labels rather than top level.
The bytes are unchanged in all eight builds.

Decisions and how the table was applied:

- E1. The macros take the table's names (`ArrayLookup`, `AssignmentStart`, `StringAssignment`, `ExpressionCore`,
  `OperandEvaluation`, `IntegerVariableValue`, `FunctionDispatch`, `LogicalOperators`, `VariableInput`,
  `VariableInputMessages`, `VariableSearch`, `SimpleVariableLookup`, `ExistingArrayEntry`, `StringStorage`,
  `StringAllocation`, `UnlinkedStringAllocation`, `LinkedStringAllocation`, `StringConcatenation`,
  `StringFromNumber`, `StringFunctions`, `StringGarbageCollection`). Every invocation, root and test follows. In the
  vendors' files, as X6 has it, the code keeps its old names until part C and only the `<link>`s change, except:
  - each vendor's `OperatorEntries` table names AND's handler `Operators::And`, where AppleSoft's had `OROP1` and
    Commodore's `ANDOP`;
  - two of part C's labels become the shared names (E6).
- E2. D5, narrowed (S11): the builds' differences stay mid-routine `.if`s, and each contract holds in every build or
  names the build that differs. `LogicalOperators` gives AppleSoft's Boolean OR, which falls into AND, under `.else`,
  and the PET's bitwise Or and And under `.if bitwise`. The exception is `Strings::ReserveSpace` (GETSPA). Its two
  allocators share only their first instruction, so each is a whole `.proc` in its own file, with its own
  contract. Each allocator macro opens `Strings` and the routine itself, and the documentation then names its
  labels in the routine. Before this, the routine was opened in `StringAllocation` and its labels were in a nested
  macro, where the documentation named them without a scope; a vendor's alias of one could not inherit. A test that
  pinned GETSPA's topic and source chain to `MsBasic.StringStorage.asm` now expects
  `MsBasic.StringStorage.Classic.asm` ahead of it.
- E3. Names that only one vendor's documents give leave the shared modules for that vendor's historical-names file, as
  S6 has it (`AssertSharedNamesAreMicrosofts`):
  - Commodore:
    - STRD, CHRD, LEFTD, RIGHTD and MIDD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R), and COPYC (E6). These were in
      `Commodore.InterpreterAliases.asm`, which is now deleted, as AppleSoft's was in M10.
    - BASIC 4's NXTPTR, QDSVAR, ARYVA2, ARYVA3, ARYVGO, ARYGET, GOGO, GOGO1, DVARTS, ARYDON, RES00, FRE01, FRE02 and
      TRYAG4 (CBM4S79, HV4, HV4R).
    - GETRTS (CBM4S79, HV4, HV4R) on BASIC 4's allocator's return. The table cites M6502 for it too, but Microsoft's
      GETRTS is the output routine's return (PrintCharacter::Return, rows 1441 and 1969).

    Each is under `.ifdef` its target (COPYC as E6 says), so a build of part of the modules leaves it out.
  - AppleSoft: the overlay's own labels INDLO1, GOTAR1, GOTAR2, NOTOP1, ANDOP, OROP1, OROP11, OROP12, NOWGE2,
    NOWGE3, TRMOK1, PTRGT4, STRNA1, STRNA2, STRNA3, SIMZER, FMAPT1 and QINTG1, cited UNKN as S6's are, since
    `applesoft.mac` defines them. SIMZER's alias targets `::ZeroVariable`. The table's merge of STRNA3 into
    `FindVariable::SearchScalars` stands.
- E4. One old name with a different definition in each vendor (K12, R4). ANDOP is AppleSoft's `Operators::Or` and the
  PET's `Operators::And`. ARYVA2, ARYVA3, ARYVGO, ARYGET, GOGO and DVARTS are the classic collector's steps in
  AppleSoft and BASIC 1 and 2, but `Variables::Create`'s array back-link steps in BASIC 4. TRYAG3 is the unlinked
  allocator's room check (Microsoft's) there, but BASIC 4's step before its own room check
  (`Strings::ReserveSpace::BelowLink`); the table's row 706 gives that one M6502 too, which m6502.asm does not bear
  out. Each name is an alias in
  both vendors' files; Commodore's are guarded by their targets, since each PET build defines only one of them.
  The classic collector's aliases are `Collector<Step>`:
  AppleSoft cites M6502, and Commodore cites M6502, HV1, HV1R and HV2. The lineage rule is not extended across the
  two collectors, which are different code under the same names. The vendor-leak checks of the workspace, math and
  statement steps now allow the names both vendors give (`Except`).
- E5. Three overlay labels get no `Also:`. They are LENFLT (`Functions::Len::ToFloat`) and BASIC 4's NOTDS and NOTDS1
  (`StoreString`'s disk-status check, part C's names until then). No document gives them. HV4 and HV4R call NOTDS's
  and NOTDS1's addresses DSKX2 and DSKX1. Those names wait for part C, which converts the labels and can give them
  (rows 2349 and 2350). A Commodore alias must
  cite one of its build's documents (`BasicAttribution.PetKeys`, S7), so UNKN cannot be a Commodore alias's
  citation. Asking for an exemption to that rule would weaken a check, so I did not. Instead, `BasicNames.OverlayOnlyLabels`
  lists them, and the overlay comparisons (`NativeBasicMatchesTheOverlay`, the assignment, string-function and
  native-equates tests) check that each current name has the overlay's address. Whether such names should be
  aliases cited UNKN is a question for the owner.
- E6. The descriptor copy (COPYZC, COPYC). The shared `StoreDescriptor` (COPYZC, M6502) is assembled where the
  collector is classic, and Commodore's alias gives it COPYC there. It is guarded by
  `Strings::CollectGarbage::NextPass`, the classic collector's label, since BASIC 4's builds also define
  `StoreDescriptor`. BASIC 4's own copy is part C's file, `Commodore.StringAssignment.asm`. Its label is now
  `StoreLinkedDescriptor` (Also: COPYZC (M6502)), and `StoreDescriptor` is an equate of it, by which the shared
  modules reach it. Commodore's alias `LinkedDescriptor` gives it COPYC, under `.ifdef` its target. Naming the label
  `StoreDescriptor` would have merged its topic with the shared one, which may cite Microsoft's names only. Likewise,
  BASIC 4's GARBA2 in `Commodore.StringGarbageCollection.asm` is `Strings::CollectGarbage`, opened as
  `.scope Strings continued` there (Also: GARBA2 (M6502, CBM4S79, HV4, HV4R)). Both are bridges until part C
  converts those files.
- E7. TRYAG4's target is `Strings::ReserveSpace::CheckLinkedRoom`, not the table's `CheckRoom`. The documentation
  merges a qualified name's topics across builds, so under the table's name the classic allocator's `CheckRoom`
  would also have taken BASIC 4's TRYAG4 (`PetOldNamesMatchTheOverlay` and the citation checks fail that way).
- E8. M4's deferral: BASIC 1's own zero bytes, `ZeroValue` in `MsBasic.VariableLookup.asm`, cite ZERO along the PET
  line (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R), under S11's lineage rule; the table's row 860 gives M6502, HV1
  and HV1R. AppleSoft's and BASIC 2's and 4's `ZeroValue` is the math step's, inside `Float::Half`. AppleSoft's own
  bytes here are `ZeroVariable` (SIMZER), which has no `Also:` in the modules; AppleSoft's alias gives SIMZER (E3).
  The math step's `ZeroValue`, inside `Float::Half`, now cites the whole line too (M6502, CBM4S79, HV1, HV1R, HV2,
  HV4, HV4R), adding HV1 and HV1R, which give the name to BASIC 1's own zero, as the lineage rule asks.
- E8a. Citations on a definition that only one vendor's builds assemble: the lineage rule stays within the vendor's
  line. BASIC 4's allocator does not cite ASTIL for GETSPA. AppleSoft's Boolean OR cites OROP by M6502 only, since
  the PET's documents describe its bitwise OR. Within the PET line, a routine that every build has, though in two
  versions, cites the whole line, as S11 has it: both allocators' GETSPA, and both COPYC aliases. The labels inside
  the two allocators and the two collectors, which are different code under the same names (E4), cite only the
  documents of the builds that have them.
- E9. Constants and layouts:
  - `INPUT_MODE_INPUT`, `INPUT_MODE_GET` and `INPUT_MODE_READ` (asserted where READ's mode is the operand of a
    skipped `lda #`).
  - `FLOAT_SIZE` and `DEFAULT_BOUND` in `MsBasic.Layouts.asm`.
  - The operator table's precedences, `PRECEDENCE_ADD` to `PRECEDENCE_RELATION`.
  - `.sizeof(Variable)`, `.sizeof(ArrayHeader)`, `ArrayHeader::DIMENSIONS` and `LENGTH`, `OperatorEntry`'s fields
    and `StringDescriptor`'s fields in many of the places the code had numbers, and `RELATION_TOKENS` for the count
    of relational tokens. Some offsets, counts and flag values are still numbers, among them the collector's
    descriptor-offset arithmetic, the multiplication's 16 bits, the link's two bytes, a few descriptor and variable
    offsets, the type flags ($FF, $80, $7F) and the carriage return; naming them is left for a later pass.
  - `*+n` branches are labels (`Arithmetic`, `NotFn`, `NotEmpty`).
- E10. Three of `SimpleVariableLookup`'s parameters are renamed so its line fits in 120 columns: `checkCallerHigh` is
  `callerHigh`, `useSimzer` is `ownZero` and `arrayEntryAlias` is `countEntry`. The table keeps the SDK's own
  names (KEEP). Whether to wrap the line instead is a question for the owner.
- E11. Tests and their helpers:
  - `BasicNames` declares the three new scopes. An old name that names different definitions in different builds (ANDOP,
    COPYZC, the room check and the classic collector's steps) is predefined per build: the operator-table,
    interpreter-alias and decimal-input tests pass `BasicNames.Build(...)` to `WithCurrentNames` and `ScopedNames`, and
    without a build both reject such a name. Its `DefiningSymbol` follows an alias to its target. `BothVendorsNames`
    pins the names both vendors' files give, and `VendorLabelNames` the one (GETRTS) that other builds still give to a
    label of their own unconverted code; the vendor-leak checks exempt exactly those.
  - The standalone sources predefine `BasicNames.ScopedNames` and include `MsBasic.Layouts.asm`.
  - The region comparisons skip the vendors' names, as S10's do.
  - The rename gate now renames CRDO and NEWSTT, in the vendor files that use them (a `Files` list), since their
    callers are converted.
  - `BasicSharedFloatAliasesTests.CheckAliases` reads only the guarded aliases a build defines. The math tests
    predefine none of the targets this step's aliases guard on (`CommodoreTargetOldNames`).
  - `BasicSharedAliasConsistencyTests` reads a guard on `::Name` as the top-level `Name`.
  - `BasicExpressionsConversionTests` is new: the overlay comparisons for the sixteen files and both vendors'
    names, the vendor-leak and alias checks, and the citations of Commodore's aliases.
  - `BasicSharedInterpreterAliasesTests` checks COPYC, STRD and the rest in the whole builds, now that they are in
    Commodore's historical names.

Checked: the full suite, the rename gate, the lint tests and `BasicExpressionsConversionTests`.
`BasicExpressionsConversionTests` compares every old name in the sixteen files and the vendors' historical names with
the MACRO-10 overlay's value in each of the eight builds. It checks that each definition reaches the overlay by its name
or an old name, that a vendor's names resolve only in its builds and through its aliases, and that every citation's key
is in the bibliography.

`BasicExpressionRoutineTests` runs these routines in the enhanced IIe's AppleSoft and PET BASIC 4 and checks
their `Out:` values and `Keeps:` claims:

- `Strings::CopyBytes` and `CopyFrom`: into a destination that crosses a page boundary, and for `CopyBytes` at
  lengths 0 (both builds) and 1 (AppleSoft) too; both keep X.
- `Strings::ReleaseTemporary`: the latest temporary and others; keeps X.
- `Variables::MultiplyUnsigned`: products and the OUT OF MEMORY jump.
- Both builds' `Strings::ReserveSpace`: room to spare, exact room, one byte short (up to the call of the collector),
  AppleSoft's collection for a zero length, and BASIC 4's return for a zero length and its link for a nonempty string.
- `EvaluateByte`: the value, the next character, and ILLEGAL QUANTITY past 255.

The existing BasicShared*Tests run the rest. The debugger's contract checking ran clean on PET BASIC 2, PET BASIC 4
and the enhanced IIe's AppleSoft. Their program adds the following to the statement step's:

- integer variables;
- NOT, AND and OR;
- string comparison and concatenation;
- 40 rounds of RIGHT$, MID$ and STR$ with FRE(0), which collects garbage;
- INPUT of a string and a number;
- CHR$, ASC and VAL of a concatenation;
- variables that were never assigned.

As a control, a false `Keeps: Y` added to `Strings::CopyBytes` was reported on PET BASIC 4.

CI's later steps, run as CI runs them with an empty `RETROCORE_CACHE`, pass: the IIe sample assembles, every
`tools/Test-*.mjs` script passes, and in `extension/` `check:grammar`, `compile` and `test:grammar` pass.

### I. The vendors' interpreter files (X8 step 6)

Converted, with `; retrocore: style=strict`, part C's twelve vendor files and both dispatch tables: AppleSoft's
`ErrorAndInput`, `ControlFlow`, `Print`, `InputOutput`, `Expressions`, `Initialization` and `DispatchTables`, and
Commodore's `CommandInput`, `StatementDispatch`, `ChannelPrint`, `ChannelInput`, `VariableEvaluation`,
`Initialization` and `DispatchTables`. AppleSoft's and Commodore's names agree where the code does the same job
(the table's "same job, one name" list). The shared modules' references to part C's names (ReportError,
PrintNewline, PrintCharacter, ReservedWords, FunctionTable and the rest) follow. The bytes are unchanged in all
eight builds.

Decisions and how the table was applied:

- I1. Commodore's macros take CamelCase names (`CommodoreErrorReady`, `CommodoreCommandLoop`,
  `CommodoreTerminalInput`, `CommodoreTokenize`, `CommodoreStatementFetch`, `CommodoreStatementDispatch`,
  `CommodorePrintChannels`, `CommodoreCharacterOutput`, `CommodoreLineEnd`, `CommodorePrintSpacing`,
  `CommodoreChannelInput`, `CommodoreInputStatement`, `CommodoreInputError`, `CommodoreVariableValue`,
  `CommodoreInitialize`, `CommodoreMemoryProbe`, `CommodoreStartProgram`, `CommodoreStartMessages`,
  `CommodoreDispatchTables`). Every invocation, root and test follows. Their parameters follow C-Q10
  (`clearSuppression`, `honorSuppression`, `setLineWidth`), and BASIC 1's `earlyBufferSetup` is `earlyBuffer` so
  the macro's line fits in 120 columns.
- I2. Owner questions, as I recommended: C-Q2 (`ReadyForCommand` in both vendors), C-Q4 (`EvaluateVariable` and
  `EvaluateVariableBody`; `NextStatementSavingStack`), C-Q7 (`Statements::PrepareRun`, POP as a `Pop:` label in
  `Statements` that falls into the shared RETURN), C-Q8 (REDDY, GOTK and Q dropped, in prose), C-Q9
  (`INPUT_BUFFER_BASE`, Also BUFOFS, and `LAST_COMMA_COLUMN`, Also NCMPOS) and C-Q10.
- I3. C-Q3, departed from for LINCHK and TABER. In the II Plus and IIe these fall inside instructions. I had
  recommended dropping them, but every overlay label must resolve in the native build (the lister, string-function
  and listing comparisons), so dropping them would weaken those tests. They are `PrintComma::ZoneMaskOperand` and
  `PrintTabOrSpace::EvaluateCallHigh`, equates at the operand bytes, each documented as an address nothing enters.
  `PrintComma::NextZone` carries LINCHK in the enhanced IIe and COMPR1 elsewhere. `PrintTabOrSpace::ReadArgument`
  carries TABER in the enhanced IIe and LINCH1 elsewhere. Microsoft's own LINCHK is PRINT's number item and its
  TABER the `php`, so the enhanced IIe's `ReadArgument` cites TABER by M6502, but the comma code's LINCHK and the
  operand byte's TABER are the overlay's own and cite UNKN.
- I4. NOTABR is `PrintSpaces::ContinuePrint`, as X2 has it, not a top-level label (C-Q3's draft). ERRCRD and ERROR1
  are both `ReportError::PrintMessage`; the table gave the PET's as `ShowMessage`.
- I5. The shared `IntegerVariableValue` expands inside each vendor's `LoadVariableValue`, so GOOO and GOOOOO are
  `LoadVariableValue::LoadNumericVariable` and its labels, and the code after the macro stays the routine's.
- I6. AppleSoft's ON is an alias in `AppleSoft.HistoricalNames.asm` (`On = Statements::On`, Also ON (UNKN)), since
  the shared `OnStatement` defines `Statements::On`. BASIC 4's disk parser has a label of its own named ON (part
  F), so `BasicNames.VendorLabelNames` adds ON beside GETRTS.
- I7. The shared `ErrorFinish` now holds only `AddErrorSuffix` (TYPERR). The new `ReportMessageRoutine` emits
  `ReportMessage`. Each vendor closes its own `ReportError` between them, since the documentation tracks a
  routine's scope within one file. S8's locals of part C's routines now take their rows' names (EditLine,
  SetMoveSource, MoveDown, ScanLine, StoreToken, StoreByte, SetTokenizeState, CheckRem, CopyLiteral, StoreLiteral),
  each with its old name in `Also:`. Where a routine's start differs by build, each `.if` branch opens and closes its
  own `.proc` (Commodore's `EvaluateVariableBody` and `EvaluateVariable`), or a per-build label carries the old
  names.
- I8. New constants: AppleSoft's `CONTROL_C`, `KEYBOARD_CONTROL_C`, `COMMA_NEWLINE_COLUMN`, `INPUT_LINE_LIMIT` and
  `PROGRAM_ORIGIN` (with `INPUT_BUFFER_BASE` and `LAST_COMMA_COLUMN` from I2), and Commodore's `CARRIAGE_RETURN`,
  `LINE_FEED`, `CURSOR_RIGHT`, `CURSOR_LEFT`, `DELETE_CHARACTER`, `CURSOR_HOME` and `CURSOR_DOWN`. Two `*+5`
  branches are labels: `ReadLine` in the statement fetch, where `shortEnd` is 0 (BASIC 2 and 4; DIRCN1 in their
  documents), and `StoreLink` in the command loop's link pass, where `linkReturns` is 0 (BASIC 1). Some values are
  still numbers with a trailing comment: the JMP opcode both cold starts store, AppleSoft's carriage return and
  16-column zone, the PET clock's reserved-variable threshold, digit count and digit mask, the screen's page and the
  direct line's $FF; naming them is left for a later pass. The PET line reader's carriage return (`InputLine`) stays
  `$0D`, since the tests assemble `Commodore.CommandInput.asm` without the file that defines `CARRIAGE_RETURN`.
- I8a. The PET roots pass `PrintTabOrSpace` to the shared `PrintItems`. Their other macro arguments keep the old
  names they had (CHRGET, NEWSTT, READY, LINPRT, FREMES and others), which resolve through `Also:`.
- I9. Part F's names stay as they are in the code: BASIC 4's trampoline ISVAR (the shared evaluator still branches
  to ISVAR), BASIC 1's GETDTL, INPSTP, TISTR, TINUM and INCTRM, and the revised BASIC 4's INPNUL. `StopEmptyInput`
  is BASIC 4's own INPSTP, under `.if localStopLabel`.
- I10. The C# debug hosts are unchanged: their old names resolve through `SymbolsWithHistoricalNames`.
- I11. Tests and their helpers:
  - The builds give NTHIS1 and NTHIS2 one step apart, and TABER to different definitions, so a test that predefines
    one of them passes its build to `BasicNames` (E11): the PET math, alias and print tests now do. `VendorLabelNames`
    adds ON, and those names may be a historical name on the vendor's own code, not only on an alias in its
    historical-names file (`BasicAttribution.AssertNotShared`).
  - Shared prose links the `ON` statement as `<Statements::On>` rather than naming it: ON is AppleSoft's alias, and
    AppleSoft has no `TOKEN_ON` to mark it as a keyword.
  - `BasicNames.CurrentLabel` labels a test's own definition by its current names alone. Defining the old name too
    would be a second definition of a name a source's `Also:` gives; the rename gate found this in the composed
    PET source.
  - The standalone PET sources predefine `BasicNames.ScopedNames` in `PetNativeEquatesTests.Assemble` (and no longer
    a second time in the array test), and the GET test includes `MsBasic.VariableInput.asm` for `INPUT_MODE_GET`.
  - The rename gate renames `ReservedWords` (both dispatch tables) and LASTWR: the interpreter files are converted,
    and LASTWR is the only label left that both vendors' unconverted files define (in BASIC 1, in a macro's body).
  - `VendorOldNamesResolveOnlyInTheirVendorsBuilds` reads the interpreter files too, and counts a name a shared
    module gives in one vendor's builds as that vendor's where the other's own files give it. It pins that set to
    LINCHK.
  - `BasicSharedFloatAliasesTests` allows BASIC 4's own ON, and checks that it is the overlay's ON, not
    `Statements::On`.
  - `BasicInterpreterConversionTests` is new: in each of the eight builds, every old name the fourteen files give
    that the MACRO-10 overlay defines reaches its value, and every definition reaches the overlay by a name, apart
    from the new constants, the two `*+5` labels, AppleSoft's `PrintTabOrSpace`, whose old names are on its
    per-build label (I3), and BASIC 1's labels whose HV1 names the overlay does not define there (I12).
    Each old name cites only its vendor's documents, Microsoft's source or UNKN (for Commodore, the BASIC 4 kernal
    listings too, as the workspace's do), all in the bibliography.
  - `BasicInterpreterRoutineTests` is new (below).
  - `BasicBuildLinkTests` is new: in each of the eight builds, every link in a BASIC comment the build assembles names
    a definition the build assembles. The lint resolves a link against every build's definitions of a conditional
    source, so it passed links in all-builds comments to definitions only some builds have; the closing reviews found
    nine of them in part C's files. The test found three more outside them: the shared RETURN's links to AppleSoft's
    `Statements::PopFinish`, and AppleSoft's cassette comments' links to the enhanced IIe's `CALLC5` and the others'
    `SETA2`, which are now described or in backticks. `DocumentationSet.CommentInBuild` is internal for it.
- I12. Old names the table's rows give only for BASIC 2 and 4, which HV1 and HV1R also give to BASIC 1's own code:
  XSPAC2 (`PrintSpaces::Next`), GLET (`DispatchStatement::ToLet`), FREMES (`SignOnMessage`, inside
  `BytesFreeMessage`'s string) and CRTSKP (`PrintSpace::CursorRight`), each now a label in BASIC 1's branch, cited
  HV1 and HV1R. Inside the two versions of `PrintSpaces`, which every build has, the labels cite only their own
  builds' documents (E8a): BASIC 1's XSPAC cites M6502 beside HV1's XSPAC1, and each version's NOTABR its own
  builds' documents. MORSTS, BASIC 1's own compare inside `NextStatement`, is in prose: as a label it would be a
  per-build `NextStatement::` name, which the standalone sources that define `NextStatement` cannot predefine. DIRCN1
  (CBM4S79, HV2, HV4, HV4R) is now on `NextStatement::ReadLine`. The overlay defines none of the BASIC 1 names at
  BASIC 1's addresses, so the conversion test exempts those labels there.

Checked: the full suite, the rename gate, the lint tests and `BasicInterpreterConversionTests`. The suite's
skipped tests are the ROM-dump comparisons, which need dumps that are not here, so they did not run.

`BasicInterpreterRoutineTests` runs these routines in the enhanced IIe's AppleSoft and PET BASIC 4 and checks
their `Out:` values:

- AppleSoft's `InputLine`: lines of 0, 3, 239 and 245 characters (cut to 239), bit 7 cleared, the zero after them,
  the blank prompt, and A, X and Y.
- `Tokenize` in both builds: the token, `TextPointer` and Y with the header.
- AppleSoft's `CheckStop`: other keys return at once with the key in A; Control-C goes on to `InputCharacter`.
- AppleSoft's `PrintCharacter`: bit 7 and `FlashMask` on a printable character only, and A with bit 7 clear.
- BASIC 4's `PrintCharacter`: the kernal's A, with zero and negative from it.

The existing tests run the rest. The debugger's contract checking ran clean on PET BASIC 2, PET BASIC 4 and the
enhanced IIe's AppleSoft. The contract check's program adds PRINT's comma, `TAB(` and `SPC(` to the expression step's, and a
GOSUB that AppleSoft leaves by POP. As a control, a false `Keeps: A` added to AppleSoft's `PrintNewline` was
reported.

### E. AppleSoft's own files (X8 step 7)

Converted, with `; retrocore: style=strict`, part E's three modules, `AppleSoft.AppleCommands`,
`AppleSoft.HighResolution` and `AppleSoft.PlatformHelpers`, and the AppleSoft files still outside the style: the
small modules that compose the shared ones (`Arrays`, `Assignment`, `Functions`, `Lister`, `MemoryManagement`,
`NumericConversion`, `Strings`) and the root, `AppleSoft.asm`. Every AppleSoft file is now strict. The other
AppleSoft files' references to part E's names follow (the dispatch table, `TrapError`, `ReadLowResCoordinates`,
`Statements::Normal`, the enhanced IIe's tokenizer and PRINT helpers). The bytes are unchanged in all eight builds,
the three AppleSoft and the five PET.
Of the shared modules, only the WAIT entry's comment changed: it links `Statements::Wait` rather than naming WAIT,
which is now AppleSoft's alias (E-2). `BasicBuildLinkTests` found four links in these files to definitions only some
AppleSoft builds have (`CompareCommaColumn`, `Statements::CallAppleSoftCassette`, `Statements::SetArrayBlock` and the
PET's `Statements::Print::NumberItem`), now in backticks.

Decisions and how the table was applied:

- E-1. Owner questions, as I recommended:
  - E-Q1: the entries other routines branch into stay `Proc::Label`s, listed under the routine's `Entry:`.
  - E-Q2: the hi-res engine is the scope `HighRes`; `ReadHighResCoordinates` and `ReadLowResCoordinates` are top
    level.
  - E-Q3: the Technical Information Library's HPLOT, HLIN, DRAW and XDRAW for the engine entries are in prose,
    since the statements have those names. The engine entries keep the overlay's HPLOT0, HGLIN, DRAW0 and XDRAW0
    (UNKN). SETHCOL is `HighRes::SetColor`, split out of `Statements::HColor`, which falls into it after its
    `EvaluateByte`. RESUME cites UNKN, not ASTIL as I had recommended: ASTIL's RESUME is $F317, one less than the
    handler, and the bibliography cites ASTIL only where its address is the build's value; the TIL's name is in
    prose.
  - E-Q4: keywords split at their words (`HGr2`, `HColor`, `XDraw`, `PrNumber`).
  - E-Q6: the enhanced IIe's helpers that other modules call are top level.
  - E-Q7: `ToIllegalQuantity`, `RejectHighResArgument`, `Statements::SetArrayBlock` and
    `Statements::CallAppleSoftCassette`.
  - E-Q8: `LowTwoBitsMask`, `BitTwoMask` and `RowInGroupMask`, with the operand trick in their comments.
  - E-Q9: the unreachable 10 bytes after `HighRes::StepVertical`'s last `bcc` are documented, with no label.
  - E-Q10: LASTWR is `InterpreterEnd`, and the wrong "Monitor workspace" comment now says the reserved bytes cover
    the Monitor's code.
- E-2. Departures from the table's names:
  - HCOLO1 is `HighRes::SetColor::Done`, since the return is now SetColor's (E-Q3).
  - MASK03 and MASK04 are `HighRes::PlotStep::LowTwoBitsMask` and `HighRes::StepVertical::BitTwoMask`: each is an
    equate at an operand inside its routine, so it is that routine's, not the scope's.
  - WAIT, AppleSoft's second label on the shared `Statements::Wait`, was DROP. The overlay's label must still
    resolve, so it is an alias in `AppleSoft.HistoricalNames.asm` (`Wait = Statements::Wait`, Also WAIT (UNKN)), as
    ON is (I6), and the dispatch table names `Statements::Wait`.
  - The table's notes give HPLOT, DRAW and XDRAW for the statements as AS82, but its Documents column has AS82 as
    spelling only for them, so they cite UNKN, as the other spelling-only names do.
- E-3. E-Q5 waits for X10. The engine still names the Monitor's bytes it borrows by the Monitor's names in
  AppleSoft.Equates (COLOR as the pixel mask, GBASL and GBASH as the screen byte's address), as the rest of the
  AppleSoft files name the Monitor's entries and soft switches (INPORT, MPLOT, HISCR). X10 replaces those copies with
  IIeEquates' names and AppleSoft's own definitions of the Monitor's entries (E-8).
- E-4. `AppleSoft.PlatformHelpers.asm` interleaved the enhanced IIe's code and the other builds' at the same
  addresses, sharing a `clc`, `pha`, `pla` and `rts` across `.if` boundaries. Each build's code is now written whole
  under one `.if ENHNCD`/`.else`, as whole routines; the shared instructions are written in each.
- E-5. New constants: `LOW_RES_ROWS`, `LOW_RES_COLUMNS`, `TEXT_ROWS`, the inverse and flash masks
  (`INVERSE_MASK_NORMAL`, `INVERSE_MASK_INVERSE`, `INVERSE_MASK_FLASH`, `FLASH_MASK_FLASH`), `HIGH_RES_PAGE1` and
  `HIGH_RES_PAGE2`, `PIXELS_PER_BYTE`, `HIGH_RES_ROW_BYTES`, `HIGH_RES_COLUMNS`, `HIGH_RES_ROWS`, `HIGH_RES_COLORS`,
  `FIRST_PIXEL_MASK`, `LAST_PIXEL_MASK`, `SHAPE_PLOT_BIT`, and the enhanced IIe's `COMMA_LIMIT_40` and
  `COMMA_LIMIT_80`. The array header's offsets use `ArrayHeader::LENGTH` and `DIMENSIONS`.
- E-6. Found in the code and documented, not fixed: those the part E proposal lists, and that
  `HighRes::StepHorizontal` and `StepVertical` take their direction from the negative flag the caller's load or
  shift leaves, not from A; and `RECALL` accepts a stored array one byte longer than the array, writing that byte
  past it, since it compares the array's length with the stored length less one.
- E-7. Tests and their helpers:
  - The rename gate's macro rename is now `AssignString`, the top-level label at the end of the shared
    AssignmentStart macro: LASTWR, which it renamed, is converted here and in part F. The gate now exercises
    lookups by AssignString, the name it renames, instead of by LASTWR.
  - `BasicSharedFloatAliasesTests` counts WAIT among AppleSoft's names, and `BasicSharedMemoryAccessTests` expects
    WAIT's topic to be the alias's.
  - `BasicMathMachine.Call` and `CallUntil` take an optional `negative`, for a routine that tests the flag its
    caller's load left.
  - `BasicAppleConversionTests` is new: in each AppleSoft build, every old name the files give that the overlay
    defines reaches its value, and every definition reaches the overlay by a name, apart from the new constants,
    the switches and `HighRes::SetColor` (SETHCOL, which the overlay does not label); each old name cites only
    AppleSoft's documents, Microsoft's source or UNKN, all in the bibliography.
  - `BasicAppleRoutineTests` is new (below).
- E-8. X10 is not in this step. As decided, including MonitorEntries.asm, grown with the entries AppleSoft calls, brings
  in Apple's Monitor names INIT, WAIT, PLOT and READ, which AppleSoft's builds give other definitions (`ColdStart`,
  `Statements::Wait`, `Statements::Plot`, `Statements::Read`); growing MonitorEntries with ReadPaddle clashes, in the
  firmware's builds, with the firmware's PREAD; and DOS defines CharacterOut, ReadKey, SetInput and SetOutput itself.
  The owner decided (2026-11-24) that X10 takes its own alternative, after DOS's X7 pattern, in a pull request of its
  own after this step: unlike DOS, AppleSoft includes IIeEquates.asm only, and like DOS it defines the Monitor entries
  it calls in AppleSoft.Equates with `Inherit:`, citing Apple's names except those that clash and adding AppleSoft's own
  spellings, and gives AppleSoft's spellings of IIeEquates' names as aliases in AppleSoft.HistoricalNames;
  MonitorEntries.asm is unchanged.

Checked: the full suite, the rename gate, the lint tests and `BasicAppleConversionTests`. The suite's skipped tests
are the ROM-dump comparisons, which need dumps that are not here, so they did not run.

`BasicAppleRoutineTests` runs these routines in the enhanced IIe's AppleSoft and checks what their documentation
says:

- `HighRes::Position`: the interleaved row address, the byte in Y and `HighResByteIndex`, the pixel mask, the point,
  and the color flipped for an odd byte, at points from (0,0) to (279,191).
- `HighRes::FindCoordinates`: it rebuilds the point `Position` set.
- `HighRes::StepHorizontal`: within a byte, across bytes, and its wrap within the row, both ways.
- The enhanced IIe's `UppercaseCharacter`, `DistanceToColumn` (40 and 80 columns, with the caller's carry) and
  `CompareCommaColumn` (A, carry and negative).

The debugger's contract checking ran clean on the enhanced IIe's and the original IIe's AppleSoft, with a program of
GR, COLOR=, PLOT, HLIN, VLIN and SCRN; HGR, HGR2, HCOLOR= and HPLOT TO; TEXT, NORMAL, INVERSE and FLASH; VTAB and
HTAB; SPEED=, TRACE and NOTRACE; ONERR GOTO; HIMEM: and LOMEM:; PR#0 and IN#0; and DEL as a command. The II Plus could
not be run that way: the debugger session's prompt check does not see its prompt. As a control, a false `Keeps: A`
added to `HighRes::Plot` was reported.

### X. AppleSoft's Monitor and IIe names (X10)

AppleSoft now takes the IIe's names from `IIeEquates.asm`, as the owner decided after part E (E-8). Its copies of 78
of the Monitor's, the IIe's and the firmware's names are gone from AppleSoft.Equates (CV stays, inheriting the
Monitor's), and its files use the current names. The bytes are unchanged in all eight builds.

- X-1. AppleSoft.Equates includes `IIeEquates.asm`, not `MonitorEntries.asm`. It defines the Monitor's entries
  AppleSoft calls, after DOS's X7 pattern: each is an equate at the Monitor's address that inherits
  `<Monitor:...>`'s documentation and cites Apple's names (A2RM78, A2RM79, IIEROM82, IIETRM85) and AppleSoft's and
  Microsoft's own spellings (MPLOT, MWAIT, OUTPOR and the rest UNKN; CQINCH, CQINLN, CQCOUT, CQCSIN and OUTCH M6502).
  Apple's PLOT, READ and WAIT are left out, since they are names of AppleSoft's statements. The low-resolution
  routines and the cassette bit reader are in the Monitor's scopes, `LowRes` and `Cassette`. `CV`,
  `EightyColumns::CursorColumn` (OURCH) and the enhanced IIe's `AppleSoftCassette` (C5ROM) inherit the Monitor's and
  the firmware's documentation the same way.
- X-2. AppleSoft's and Microsoft's spellings of names IIeEquates gives under Apple's are aliases in
  `AppleSoft.HistoricalNames.asm`: BUF (M6502, ASTIL) and CQPRMP (M6502) on `InputBuffer` and `PromptCharacter`,
  and the overlay's WNDWDT, SETSLO, SETINT and RD80VI (UNKN). Every AppleSoft build includes IIeEquates, the II
  Plus's too, as it had the copies; `EightyColumns::CursorColumn` is AppleSoft.Equates' own equate (D-Q1).
- X-3. The shared modules' BUF is `InputBuffer`, which both vendors define.
- X-4. E-Q5: the hi-res engine names the Monitor's bytes it borrows `HighRes::PixelMask` (`PlotColor`),
  `HighRes::ByteAddress` and `ByteAddressHigh` (`LowResBase`, `LowResBaseHigh`). ASTIL's HBAS, its name for the
  hi-res byte address, is on `HighRes::ByteAddress` (row 1144).
- X-5. Tests:
  - The AppleSoft documentation set in `SdkDocumentationTests.Sets` holds every file the assembly reads as well as
    every AppleSoft and shared BASIC file, so links to IIeEquates' definitions resolve; the AppleSoft alias test's
    resolver has the other modules' sets. The E-Q5 names, which the overlay comparison leaves out, are checked to be
    the Monitor's bytes.
  - BUF is both vendors' name: `BasicNames.VendorLabelNames` adds it, the vendor-leak checks count it with LINCHK,
    and the PET's alias test checks that it is the PET's input buffer.
  - The alias tests accept an AppleSoft alias whose target IIeEquates documents; such a location has no code for the
    debugger's position check. AppleSoft.Equates may cite Apple's Monitor manuals.
  - The E-Q5 names give no overlay name of their own; `HighRes::ByteAddress` gives ASTIL's HBAS.

### B7. The dependents of BASIC's old names

- B7-1. DOS's and the enhanced IIe firmware's links into AppleSoft name its definitions by their current names
  (`<AppleSoft:ProgramStart>`, `<AppleSoft:NextStatementSavingStack>` and the rest), and DOS's Equates describe in words
  the AppleSoft locations its equates mirror. The firmware's own copies of AppleSoft's page-zero names, which its F8
  kept until AppleSoft was converted, take AppleSoft's current names (`LineNumber`, `ArraysEnd`, `StringsBottom`,
  `MemoryTop`, `DestinationEnd`, `SourceStart`, `ShapeTable`), with the old ones in `Also:` cited UNKN, as its SHAPEPTR
  is; inside `AppleSoftCassette`, whose shape-table entry is also `ShapeTable`, the copy is `::ShapeTable`. DOS's BASIC
  vector (P2) keeps DOS's own names for AppleSoft's entries (ASBRK1, ASCNTU1, ASRSEQ1 and the rest), which DOS's
  listings give.
- B7-2. The disassembler takes its names from the sources (`MachineSymbols`), so it emits the current ones; only its
  example comments changed, in `MachineSymbols` and `DebugSession.Memory`.
- B7-3. docs/Apple2.md and docs/Pet.md name the converted routines by their current names, where they first appear with
  the old ones beside them. The extension README's account of the MACRO-10 overlay and docs/Pet.md's kernal jump-table
  names describe sources that keep those names. The C# debug hosts look BASIC's addresses up by Microsoft's names, which
  both the native and the MACRO-10 builds give (I10).

### F. Commodore's own files (X8 step 7)

X8 step 7, part F. Converted, with `; retrocore: style=strict`:

- the PET roots, `Basic1.asm`, `Basic2.asm` and `Basic4.asm`;
- BASIC 4's extension: `Commodore.Basic4Extension.asm`, `Basic4SystemEquates`, `Basic4Monitor`, `Basic4Record`,
  `Basic4DiskCommands`, `Basic4DiskParser` and `Basic4RomEnd`;
- the patches, BASIC 1's `Commodore.Basic1Patches.asm` and BASIC 4's `Commodore.Basic4Patches.asm`;
- `Commodore.StringAssignment.asm`, `Commodore.StringGarbageCollection.asm` and `Commodore.TimeAssignment.asm`;
- the platform's composition files, `Commodore.Platform.asm` and `Commodore.InterpreterMacros.asm`.

Part C's leftovers (I9) are converted too. The bytes are unchanged in all eight builds.

Decisions and how the table was applied:

- F1. Scopes:
  - the monitor is `.scope Monitor`, opened and closed in its macro, with flat routine names (F-Q7);
  - the disk helpers are `Disk` (F-Q2), which `Commodore.Basic4Extension.asm` declares empty, as
    `MsBasic.Families.asm` declares the shared families, so that Record, DiskCommands, DiskParser and RomEnd each
    continue it;
  - the disk statements are in `Statements`, named for their keywords (X13: `Statements::DOpen` ...), and
    `ForgetDiskStatus` (OLDCLR) is top level, since Kernal4's channel selectors call it before `TALK` and
    `LISTEN`;
  - BASIC 4's collector is `Strings::CollectGarbage`, as E6 left it, now a `.proc` with nested routines.
- F2. Owner questions, as the log recommends:
  - F-Q3: DCOPY, DSCRTC, GTVLCN and MGO, which no document but the overlay gives these routines, cite UNKN, since the overlay
    comparisons need every overlay label to resolve. (The question's premise is not quite right: BASIC 4's jump table
    gives DCOPY to the kernal's entry `KernalCopy`, which names it in prose, since the overlay's DCOPY is in the same
    build.) Checked against mist64/cbmsrc at the bibliography's commit, Commodore's
    kernal listing and its reconstruction (K4S79, HVK4) call them COPY, SCRTCH, CONT and GO, each a name BASIC 4
    already gives another definition (`StoreString::CopyCharacters`, `EraseProgram`, `Statements::Cont`,
    `Statements::Go`), so they are in prose, as the recommendation said.
  - F-Q4: the table's choices, with three changes. ERRS1 is `Monitor::ToShowError`, named for the
    `Monitor::ShowError` it jumps to. ERRL is the scope-level `Monitor::LoadOrSaveFail`, since its code comes before
    LD's, which the command tables need as LoadOrSave's start. SNER3 is the entry
    `Disk::ParseParameters::RejectParameter` (X2), since the parser's `Done` follows it.
  - F-Q5: the templates' offsets and lengths are `TEMPLATE_*` constants, each position and length asserted.
  - F-Q6: the parser's bits are `PARSED_*` constants, and every check's mask is an OR of them.
  - F-Q8: the collector's bytes take scoped aliases: `GapOpen` (HIGHDS's byte, a flag here), `Source` (GRBPNT's)
    and `Destination` (GRBTOP's).
  - F-Q9: `FindStringLink` is one routine with two entries, `CompareStatusLow` and `AddLength`, and the revised
    chip's `TestStatusString` is its own routine.
  - F-Q10 and F-Q11: K5's and K6's names. The clock code is `.proc AssignClockString`, not locals of
    `AssignString`, which is a bare label at the end of the shared `AssignmentStart`; INPCOM stays on that label.
  - F-Q12: InterpreterEnd (K3); D-Q10: `CatalogOutputFile` and `CatalogOutputDevice`.
  - The table's RWRT reason is the other way round: with no record length the code leaves `S` in RecordLength and
    returns `W`. The code's comments say what it does.
- F3. One definition for a name another file already defines:
  - SATUS joins `IoStatus`'s `Also:` in `Commodore.Equates.asm`, on both branches (lineage), so the extension's
    assertion reads `IoStatus = $96`;
  - CR joins `CARRIAGE_RETURN` in `Commodore.ChannelPrint.asm`;
  - ONTK is `TOKEN_ON`, now defined with the token table in `Commodore.DispatchTables.asm`; only BASIC 4's overlay
    gives it, so the workspace and interpreter tests exempt it in BASIC 1 and 2 (`Basic4OverlayNames`);
  - BAD is `MonitorHexByte = NumberBuffer`, asserted $0100; FNADR2, RECPOS and DIDCHK are aliases of the bytes they
    share; MS1 and MSG1, CLRCH and CLRCHN, CLOS5 and FCLOSE are one definition each.

  The extension's test supplies the two constants the platform defines (`CR`, `ONTK`) as it supplies its other BASIC
  entries, and the extension's header lists them.
- F4. Citations:
  - Labels whose rows say "none found" cite UNKN, as W2 has it, so every overlay label still resolves. That now
    includes BASIC 4's NOTDS and NOTDS1 (with HV4's and HV4R's DSKX2 and DSKX1), which E5 left without `Also:` because their
    labels were reached only through a Commodore alias; they are in Commodore's own macro now, so
    `BasicNames.OverlayOnlyLabels` drops them.
  - The reconstructions' address-generated names the table's notes suggested (HV1's LE1AA ..., HV4R's LBA70, HV4's
    LBA74) are dropped, as X7 settled.
  - The lineage rule: BASIC 1's and BASIC 4's `StopEmptyInput` both cite INPSTP (UNKN), PATCH1 (HV1, HV1R) and
    BUFFU1 (HV4R); every PET `EvaluateVariable`, BASIC 4's trampoline and the other builds' routine, cites ISVAR (M6502,
    CBM4S79, HV1, HV1R, HV2, HV4, HV4R), and so do both collectors' GARBA2; `FindStringLink::CheckStatus` cites
    ADJ (CBM4S79, HV4, HV4R); every build's `InterpreterEnd` cites LASTWR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R,
    K4S79, HVK4) and `ROM_ORIGIN` ROMLOC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R). A question for the owner: the
    overlay gives ISVAR to BASIC 4's trampoline, where the comparisons need it, but BASIC 4's own documents (CBM4S79,
    HV4, HV4R) give it to the code the trampoline jumps to, `EvaluateVariableBody` (ISVAR1, UNKN), which is also
    Microsoft's ISVAR. The name stays on the trampoline, with the mismatch in its prose. A second: CBM4S79's ROMLOC
    is its RAM build's $3000, a value no PET build has; the lineage rule is read to cover it, as it covers BUFLEN's
    80 and 81.
  - The table's other names go on the definitions: PATCH1 to PATCH7 (HV1, HV1R) on BASIC 1's patches; PATCHG, PATH0,
    PATH1, PATCHH and PATCHI (HV4R) on the revised chip's; T1, T2, RCNT, FSBLK, STAL, ZZZ1, TAPE2, TKSA and CKOUT,
    which the table gives as HVK4's but K4S79 gives at the same places too, so both are cited; PATCH5 (HVK4) on
    `Disk::StoreStatusLink`. The table's CHANL is not `STATUS_LOAD_ERROR`'s: the kernal listings define it as
    $0010 under "CONSTANTS FROM BASIC" and clear it to 0 when STOP stops the tape, so it is on every PET
    `CurrentChannel`.
    The kernal listings' POS, PARCHK and COUNT for disk-workspace bytes, and BASIC 4's jump-table names (CONCAT ...),
    clash with other definitions, so they are in prose.
- F5. Part C's leftovers (I9): BASIC 4's ISVAR trampoline is `EvaluateVariable`, and the shared evaluator branches to
  `EvaluateVariable` in every build. BASIC 1's GETDTL, INPSTP, TISTR, TINUM and INCTRM are `GetDataLine`,
  `StopEmptyInput`, `CheckClockString`, `RouteNumericVariable` and `AdvanceTerminalPosition`; the revised BASIC 4's
  INPNUL is `HandleBlankInput`; BASIC 1's GETSTR, GETST1 and ARYINC are `BeginGetString`, `ResumeGetString` and
  `ArrayHeaderSize`. Their callers in part C's files and the shared modules use the new names. A shared Commodore
  file's comment names a routine only some builds have in backticks, not as a link, since the documentation of the
  other builds does not have it. The roots pass `PrintTabOrSpace` (TABER), `SignOnMessage` (FREMES),
  `Basic4SignOnMessage` (SIGNON) and every other macro argument by its new name.
- F6. The two over-length lines in `Basic1.asm` (and a third, the statement fetch's, once its argument had its new
  name): a line exclusion quiets the editor, but the SDK's documentation tests do not honor it, so the lines are
  shortened instead. `CommodoreInitialize` and `CommodoreStatementFetch`, part C's macros, take the workspace's
  `LOCAL_TERMINAL_POSITION` and `INPUT_BUFFER_PAGE` from the workspace rather than as parameters; every caller
  passed those switches or the values they have in its workspace (the table's rows for those parameters, in part C's
  sections, are not edited), and BASIC 1's `PROBE_LOAD_INDEX_ZERO` is `PROBE_ZERO_INDEX`.
- F7. BASIC 1's switches the table renames (`SUBSCRIPT_CHECKS_NUMERIC`, `POSITIVE_INTEGER_CHECKS_TYPE`,
  `STRING_CLEARS_FAC_EXTENSION`, `COLLECTOR_FULL_POINTER`, `COLLECTOR_PATCH_ARRAY_STEP`, `COLLECTOR_SUBTRACT_OFFSET`,
  `STRING_PREAMBLE_INDIRECT_RETURN`), and `PROBE_ZERO_INDEX`, are renamed in the root, the shared folder's README
  and the test that predefines one; the root rejects each old name predefined, as W7 has it.
- F8. Structure:
  - BASIC 4's string assignment: the end of `StoreString`'s copy for the linked collector, which was left after
    `StoreString` closed, is the new macro `LinkedStringRelease`, expanded inside it; `LinkedStringStore` emits
    `.proc StoreLinkedDescriptor` (E6's name, with `StoreDescriptor` its equate), whose locals are its own
    (`StoreLinkedDescriptor::ReleaseOld`, not the table's `StoreString::`).
  - The clock assignment is `AssignClockString` with its nested `AddClockDigit`, whose `ToIllegalQuantity` the
    length check branches into.
  - `PATCH_FILL`, the $AA both BASIC 4 chips fill their patch space with, is defined in
    `Commodore.Basic4Patches.asm` and `Commodore.Basic4RomEnd.asm` under `.ifndef`, since the extension's tests
    include one without the other.
  - The $B000 chip's checksum byte is `InterpreterChecksum`, with HV4's and HV4R's CKSUMB, as the plan note on the
    unlabelled byte suggested; the overlay leaves it unlabelled, so the overlay comparison exempts it.
- F9. Shared modules touched, minimally: `MsBasic.Assignment.asm` (the two Commodore macros it invokes),
  `MsBasic.OperandEvaluation.asm` (`EvaluateVariable`), `MsBasic.VariableInput.asm` (`BeginGetString`),
  `MsBasic.StringGarbageCollection.asm` (`ArrayHeaderSize`), `MsBasic.StringConcatenation.asm` (`FindStringLink`)
  and the shared folder's README (the renamed macros and switches). `MsBasic.MemoryAccess.asm` still names `ROMLOC`
  and `LASTWR`, which reach every build's new names through `Also:`.
- F10. Tests and their helpers:
  - The rename gate's second rename is `AssignString`, as E-7 records.
  - `BasicCommodoreConversionTests` is new: in each PET build, every old name the part's files give that the overlay
    defines reaches its value, every definition reaches the overlay by a name apart from the SDK's own switches,
    constants and scoped aliases, and every citation is Commodore's, Microsoft's or UNKN, in the bibliography; the
    leftover names are old names only.
  - `BasicCommodoreRoutineTests`, `BasicMonitorRoutineTests` and `BasicDiskRoutineTests` are new (below).
  - `BasicWorkspaceConversionTests.VendorOldNamesResolveOnlyInTheirVendorsBuilds` reads the PET roots, which give
    ROMLOC as AppleSoft's Equates does.
  - The test sources that assemble the part's files alone follow the macros' new names and include
    `MsBasic.Layouts.asm` where the files now use its layouts; `PetBasic4ExtensionTests` exempts the disk commands'
    new constants and scoped aliases from its overlay check.

Found in the code (documented, not fixed):

- BASIC 4's string links: the original chip recognizes `DS$`'s characters by their address alone (F-Q9); the test of
  `FindStringLink`'s address against `ROM_ORIGIN` never branches, since the bit-15 test before it catches the ROM.
- The clock string: `ClassifyCharacter` is the reader's entry after its colon test, so `TI$`'s string takes every
  byte from `0` up as a digit, counted from `0` (`TI$="1A0000"` sets 27 hours), and rejects only those below `0`; a
  space is skipped by reading the byte after `TextPointer` instead, which moves `TextPointer` on, and that byte gets
  the reader's full test (a byte from `:` up is rejected, another space skipped); the time is not
  checked against 24 hours. `BasicCommodoreRoutineTests` pins the first.
- BASIC 4's error-channel read: only a carriage return ends it; a zero is stored like any other byte, so nothing
  stops a long reply.
- The monitor: `EnterByCall` reaches `SaveState`'s subtraction without setting the carry; the overlay's "after a
  CALL" is the kernal's reset with the diagnostic line low; `L` and `S` take at most 15 filename characters;
  `ReadCharacter` at a return drops only its own return address, so a line that ends inside a nested read leaves its
  callers' on the stack; `ReadByte` takes a space and one digit as that digit and does not check its digits.
- The disk commands: the error channel's read has no length bound (a reply of 40 characters or more runs over the
  buffer's link); `HEADER` closes the unit's files before asking; `Confirm` drains a rejected answer by the zero flag
  the kernal's input leaves, not the character, though the screen editor always leaves it clear; every template with
  both names puts the second before the first; `R` is accepted and skipped; a name takes 16 characters, or 17 with `@`,
  and a second `@` name is a syntax error; `DiskIdSeen` shares `RecordLength`'s byte;
  `Statements::Catalog::DropAndClose` is unreachable.
- The revised chip's `FetchStatementCharacter` keeps the `PI` token from reaching `DispatchStatement`, which on the
  original chip takes it past the disk statements to an entry beyond `StatementTable`.

## Other dependents

- **DOS** left BASIC's names unchanged until this conversion: X7 in the DOS conversion's log, `docs/conversions/Dos.md`,
  which comes with the DOS conversion ("BASIC names wait for the BASICs' conversion"). P2 is DOS's BASIC vector: the
  labels for the six live words, written with a BasicEntries macro. When AppleSoft's entries are renamed, DOS's vector
  should name the entries it jumps to by their new names.
- **The disassembler** ([retrocore-disassembly](../../.claude/skills/retrocore-disassembly/SKILL.md)) names a
  program's uses of BASIC by these sources' names, so every program that calls AppleSoft's entries (`jsr FRMEVL`,
  `jsr HPOSN`) disassembles with the new names after the conversion. The ASTIL index's entries are what programs
  call most, so their new names matter most.
- **The tests** look labels up through `BasicNames` (plan item B4), which finds a label by its Microsoft name or
  its new one (X9).
- **The debug hosts** look up BASIC's workspace by name (X9).
- **The overlays** (D6) keep Microsoft's names: they are the oracle, and the table does not touch them.

## Found while drafting (document, never fix)

The parts' notes list these, among others; each is a comment for the conversion, not a byte change:

- LINGET's overflow branches into ON's token test: a line number whose high byte equals the GOTO token, followed by
  another digit, runs ON's skip loop (43776-44031 in AppleSoft, 35072-35327 on the PET; B1-Q6).
- The classic allocator, on a zero-length request that does not fit, collects twice and returns without
  allocating (B2).
- VAL leaves a zero after the string and does not restore TextPointer when FIN fails (B2).
- AppleSoft: 10 unreachable bytes at $F530; XDRAW's and DRAW's collision counts count different things; the
  overlay's DRWPNT and XDRPNT names are swapped (E).
- BASIC 4: the original ROM recognizes DS$ by address alone; the disk-status read has no length limit; HEADER
  closes the unit's files before asking for confirmation (F).
- Comments found wrong: MLTPL1's "implicit high bit" (it is the loop's end marker); VariableLookup's note on where
  AppleSoft keeps its zero bytes; Microsoft's comments for DPTFLG and TENEXP are swapped; LASTWR's "Monitor
  workspace" is Monitor ROM code.

## Per-part questions

### What the settled decisions answer

The decisions above, the settled rules of [the method](../ConvertingSources.md) and the merge (K1-K12) and review
(R1-R10) corrections answer most of the parts' questions; some only in part. The rest still need the owner. The part
sections below are the questions as drafted: names they propose may since have been settled otherwise (X13's casing,
K1-K12), and their "please confirm" asks are answered where the table below says so.

Answered:

| Question | Answered by |
| --- | --- |
| A-Q1 | D2 and X5 |
| A-Q2, A-Q3 | X1 (the functions in `Functions`) |
| B1-Q1 | X2 |
| B1-Q2 | X3 |
| B1-Q6 | the method: bugs are documented, not fixed |
| B1-Q8 | X13 (`GoSub`, `GoTo`) |
| B1-Q9 | X1 (the macro opens and closes the scope) |
| B1-Q10 | K1 and D4 |
| B1-Q11 | X9 and X15 |
| B2-Q1, B2-Q2, B2-Q5 | X1 |
| B2-Q3, B2-Q6 | X2 |
| B2-Q4 | X1, with R4 for ANDOP's per-build name (DOREL's place: A-Q9, open) |
| B2-Q8 | X5 |
| B2-Q9 | D5 (each variant that keeps less is its own `.proc`); the owner may confirm the list of five |
| B2-Q10 | X4 |
| B2-Q12 | K7 |
| C-Q1 | X9 |
| C-Q3 | X2 and R4 |
| C-Q5 | X4 (`ERROR_FILE_DATA`; ERROR_* for the offsets) |
| C-Q6 | K2 |
| C-Q11 | X5 |
| D-Q1 | X10 (IIeEquates in every build; AppleSoft's own `EightyColumns::CursorColumn`) |
| D-Q2 | X10 (`RandomValue`) |
| D-Q6 | X4 for the token and error copies; the method's one old name per definition for the rest |
| D-Q7 | R6 (the DOS log's X7: the Monitor keeps CV) |
| D-Q8 | X9 |
| D-Q9 | X3 |
| E-Q1 | X2 |
| E-Q2 | X1 (`HighRes`, Monitor decision 18) |
| E-Q4 | X13 |
| E-Q5 | the method: shared bytes get scoped aliases |
| E-Q6 | X1 (top level for what other code reaches) |
| E-Q9 | the method: documented, not fixed |
| E-Q10, F-Q12 | K3 |
| F-Q1 | X13 (`DOpen`, `DClose` ...) |
| F-Q2, F-Q7 | X1 |
| F-Q8 | K4, X1 and the method's scoped aliases |
| F-Q9 | X2 |
| F-Q10 | K5 |

Answered in part (what is left is the owner's):

| Question | Settled by | Still open |
| --- | --- | --- |
| A-Q4 | X2 | Whether NormalizeBits' proc starts at NORM2 or NORM1 |
| A-Q5 | X11 (the operand names) | `ToLongInteger` or `Truncate` for QINT |
| A-Q7 | K7 | Where `ZeroValue` sits (Float closed around it, or `Float::ZeroValue` with an alias) |
| A-Q10 | X15 and D4 | Renaming the parameter `limitAt120` |
| D-Q5 | X14 | `Statements::Load = KernalLoad` aliases; OUTCH as `CharacterOut` in both vendors |
| F-Q11 | K6 and K12 | `EvaluateVariable` waits on C-Q4; the names of TINUM1 and INPCON |

Still for the owner:

| Question | What it asks |
| --- | --- |
| A-Q6 | Drop AppleSoft's ZSTORD equate and WAIT label, or keep a vendor alias |
| A-Q8 | Whether the line-number printers stay in `Float` |
| A-Q9 | DOREL: top-level `ApplyRelation` (the table) or `Operators::Relation` (B2-Q4), now that `Operators` is a scope |
| B1-Q3 | The character reader's template and inner entries (the draft applies `ClassifyCharacter`, R5) |
| B1-Q4 | The lister as one `.proc Statements::List` |
| B1-Q5, E-Q7 | Whether the DOS log's P9 ("range, not block") holds here: `MoveRangeUp`, `SetArrayRange` |
| B1-Q7 | Dropping the parameters `newAlias` and `runLabel` |
| B2-Q7 | `Statements::DimNextArray` and `Statements::LetString`, which are not keywords |
| B2-Q11 | Labels for AppleSoft's fixed jumps at $E000 |
| C-Q2 | READY and MAIN (`ReadyForCommand`) |
| C-Q4 | BASIC 4's split ISVAR (`EvaluateVariable`, `EvaluateVariableBody`) |
| C-Q7 | The wrappers in front of shared statements (`PrepareRun`, `CheckGoStatement`, `Pop`) |
| C-Q8 | Dropping AppleSoft's unused REDDY and GOTK (a documented name in prose) |
| C-Q9, D-Q4 | Keeping or dropping AppleSoft's unused Microsoft configuration constants (BUFOFS, NCMPOS and the rest) |
| C-Q10 | The four renamed macro parameters |
| D-Q3 | The glossary names still open (SIZE, OLDOV, GRBTOP, GRBPNT, COUNT, INTEGR, CURTOL, LOWTR, LINWID, NCMWID) |
| D-Q10 | The kernal bytes BASIC 4's CATALOG reuses |
| E-Q3 | Splitting out SETHCOL as `HighRes::SetColor` (the TIL clashes themselves follow the method: prose) |
| E-Q8 | Names for the operand bytes read as masks |
| F-Q3 | Commodore's spellings of DCOPY, DSCRTC, MGO and GTVLCN, to check against K4S79 |
| F-Q4 | Scope-level tails (`Disk::Return`, `Monitor::ToPrompt` ...), which X2's rule does not provide for, or entries and procs as X2 says |
| F-Q5 | A macro for the disk-command templates' offsets |
| F-Q6 | Bit constants for PRSCHK, to be agreed with the workspace |

### A: The floating-point package
Scope of the part: Microsoft's floating-point package (MsBasic.AdditionCore, ArithmeticCore, MovementCore,
ConversionCore, DecimalInputCore, OutputCore, FloatConstants, Logarithm, TranscendentalCore, RandomCore), plus
IntegerConversion, Relational, SimpleFunctions, Switches, the ZSTORD equate, and the vendor files
AppleSoft.FloatAliases, AppleSoft.NumericConversion (WAIT) and Commodore.FloatAliases and FloatingPoint. 309 rows.

#### Cross-cutting

##### A-Q1. Where do the `Also:` names go for labels defined inside macros?

Every label in this part is defined inside a macro body (D2 keeps the macros). DocComments 2.4 said, when this was
drafted, that an `Also:` inside a macro's body is ignored (#132 has since changed that; see D2). So FADD, MOVFM, FOUT
and the rest cannot reach their new names from the definitions themselves, even though all of them are expanded once per
build (x1). This is also why today's vendor alias files exist.

- **Recommendation:** have the assembler and tools honor `Also:` on a label in a macro that is expanded at most once per
  assembly (done in #132). Every macro in this part that defines labels is x1. FLOAT_ONE (x3) defines no label.
  Microsoft's names (M6502, ASTIL, CBM4S79 where every build has the name) are then to go on the definitions. A
  vendor-only name (D3) goes in that vendor's alias file as a documented attachment to the qualified name, for example
  `PRNTFAC` for `Float::PrintFac` (AppleSoft), `SQR05`/`TENC`/`N0999`/`RMULC` ... (Commodore), and `MULLN2`/`GFDIV`,
  which M6502 gives only for PET builds.
- Alternative A: a shared `MsBasic.MathAliases.asm` (outside the macros) plus the vendor files, each old name an
  equate to the new name (`FADD = Float::AddPacked`). This works today, but the old names become real symbols: the
  editor gives no "historical name" hover and no quick fix.
- Alternative B: one documented alias per old name with a new SDK name. This adds about 250 names for no reader's
  benefit.
- Rows 1287 and 2273-2280 were drafted as DROP because their names would move into `Also:`. With Alternative A they
  stay as equates with their targets renamed; X5 has since made them scoped aliases (`AppleSoft::PrintFac`,
  `Commodore::*`).
- ASTIL spells FDIVT as `FIDVT`. Keep both, per "a name from a document is never dropped".

##### A-Q2. Is the math package a scope or a set of top-level entries?

- **Recommendation:** use one `.scope Float` from FADDH through ATNCON (Microsoft's math-package bounds). Open it,
  and continue it with `.scope Float continued`, in the composition files around the macro invocations
  (MsBasic.FloatingPoint/FloatArithmetic/.../Transcendental and Commodore.FloatingPoint), so the macros stay
  scope-free. Callers write `Float::AddPacked` or `.using Float`. Reasons:
  - AssemblyStyle's own example of a scope is "the entries of a floating-point package".
  - The code is an unusually dense web of shared tails, entered part way and jumped between. NORMAL's byte loop
    jumps over SetZero and AddMantissas into its bit loop. Several routines branch into another routine's `rts`.
  - Monitor log 18 keeps subsystem routines in their family even when programs call them.
  - Short member names (`Float::Round`, `Float::Negate`, `Float::Compare`) would otherwise need a prefix at top
    level anyway, and must not collide with the Monitor's top-level `Multiply`/`Divide`.
- Alternative: top-level entries for the ASTIL and M6502 documented names (Monitor log 9), with the internals as
  locals. That needs about 70 top-level names, all prefixed. It still leaves the cross-routine targets in A-Q4 without
  a scope to put them in.
- Placed outside Float, at top level: the integer conversions (AYINT family), ApplyRelation (DOREL), ReturnSignedWord
  and ReturnByte (GIVAYF, SNGFLT), and MinimumInteger. They sit elsewhere in ROM (arrays, the expression evaluator,
  after array multiplication). The vendor oddities placed inside the package region (BASIC 2's WAIT message, BASIC 4's
  checksum byte) are also top level. The Commodore composition closes and reopens Float around them.

##### A-Q3. Do the functions inside the package go in `Functions` or in `Float`?

SGN, ABS, INT, LOG, SQR, EXP, RND, COS, SIN, TAN and ATN lie inside the package, and FRE and POS lie in
SimpleFunctions. I followed the default: `Functions::Sgn`, `Functions::Int`, and so on. Consequences:

- `Functions` is opened many times inside the package, closing Float each time.
- Several fall-throughs cross the scope boundary:
  - Sgn into `Float::ConvertSignedByte`;
  - Log into `Float::MultiplyPacked`;
  - Sqr into `Float::RaiseArg`;
  - Cos into Sin;
  - Fre and Pos into `ReturnSignedWord` and `ReturnByte`.
- Package routines call functions: RaiseArg calls Functions::Int, Log and Exp, and Exp calls Functions::Int.
- **Recommendation:** keep the default (keyword names, one dispatch scope) and accept the pieces.
- Alternative: `Float::Sine`, `Float::Floor` ... inside the Float scope, with `Functions` holding only the non-math
  functions. This gives fewer scope pieces, but the function dispatch table then mixes two scopes.

##### A-Q4. How are labels written that another routine jumps into mid-routine?

The draft rule makes these a separate `.proc` or a scope-level label. I made a separate proc wherever the label
starts a piece with its own contract that others call. Examples: AddArg, AlignAndAdd, NormalizeSigned, SetZero,
ComplementMantissa, CompareAtPointer2, ConvertWord, AddExponent, AddScaledArgAndDouble (Commodore's TI$ path),
CopyArgToFacWithSign, EvaluateStoredPolynomial. Each is noted "Falls into".

The rest are mid-routine points: shared `rts` exits, a loop's entry, and the head of the shifter's low bytes. I wrote
them as `Proc::Label` entries (AssemblyStyle: "Code elsewhere reaches one as Proc::Label"):

- shared `rts` exits: ShiftInCarry::Done, IncrementMantissa::Done, MultiplyByte::Done,
  AddScaledArgAndDouble::Done, ToLongInteger::Done, ClearMantissa::Done, CopyFacToArgUnrounded::Done,
  EvaluateStoredPolynomial::Done, Negate::Done;
- the rest: AlignAndAdd::Combine, NormalizeBits::Test, NormalizeBits::CheckCarry, ShiftRight::ShiftLow,
  MultiplyByte::NonZero, GetSign::FromSignByte, GetSign::FromBit7, ReadNumber::NextExponentCharacter,
  Round::Increment, FormatFacAtOffset::ExtractDigits, PrintFac::ToPrintString, FacToInteger::FailUnlessEqual,
  Functions::Rnd::ToStoreFac, Functions::Sin::Reflect.

- **Recommendation:** accept these entries. Splitting each into its own proc produces procs of one `rts`, or splits
  loops across procs.
- Alternative: make them scope-level labels in Float, and give up procs for the tangled addition/normalize block
  (FADD5 through SHFTRT) and the sign/compare block.
- One proc does not start at its entry. NormalizeBits begins at NORM2, the loop body, but is entered at NORM1
  (`NormalizeBits::Test`). Its other option is to make NORM2 an unnamed-looking `NormalizeBits::ShiftLeft` with
  NORM1 the proc. Say which you prefer.
- ToOverflowError (GOOVER) is a jump-only routine shared by four routines. I named it with `To` as the rule does
  for locals, although it is a scope member.

##### A-Q5. Names for the arithmetic operations

M6502's convention: the plain entry takes a packed number at Y:A and unpacks it into Arg; the T entry takes Arg
already unpacked. The result is in Fac. Subtraction and division compute Arg - Fac and Arg / Fac.

- **Recommendation:**
  - `AddPacked`/`AddArg`;
  - `SubtractFromPacked`/`SubtractFromArg`;
  - `MultiplyPacked`/`MultiplyArg`;
  - `DividePacked`/`DivideArg`, plus `DivideArgByPacked` (FDIVF);
  - `RaiseArg` (FPWRT, Arg ^ Fac).
- Movement: `LoadFac` (MOVFM), `LoadArg` (CONUPK), `StoreFac` (MOVMF), `StoreFacInTemporary1/2`,
  `StoreFacInVariable`, `CopyFacToArg`/`CopyArgToFac`, `NormalizeResult` (MOVFR).
- Conversions: `ConvertSignedByte` (FLOAT), `ConvertSignedWord`, `ConvertWord`, `ConvertMantissa`. These are named
  "Convert" so that jump-only locals read `ToConvertSignedByte`.
- Alternatives:
  - `Add`/`AddUnpacked`. This is shorter, but plain `Multiply`/`Divide` inside Float would shadow the Monitor's
    top-level routines.
  - `FacPlusPacked`-style names. These are exact but read poorly in `jsr`.
- QINT is `ToLongInteger` (four-byte, rounded down). AYINT is the top-level `FacToInteger` (16-bit, range-checked).
  Alternative for QINT: `Float::Truncate`. That is wrong for negatives, which round down.

##### A-Q6. ZSTORD and WAIT

- In MACRO-10, ZSTORDO and ZSTORD are one six-character symbol. ZSTORD is WAIT's omitted-second-mask target: BASIC 2's
  hidden-message routine, or STORDO in every other build.
- **Recommendation:**
  - Drop AppleSoft's `ZSTORD = STORDO` equate (row 263) and pass B1's new name for STORDO to the WAIT macro. M6502's
    ZSTORDO goes in prose.
  - The Commodore routine (row 2281) is the top-level `WaitHiddenMessage`, with `Also: ZSTORD (M6502), STORD1 (HV2)`.
- Alternative: keep a vendor alias `ZSTORD` in AppleSoft's alias file.
- AppleSoft's `WAIT:` label (row 1392) sits at the same address as FNWAIT and only feeds AppleSoft's dispatch table.
  Fold it into B1's name for FNWAIT (expected `Statements::Wait`). AS82 gives WAIT only weakly, so add an `Also:`
  only if B1 confirms it.

##### A-Q7. ZERO: one name across two parts

ZERO (row 249: AS, P2, P4, P4R, three zero bytes inside Half) and B2's row 860 (P1, in VariableLookup) are the same
job. Both are the value LDZR returns for a variable that does not exist.

- **Recommendation:** use the top-level `ZeroValue` in both. Inside OutputTables the label then has to be emitted
  outside the Float scope: the composition closes Float for those bytes, or Float gets `Float::ZeroValue` with a
  top-level alias.
- I renamed ZEROFC from Zero to `Float::SetZero` so the names do not collide.
- Bug in a comment, to fix in conversion: MsBasic.VariableLookup's LDZR comment says AppleSoft places its zero bytes
  there. AppleSoft actually defines ZERO in FHALF: MsBasic.FloatOutput passes `OUTPUT_TABLES 1, TIME`.

##### A-Q8. Do the line-number printers belong in Float?

INPRT, LINPRT, PRNTFAC and STROU2 are emitted at the head of Microsoft's FOUT section, so I put them in Float:
`Float::PrintInLineNumber`, `Float::PrintDecimalAX` (named after the Monitor's PrintAX, which prints hex),
`Float::PrintFac`.

- **Recommendation:** keep them in Float.
- Alternative: make them top level, since LIST, error reports and Commodore's disk code call `PrintDecimalAX`. That
  costs a scope break inside DECIMAL_OUTPUT's emission.

##### A-Q9. Top-level names outside the package

- AYINT family: `EvaluateSubscript` (INTIDX), `FacToNonnegativeInteger` (POSINT), `FacToInteger` (AYINT).
- `ApplyRelation` (DOREL).
- `ReturnSignedWord` (GIVAYF) and `ReturnByte` (SNGFLT). Each sets ValueType numeric, making the value the
  expression's result.
- Alternatives:
  - `Operators::Relation` (DOREL), if B2 makes the operator handlers a scope.
  - `GiveSignedWord`/`GiveByte`. "Give" is Microsoft's verb, but it is opaque to a newcomer.

##### A-Q10. Switches and macro names

- REALIO, TIME, EXTIO and DISKO: KEEP. They are predefined by C# and the tests.
- Microsoft's INTPRC, ADDPRC and LNGERR are historical, so they are renamed with `Also:`:
  - `INTEGER_VARIABLES`;
  - `ADDITIONAL_PRECISION`, which code also uses as a byte count, as in `8+ADDPRC`;
  - `LONG_ERRORS`.
- The SDK's macros become PascalCase. Abbreviations are expanded to full words (D4): `ExponentialConstants`,
  `SineConstants`, `ArctangentRoutine`, `TrigonometricRoutines`, `LogarithmRoutine`, `SignAndIntegerRoutines`.
  Alternative: only change the case (`ExpConstants`, `AtnRoutine`).
- The parameter `limitAt120` is kept, but it reads oddly: value 1 selects the exponent test against 12. Consider
  `earlyExponentLimit`, which matches Commodore's EARLY_FIN_LIMIT.

#### Glossary names I disagree with (I used them anyway)

- **OLDOV** (`FunctionJumpHigh`, an alias of JMPER+2). In the math package this byte holds a guard byte:
  - AddArg saves FacExtension there, and AlignAndAdd/AddMantissas use it as the unshifted operand's guard;
  - Functions::Exp keeps its rounding byte there.

  Recommend a scoped alias in Float, for example `Float::SavedExtension = FunctionJumpHigh`.
- **DECCNT** (`DigitsBeforePoint`). FormatFac uses it that way, but ReadNumber counts the digits *after* the point in
  it. Recommend a scoped alias in ReadNumber (`FractionDigits`).
- **INTEGR** (`SmallInteger`, "QINT's one-byte integer"). The byte is written by INT (Functions::Int), not by QINT.
  RaiseArg (parity) and Exp (power of two) read it. The name is fine; the note should be corrected.
- I checked and confirmed: DPTFLG is "decimal point seen" (a second point sets bit 6 and ends the number); TENEXP is
  the decimal exponent (in ReadNumber, and FormatFac's printed exponent, 0 for fixed point); EXPSGN is the exponent's
  sign; SGNFLG is the input sign ($FF for minus).
- BITS, the shifter's fill byte ($FF while ToLongInteger shifts a negative), is not in the glossary. The workspace
  part should name it, for example `ShiftFill`.

#### Names chosen to match other parts

- `ZeroValue` matches B2 row 860 (P1's ZERO).
- These names were chosen before the target parts settle theirs; adjust them to match:
  - `Functions::Log::ToIllegalQuantity` assumes FCERR's new name.
  - `PrintFac::ToPrintString` assumes STROUT's new name.
  - STORDO and ZERRTS (B1, MemoryAccess) are jump targets here. AlignAndAdd's `beq ZERRTS` returns through WAIT's
    `rts`.
- `Float::ReadNumber` follows DOS's `Scanner::ReadNumber` wording.
- `Float::PrintDecimalAX` follows the Monitor's `PrintAX`.

#### Found in the code (document, do not fix)

- ArithmeticCore says MLTPL1 "includes the implicit high bit of the final byte". In fact `ora #$80` after `lsr` is
  the marker bit that ends the eight-bit loop, set for every nonzero multiplier byte. MLTPL1 is entered directly only
  for FACHO, to skip the zero test.
- SIMPLE_FUNCTIONS' `setCarry` changes bytes only. ReturnSignedWord recomputes carry in ConvertSignedWord (`rol`).
- The quirks the sources already document stand:
  - MinimumInteger's fifth byte is a JSR opcode;
  - Compare's last-byte wrap;
  - FRE turns negative above 32767.
- Unreferenced labels kept as locals because a document names them: FADD3, SHFTR7, FOUTCP, MOVML, FOUTCM, FPWRRT,
  MULLN2, GPOLYX, GFDIV.
- FOUT13 (AppleSoft only) has no document name, so it has no `Also:`. HV2's LE082 is an address name and is not cited.

### B1: The shared program and statement modules
This part covers 256 rows: the shared modules CharacterReader, CommandCore, For, LineNumber, LineSearch, Lister,
MemoryAccess, MemoryManagement, Next, OperatorTable, Print, ProgramReset, ProgramTransfers, StatementFlow and
UserFunctions. I read every routine, how each vendor root expands its macros (AppleSoft.*.asm, Basic1/2/4.asm,
Commodore.CommandInput.asm), and every reference to each label in the native sources. The MACRO-10 overlays
(`applesoft.mac`, `Basic1.mac`, `Basic4.mac`) also use many of these names. I did not count those uses when deciding
what is top level, because they are written in the historical dialect.

#### Cross-cutting

**B1-Q1. Shared exits and mid-routine entries.** Microsoft often branches into another routine's `rts`, or into the
middle of another routine:

- FLNRTS: New, List.
- STKRTS: List, Clear.
- CONTRT: Stop, Null, BASIC 1's Clear and its dispatcher.
- ISCRTS: the dispatcher.
- ONGRTS: ReadLineNumber.
- ZERRTS: the addition core.
- REMRTS: FindLineEnd.
- GORTS: Return.

Entries of the same kind are STPEND, ENDCON, RESFIN, PRINTC, BLTUC, FNDLNC, RUNC2, USERR, SNERR2, SNERR3, ERRGUF and
ERRGO5. The draft rules say such a label "stays a separate `.proc` or a scope-level label". AssemblyStyle allows reaching a
label as `Proc::Label`.

- *Recommendation:* make them entries of the routine they sit in: `FindLine::Done`, `Statements::Cont::Done`,
  `Statements::On::RequireGoto`. Note each in the routine's `;;` block (for example "Entry: Done = ..."). A one-byte
  `.proc` for every shared `rts` would fragment the code, and these entries do not keep weaker contracts of their own.
- I made a separate `.proc` only where the code before the label is a different statement, or where a dispatch target
  must start at that address:
  - `Statements::StopOrEnd` (STOPC)
  - `Statements::IfTrue` (DOCOND)
  - `Statements::PrintStringItem` and `Statements::PrintNextItem` (STRDON and NEWCHR, which come before PRINT)
  - `Statements::PopFinish` (REMER1)
  - `ReportMessage` (ERRFIN)
  - `AdvanceTextPointer` (ADDON)
- *Alternative:* follow the draft rules literally and turn every one of these into scope-level labels in `Statements`, or
  into one-instruction procs.

**B1-Q2. Structs: ForFrame (asked), and four more.**

- **`ForFrame`**: 18 bytes (FORSIZ = 2*ADDPRC+16). It sits on the 6502 stack, and its fields are read as
  `$0101+field,x` after FindForFrame returns X:

  | Offset | Field | Size | Contents |
  |---|---|---|---|
  | 0 | `TOKEN` | .byte | TOKEN_FOR |
  | 1 | `VARIABLE` | .word | pointer to the loop variable |
  | 3 | `STEP` | 5 bytes | packed step |
  | 8 | `STEP_SIGN` | .byte | |
  | 9 | `LIMIT` | 5 bytes | packed limit |
  | 14 | `LINE` | .word | line of the FOR |
  | 16 | `TEXT_POINTER_HIGH` | .byte | |
  | 17 | `TEXT_POINTER` | .byte | low byte |

  The text pointer is stored high byte first: FOR pushes the low byte first, so the low byte lands at the higher
  address. The struct must show that order, rather than one `.word`. NEXT's `$0109,x`, `$010F,x`, `$0110,x`,
  `$0111,x` and `$0112,x` become `Stack + 1 + ForFrame::STEP_SIGN` and so on. Its `adc #$04 ... adc #$06` and the
  `inx` runs reach STEP and LIMIT. The `adc #$11` with carry (18) becomes `FOR_FRAME_SIZE - 1`.
  - *Recommendation:* add the struct, with `FOR_FRAME_SIZE = ForFrame .sizeof` and `Also: FORSIZ (M6502)`. A
    `Stack = $0100` location may already exist in the workspace part.
- **`GosubFrame`**: 5 bytes. `TOKEN` (TOKEN_GOSUB), `LINE` .word, `TEXT_POINTER` .word, little-endian. GOSUB asks
  CheckStack for 3 two-byte entries.
- **`OperatorEntry`**: 3 bytes. `PRECEDENCE` .byte and `HANDLER` .word, where HANDLER is the address minus 1.
  ExpressionCore reads `OPTAB+1,y` and `OPTAB+2,y`. Name the precedences too: PRECEDENCE_ADD = $79,
  PRECEDENCE_MULTIPLY = $7B, PRECEDENCE_POWER = $7D/$7F, PRECEDENCE_AND = $50, PRECEDENCE_OR = $46,
  PRECEDENCE_RELATION = $64, PRECEDENCE_UNARY = $7F in AppleSoft ($7D on the PET, where negation shares power's level), PRECEDENCE_NOT = $5A. ExpressionCore's `cmp #$64` is the
  relation entry's precedence.
- **`FunctionDefinition`**: the value of a DEF FN variable. `FORMULA` .word (the text pointer), `ARGUMENT` .word (the
  argument variable's value pointer), and a fifth byte that DEF also stores (the character after `=`). FNDOER reads
  offsets 0 to 3.
- **`ProgramLine`**: `LINK` .word, `NUMBER` .word, then the text. FindLine, the lister and LinkProgram use offsets
  1 to 3. This one probably belongs to the workspace part (D).

**B1-Q3. The character reader.** INITAT is code that runs only as its page-zero copy.

- *Recommendation:* `CharacterReaderTemplate` (kind data), with locals `GetCurrent` (CHZGOT) and `Done` (CHZRTS).
  The page-zero names stay the glossary's GetNextCharacter and GetCurrentCharacter.
- The glossary leaves QNUM to this part: `QNUM = GetCurrentCharacter + 7`. That is the entry that classifies A without
  reading, and it skips the colon test.
  - *Recommendation:* `ClassifyCharacter`.
  - CHRRTS (AppleSoft, $C8) would become `CharacterReaderReturn`.
- *Alternative:* keep the template's locals as aliases pointing at the page-zero names.
- Hoffmann-Vetter spells CHZGOT and CHZRTS as CHDGOT and CHDRTS. They go in `Also:` for the PET builds only.

**B1-Q4. The lister is one proc.** In every build the LIST code is contiguous: ListRange, then ListLines, then
(AppleSoft only) ListNextTableByte, then ListTokens. Code branches back and forth between those pieces (PLOOP,
PRIT4, QPLOP), and no native code outside reaches any of its labels.

- *Recommendation:* one `.proc Statements::List`, opened in the vendor file before ListRange and closed after
  ListTokens. All 30 labels become its locals. GRODY1 becomes `List::NextTableByte`, a local subroutine called by jsr.
- *Alternative:* a scope `Lister` with procs `ListLines` and `ExpandToken`. That needs scope-level labels for PLOOP,
  PRIT4 and QPLOP, for little gain.

**B1-Q5. Range or block.** The DOS precedent P9 says "Range, not block, for multi-byte transfers". I named BLTU
`MoveRangeUp` (with `MoveRangeUp::Unchecked` for BLTUC). The glossary's notes say "block move".

- *Recommendation:* MoveRangeUp.
- *Alternative:* `MoveBlockUp`, if P9 was meant for DOS's transfer requests only.

**B1-Q6. A bug to document (not fix).** When ReadLineNumber (LINGET) finds the running high byte at $19 or more, it
branches to ON's `SNERR3` (`Statements::On::RequireGoto`), not to a syntax error. That code compares A with
TOKEN_GOTO, and A is that high byte.

- A number whose high byte equals TOKEN_GOTO, followed by one more digit, falls into ON's skipping loop with a stale
  selector and the GOTO token. In AppleSoft (TOKEN_GOTO = $AB) these are 43776 to 44031; in the PET builds ($89),
  35072 to 35327.
- *Recommendation:* document the bug on both routines, with a link between them.

Other bugs and quirks the code shows, all already described in the current comments, which I checked:

- FindForFrame's wrap leaves zero set.
- CheckFreeMemory loads TEMPF1 last but never pushes it.
- CheckStack does not reject counts above $7F.
- The early stack reset (`earlyStack`) has an interrupt window.
- The RETURN variant that sets the low byte can still match a FOR variable.
- FN's early check rejects an argument variable at an address ending in $00.

**B1-Q7. Parameters that only define a label.**

- `newAlias` only defines AppleSoft's NEW at SCRATH's address. Under D3, NEW should be an `Also:` of
  `Statements::New` in AppleSoft's alias file.
- `runLabel` only defines RUN1, which nothing references and no document names.
- *Recommendation:* DROP both parameters (and RUN1). This changes the invocations, not the bytes.
- *Alternative:* KEEP them, and make NEW a scoped alias.
- AppleSoft's own `ON:` label (ONGOTO's address) and `POP:` (RETURN's address) are part C's. They become
  `Also: ON` and `Statements::Pop` in AppleSoft.

**B1-Q8. Spelling of the statement names.** The draft's own examples (`Statements::OnErr`) and DOS's `Commands::PrNumber`
take the keyword as the name, so I wrote Cont, Def, Rem, Fn, Gosub and Goto.

- *Recommendation:* `Gosub` and `Goto` (one word each, as programmers write them).
- *Alternative:* `GoSub` and `GoTo`, split at the word boundary the way OnErr is.
- *Alternative:* full words such as `Statements::Continue` (CONT). I advise against these: the keyword is what a
  reader searches for.

**B1-Q9. Scopes inside the shared macros.** Several macros emit both a `Statements` handler and top-level routines.
NEXT_ENTRIES, for example, emits Next and then EvaluateNumber and RequireType.

- *Recommendation:* each macro opens and closes `.scope Statements continued` (or `Functions`) around the handlers it
  emits, so the vendor files need no scope bookkeeping around the macros.
- *Alternative:* the vendor files wrap the macro calls in the scope, and the macro moves its top-level routines to the
  start or end.

**B1-Q10. Macro names.** I converted the case and improved names only where needed:

- `ErrorFinish` (dropping the redundant BASIC_ prefix), and likewise `DeleteOldLine`, `LinkLine`, `TokenStore`.
- `AddressConversion` (MEMORY_ACCESS_ADDRESS).
- `PeekFunction`, `PokeStatement` and `WaitStatement` (MEMORY_ACCESS_*).
- `OperatorEntries` (OPERATOR_TABLE). Calling it OperatorTable would give it the same name as the table.
- `PrintItems` (PRINT_CORE).
- `NextStatement` (NEXT_ENTRIES; settled as `NextEntries`, K1). It reads close to the parameter `nextStatement`; `NextAndTypeChecks` is the
  alternative.

Every macro parameter is already descriptive camelCase, and I wrote KEEP for each. Two are DROPs (B1-Q7).
`countedStack` is the SDK name the draft rules lists.

**B1-Q11. Tests use the old names.** BasicShared*Tests and PetNativeEquatesTests look up labels such as TYPERR, MAIN1,
GRODY1 and REMER1 in the symbol table, and the macros by name. The integration must update them, unless symbol
lookups resolve `Also:` names. Locals such as `ReportError::AddErrorSuffix` (TYPERR) would also need a qualified
lookup.

#### Per module

- **CommandCore.**
  - TYPERR, MAIN1, QDECT1, MLOOP, CZLOOP, GETBPT through STRNG are locals of part C's ERROR, MAIN, LNKPRG and
    CRUNCH. I wrote them as `ReportError::`, `CommandLoop::`, `LinkProgram::` and `Tokenize::`, and those names must
    follow part C's choices.
  - I named CZLOOP `LinkProgram::ScanLine` so that it would not shadow `FindLineEnd` (REMN).
- **MemoryAccess.**
  - GETNUM is `ReadAddressAndByte`. DOS's GETNUM is `Scanner::ParseNumber`, a different thing; clashes across modules
    are allowed.
  - COMBYT is `ReadCommaAndByte`, with ASTIL's COMBYTE in `Also:`. It should match whatever B2 names GETBYT
    (I assumed something like ReadByte, so I named PEEK's local `Fetch` rather than ReadByte).
- **Next.**
  - GETFOR is `Statements::Next::WithVariable`, not FindVariable, so that it does not shadow what PTRGET will likely
    be called.
  - LOOPDN's `jsr GETFOR` is deliberate. The return address it pushes stands in for the statement loop's return,
    which FindForFrame skips. It is never returned to, so NEXT does not really fall into EvaluateNumber. The comment
    should say so.
- **Print.**
  - LINCHK (PET, `Statements::Print::NumberItem`) is unreferenced but documented, so I kept it as a local.
  - AppleSoft's own LINCHK in AppleSoft.Print.asm is a different label in the comma-zone code. It needs a different
    new name; that is part E's.
- **ProgramReset.**
  - RUNC is `ResetProgramState`. It rewinds TextPointer and falls into CLEAR's reset. RUN, the line editor and LOAD
    all use it, so a name that says "run" would mislead.
  - In BASIC 1 it falls straight into ClearVariables. In the other builds it falls into `Statements::Clear`, whose
    `bne` sees the zero that `runSetsZero` supplies.
- **ProgramTransfers.** STOP's carry comes from CHRGET (set for a non-digit) or from ISCNTC's `cmp #3`. ISCNTC falls
  into STOP in both vendors.
- **StatementFlow.**
  - DATAN and REMN are top-level `FindStatementEnd` and `FindLineEnd`. FOR, DATA, READ, GOTO, REM and AppleSoft's
    commands all use them.
  - Return falls into Data to skip the rest of its statement.

#### Glossary names I disagree with (used as given)

- **LSTPNT = ListString.** The lister uses LSTPNT only to save and restore Y, the offset in the current line
  (`sty LSTPNT`, `ldy LSTPNT`). It never points at a keyword. Suggest `ListOffset`, as a scoped alias in
  Statements::List.
- **LOWTR = SourceStart.** Its note ("FindLine's result") is right, but FindLine and its callers (List, Goto, the line
  editor) use it as "the line found". Suggest a scoped alias `FoundLine` in FindLine's family, keeping SourceStart for
  MoveRangeUp.
- **DEFPNT = FunctionPointer.** In FN it also holds the argument variable's address while the old value is restored
  (`PopToFunctionPointer`). The name is acceptable, but its comment should say both uses.
- "Block move" in the notes for LOWTR, HIGHTR, LOWDS and HIGHDS: see B1-Q5.

#### Names matched to other parts (to align at merge)

- Part C:
  - `ReportError` (ERROR)
  - `CommandLoop` (MAIN)
  - `LinkProgram` (LNKPRG)
  - `Tokenize` (CRUNCH)
  - GONE3, in `IfTrue::ToExecuteStatement`
  - READY and NEWSTT, named in reasons only
- Part B2: FCERR, in `Null::ToIllegalQuantity`; GETBYT, PTRGET and FRMEVL, named in reasons only.
- Part E: AppleSoft's NEW, ON and POP aliases (B1-Q7).
- The glossary: everything I cite in the workspace (TextPointer, ProgramStart, CurrentLine, StoppedText, PokeAddress,
  WaitXorMask, FunctionPointer, and so on).

### B2: The shared expression, variable and string modules
Part B2 covers the shared modules ArrayMultiplication, Arrays, Assignment, Dim, ExpressionCore, OperandEvaluation,
VariableInput, VariableLookup and the string package (StringStorage, .Classic, .Linked, StringConcatenation,
StringConversion, StringFunctions, StringGarbageCollection, StringOutput). The table has 332 rows. Every routine
was read in the macro source, and its cross-module references were checked by grep over the shared, AppleSoft and
Commodore files. References from the legacy `.mac` overlays were not counted as references.

#### Cross-cutting

**B2-Q1. The string package is a scope `Strings`.** It holds the allocation front ends (AllocateForFac, Allocate,
ReserveSpace), the literal scanner (FromText, FromTextUntil, FromNumberBuffer), PushTemporary, CollectGarbage,
Concatenate, the movers (CopyString, CopyFrom, CopyBytes) and the release routines (ReleaseFacString, ReleaseFac,
ReleaseDescriptor, ReleaseTemporary). In the ROM these routines sit together, from TIMSTR to FRETMS, so the scope
opens once in each build (Str, in Functions, comes just before it). The ASTIL entries are reached as
`Strings::FromText` and so on.
Recommendation: the scope, following Monitor decision 18 (a subsystem's routines stay in their family even when
programs call them). Alternative: top-level names (`MakeStringLiteral`, `ReleaseTemporaryString` ...), because
nearly every module calls FromText, ReleaseFac and PushTemporary.

**B2-Q2. The variable and array internals are a scope `Variables`.** It holds NotFound, ReturnZero,
CheckReservedName, Create, ValueAddress, ElementsStart, ChooseArrayLookup, FindArray, ArrayFound, ArrayMissing,
CreateArray, ElementAddress, MultiplyByBound and MultiplyUnsigned. FindVariable (PTRGET) stays top level because it
is an ASTIL entry. The scope has to come in pieces, because ISLETC (part B1), the integer conversion (part A), the
zero bytes and the two error entries all sit between its routines.
Recommendation: the scope, as `.scope Variables continued` pieces. Alternatives: top-level names
(`VariableNotFound`, `CreateVariable`, `FindArray` ...), which avoids the pieces; or two scopes, `Variables` and
`Arrays`.

**B2-Q3. The expression evaluator's structure.** FRMEVL's loop has PUSHF1, PUSHF and FORPSH in its middle, and its
tail (QOP to UNPRTS) is reached by branches from before them. So I made `EvaluateExpression` a single `.proc`, with
labeled entries for what other code enters: `NextOperator` (from Concatenate), `Prefix` (unary minus and NOT),
`PushSignedFac` and `PushFac` (from FOR). In OperandEvaluation the code is cut into small top-level procs at each
point another routine branches to: EvaluateOperand, ReadQuotedString, EvaluateTokenOperand,
EvaluateFunctionOperand, ApplyMinus and ApplyPrefixOperator.
Recommendation: as drafted. Alternative: a scope `Expression` with scope-level labels for the shared tail and the
push helpers as their own procs. FOR would then call `Expression::PushFac`, and FRMEVL would have to become
`Expression::Evaluate` or stay top level outside the scope.

**B2-Q4. The logical operators are a scope `Operators`** (`Operators::Not`, `Operators::Or`, `Operators::And`),
following the pattern of Statements and Functions. Part A's relational operator (DOREL) should join it. There is
one case where the builds differ. On the PET, ANDOP is the AND entry. In AppleSoft's Boolean version, the ANDOP
label sits at OR's entry and AND is OROP1. So in AS, ANDOP becomes `Also:` of `Operators::Or`, and OROP1 takes
`Operators::And`, which keeps one name for one job.
Recommendation: the scope, with that per-build placement of ANDOP. Alternative: top-level `OrOperator`,
`AndOperator` and `NotOperator`.

**B2-Q5. Error entries are top-level `<Message>Error` routines**: SyntaxError (SNERR), IllegalQuantityError (FCERR)
and BadSubscriptError (BSERR). Both vendors and nearly every module jump to them. The jump-on stubs are
`To<Target>` locals, or GOFUC as `Functions::ToIllegalQuantityError`, which MemoryAccess also uses. These names
depend on the names other parts give ERROR, OMERR, FIN, SNGFLT and MOVVF. Where I needed one, I used a guess
(ToError, ToOutOfMemoryError, ToParseNumber, Len::ToFloat, ToPackFac) and marked it in the note column.
Recommendation: settle one rule for all the parts. Either top-level `XxxError` (my choice), or a DOS-style
`Errors::Syntax` scope.

**B2-Q6. Borrowed RTS instructions and shared stubs.** Several labels are entered from other routines only because they
are a nearby RTS or JMP: DIMRTS (ERRDIR in UserFunctions branches to it), FRERTS (P4's ReleaseDescriptor), ERRGO2
(both allocators), ERRGO3 (ArrayFound), OMERR1 (CreateArray and the multiplier), and StringOutput's branch to
Print's PRTRTS. I wrote each as an `entry` of the routine it is in (for example `ElementAddress::Done`).
Recommendation: entries, with a note at the user. Alternative: end the proc before the instruction and make it a
scope-level label.

**B2-Q7. Statements that are not keywords.** DIM3 sits before DIM's entry, and COPSTR (LET's string path) sits after
StoreNumber. Each needs its own proc: `Statements::DimNextArray` and `Statements::LetString`.
Recommendation: keep them in Statements, next to their handlers. Alternative: top-level `DimNextArray` and
`LetString`.

**B2-Q8. Apple's old names that clash in AppleSoft builds.** Apple's COPY (The Apple Orchard) names COPYZC
(StoreDescriptor), and Apple's GARBAG names GARBA2 (CollectGarbage). Microsoft's COPY (`StoreString::CopyCharacters`)
and GARBAG (`ReserveSpace::Collect`) are also assembled in AS.
Recommendation: one old name per definition. Microsoft's names keep `Also:`, and Apple's go in prose on
StoreDescriptor and CollectGarbage, as DOS decision X8 handled RD1-RD5. Alternative: Apple's names win in AS,
because D3 says a vendor's name resolves in that vendor's builds, and Microsoft's go in prose there.

**B2-Q9. Under D5, which variants become their own procs.** Each of these keeps a weaker contract and is written as an
`.if` in the middle of a routine:
- P1's ElementAddress (saveOffsetHigh = 0), which keeps BASIC 1's array bug;
- the PET's NotFound, which compares only the low byte of the return address;
- AS, P1 and P2's PushSignedFac, which does not carry the return address across a page;
- P1's SliceArguments, whose indirect return wraps within its page;
- the AS and P1 collector, which stops early at a temporary in page zero.

Recommendation: whole procs per variant for these five only. The other `.if`s (register choice, extra name checks)
stay inside a routine. Alternative: keep every `.if` as it is, and document the weaker contract in that variant's
contract text.

**B2-Q10. Constants this part needs** (none of them are definitions today):
- InputMode values: `INPUT_MODE_INPUT` = $00, `INPUT_MODE_GET` = $40, `INPUT_MODE_READ` = $98. READ's $98 is the
  TYA opcode that READ's `.byte $A9` turns into an operand, so it needs an `.assert`.
- `RELATIONAL_PRECEDENCE` = $64, tested in EvaluateExpression.
- The type bits in a variable name: bit 7 of the first byte and of the second byte.
- The element sizes: `FLOAT_SIZE` = 5, `INTEGER_SIZE` = 2 and `DESCRIPTOR_SIZE` (glossary).
- `DEFAULT_BOUND` = 11.

Recommendation: define these where they are used, or in the workspace part's shared file.

**B2-Q11. Apple's fixed jumps at $E000 inside FindVariable.** These are three JMP INIT/MAIN instructions and the model
byte, under `fixedVectors`. They have no labels in my part. They are entry points programs call ($E000 cold start,
$E003 warm start).
Recommendation: part D or E should give them top-level labels with `.assert`s (for example `BasicColdStart` and
`BasicWarmStart`, following MonitorEntries), even though the bytes sit inside FindVariable. I named the code after
them `FindVariable::AfterVectors`.

**B2-Q12. The zero an absent variable reads.** P1 defines ZERO here (row 860). P2 and P4 define it inside FHALF (part
A). AS defines both its own SIMZER here (row 859) and ZERO in FloatConstants. ZERO has the same job in every build
(the PET's TI$ assignment also tests for it), so row 860 must take part A's name for ZERO. I wrote `ZeroBytes` as a
placeholder. SIMZER is a second definition in AS, so it needs its own name: `ZeroVariable`. After the rename,
`useSimzer` only chooses which old name goes in `Also:`.
Recommendation: part A uses `ZeroBytes` for ZERO; SIMZER is `ZeroVariable`; `useSimzer` is kept.

#### Structs

- `Variable` (7 bytes, `VARIABLE_SIZE`): `NAME` (two bytes; bit 7 of each carries the type: both set for an
  integer, the second for a string, the first for a DEF FN), then `VALUE` (5 bytes). The value is a packed float,
  an integer stored high byte first, a StringDescriptor, or DEF FN's pointers. The 7s in Create, FindVariable and
  the collector's scalar step (`6 + ADDPRC`) become `.sizeof`.
- `ArrayHeader` (5 bytes, `ARRAY_HEADER_SIZE`): `NAME` (2), `LENGTH` (2, low byte first, the whole array's size),
  `DIMENSIONS` (1), followed by one two-byte bound per dimension, high byte first, each the largest index plus one.
  This covers the offsets `ldy #$02`, `ldy #$04` and `asl a; adc #$05` in CreateArray, ArrayFound, ElementsStart
  and the collector.
- `StringDescriptor` (3 bytes, `DESCRIPTOR_SIZE`): `LENGTH`, `ADDRESS` (2). This covers the `ldy #$02` tests in
  StoreString and CollectGarbage. The temporary stack is `TEMPORARY_COUNT` of these.
- BASIC 4's string link (2 bytes after each nonempty string): the descriptor's address, or the length and then $FF
  for garbage. It is probably part F's, but ReserveSpace (Linked), ReleaseDescriptor and Create's back-link
  adjustment write it.

Recommendation: the three structs above, in the workspace part's shared file.

#### Glossary names I disagree with, or that need scoped aliases

- **SUBFLG `SubscriptsAllowed` is the wrong way round.** A nonzero value is ORed into the next character, so `(`
  no longer matches: nonzero means subscripts are not allowed. Bit 6 is also AS's existing-array mode. I suggest
  `SubscriptMode` or `NoSubscripts`. I used the glossary name anyway.
- **GRBTOP `CollectorTop`** holds the address of the best string found so far in the pass, and GRBPNT
  (`CollectorPointer`) holds its descriptor. I suggest `CandidateString` and `CandidateDescriptor` as the
  collector's scoped aliases.
- **SIZE `FunctionJumpTarget`**: the collector uses this byte as the chosen descriptor's step, then as its offset.
  It needs a scoped alias in CollectGarbage, for example `CandidateStep`. PREAM (SliceArguments) uses JMPER+1/+2 to
  hold the dispatcher's return address.
- **DECCNT `DigitsBeforePoint`**: MultiplyUnsigned uses it as its 16-step bit counter, so it needs a scoped alias
  (`BitCount`).
- **COUNT `Counter` and INTEGR `SmallInteger`**: the PET's OR and AND use COUNT as a complement mask ($FF or $00)
  and INTEGR/+1 as a 16-bit work word. They need scoped aliases in `Operators::And` (`ComplementMask`,
  `FirstOperand`).
- **CURTOL `LinearIndex`**: CreateArray also uses it for the element size and then the running size. It needs an
  alias there.
- **STRNG2 `SecondStringPointer`**: FromTextUntil leaves the end of the scanned text in it, and VAL saves
  TextPointer in it. The name fits both uses; SetTextPointer's contract should say which.

#### Names chosen to match another part

- Row 860, `ZeroBytes`: must equal part A's name for ZERO (B2-Q12).
- `StoreDescriptor` (COPYZC): P4's COPYZC is in Commodore.StringAssignment's LINKED_STRING_STORE (part F), and it
  takes the same name. Commodore's COPYC alias points at it.
- `Strings::CollectGarbage` (GARBA2): P4's linked collector (part F) should take the same name. Its locals should
  also follow mine where they do the same work: NextPass, NextArray, ReadArray, ScanElements, CheckElement,
  Advance.
- `Variables::Create`'s P4 back-link locals (ARYVA2 ... ARYDON) reuse CollectGarbage's local names where the step
  is the same (NextArray, CheckArraysEnd, ReadArray, ScanElements, CheckElement, Advance).
- The guessed "To + target" names that wait on other parts' names: FIN (`EvaluateOperand::ToParseNumber`,
  `AssignVariableList::ConvertNumber`), SNGFLT (`Len::ToFloat`), MOVVF (`StoreNumber::ToPackFac`), ERROR
  (`IllegalQuantityError::ToError`, `PushTemporary::ToError`) and OMERR (`ElementAddress::ToOutOfMemoryError`).
- Vendor names my reasons rely on: ISVRET and ISVAR (part C, the target of LoadNumericVariable and the
  NotFound test), TRMNOK and SNERR6 (part C), and ERRDIR (part B1, which borrows `ElementAddress::Done`).
- The glossary names are used throughout: TextPointer, AssignedVariable, NewDescriptor, NewString, StringsBottom,
  ArraysStart, ArraysEnd, SourceStart, Pointer1, LinearIndex, ArrayIndex, CollectorStep, InputMode, and the rest.

#### Per-module notes (bugs documented in the code, not fixed)

- Arrays: when the next array's address wraps, FindArray::NextArray falls into BAD SUBSCRIPT (unreachable in
  practice). P1 (saveOffsetHigh = 0) keeps the array-offset bug (B2-Q9).
- VariableLookup: the PET's NotFound compares only the return address's low byte, so another caller with that low
  byte also gets the zero. FindVariable::Advance would fall into ISLETC if the table wrapped past $FFFF.
- StringStorage.Classic: a zero-length request that fails the room check collects once, then falls out of the
  macro into CollectGarbage a second time, and returns without allocating.
- StringFunctions: if FIN reports an error, VAL leaves the byte after the string as zero and does not restore
  TextPointer. P1's indirect return from SliceArguments wraps within its page.
- ExpressionCore: AS, P1 and P2's PushSignedFac increments only the low byte of its return address.
- StringConversion: FromNumberBuffer's BEQ to FromText depends on `>LOFBUF = 0` (the source asserts it).
- STRNA3 and SCALAR_SEARCH are one address in AS: both rows map to `FindVariable::SearchScalars`. STRNA3 has no
  document, so it gets no `Also:`. SCALAR_SEARCH is the SDK's own label and is renamed to the style.
- Macro VARIABLE_NAME becomes `VariableSearch`, so that it does not read as the glossary's location VariableName.
  Every other macro becomes the PascalCase of its name, and every macro parameter is KEEP: they are the SDK's own
  camelCase names, none of them is in the C#-predefined list, and none breaks the style.

### C: The vendors' interpreter files
Covers AppleSoft.ErrorAndInput / Commodore.CommandInput, AppleSoft.ControlFlow / Commodore.StatementDispatch,
AppleSoft.Print / Commodore.ChannelPrint, AppleSoft.InputOutput / Commodore.ChannelInput, AppleSoft.Expressions /
Commodore.VariableEvaluation, both Initialization files, both DispatchTables files and both InterpreterAliases files.
416 rows. Every routine named in both vendors' files has one name for both (checked by script). The places where
one old name gets two new names are listed under "Same old name, different job".

#### Cross-cutting

**C-Q1. The debug hosts look up old names.** `Retrocore.Debug/BasicRom.cs`, `PetDebugTarget.Basic.cs` and
`Apple2DebugTarget.cs` call `symbols.TryGetValue("NEWSTT" / "GONE" / "ERROR" / "MAIN")`.
- Recommend: before the conversion, check that the symbol table resolves `Also:` names. If it does not, change
  the C# to the new names (NextStatement, ExecuteStatement, ReportError, CommandLoop) in the same change.
- Alternative: keep those four old names as plain labels. That breaks D4.

**C-Q2. READY vs MAIN.** On the PET, READY prints `READY.` and falls into MAIN. In AppleSoft the two labels share an
address, because Apple prints no READY message.
- Recommend: `ReadyForCommand` in both vendors. On the PET it is its own routine. In AppleSoft it is a second label
  on `CommandLoop`, kept because the shared ERRFIN (`beq READY`) and ProgramTransfers name it.
- Alternative: point the shared code at a per-build name and drop AppleSoft's label.

**C-Q3. Labels that other routines branch into, in the middle of a routine.** PRINT's tail and the trampolines that
only jump to SNERR show this:
- `ContinuePrint` (NOTABR) sits between PrintSpaces' test and its loop body. Shared PRINT, PrintComma and
  PrintTabOrSpace all branch to it. I made it a top-level entry label, not a `.proc`.
- SNERR1 → `CheckStatementSeparator::ToSyntaxError` and SNERR4 → `HandleBadInput::ToSyntaxError` are entries that
  another routine also branches to, for range. In BASIC 1, SNERR1 lies inside NextStatement, so it would be written
  `NextStatement::ToSyntaxError` there. One old name then gets two scoped names, one per build.
- AppleSoft II+/IIe Print: LINCHK ($DB11) and TABER ($DB19) fall inside instructions (the overlapping
  `.byte` block), and nothing uses them. Recommend dropping them in those builds and giving their jobs' names to
  COMPR1 (`PrintComma::NextZone`) and LINCH1 (`PrintTabOrSpace`, the entry PRINT_CORE is given). Each row then
  holds a per-build name. Alternative: keep them as unreferenced locals with `Also:`. They would mislead a reader.
- Alternative for all of these: open a `.scope Print` family scope (Comma, TabOrSpace, Spaces, Continue,
  Character ...). Scope-level labels would remove the entry-inside-proc problem. I did not, because shared code
  names CRDO, OUTDO and the rest as top-level entry points.

**C-Q4. Entries split by a vendor's patch area.** BASIC 4's ISVAR is a trampoline (F part) to ISVAR1.
- Recommend: `EvaluateVariable` stays the name the shared evaluator branches to in every build (the trampoline
  in BASIC 4), and ISVAR1 becomes `EvaluateVariableBody`. ISVRET is `LoadVariableValue`, a top-level routine,
  because the shared VariableLookup compares a return address with `LoadVariableValue-1` in every build.
- Alternative: `EvaluateVariable` on ISVAR1 and a per-build `ToEvaluateVariable` for the trampoline. The shared
  operand code would then need a parameter.
- Related: AppleSoft's NXTCO1 (save REMSTK, then NEWSTT) is `NextStatementSavingStack`. It is the next-statement
  target AppleSoft's callers pass, where the PET passes NEWSTT. These are two jobs, so two names.

**C-Q5. Constants that are roles, not keywords.**
- Tokens: ONEFUN → `TOKEN_FIRST_FUNCTION`, LASNUM → `TOKEN_LAST_SIMPLE_FUNCTION`. The code uses them as range
  bounds (`cmp #ONEFUN`, `FUNDSP-2*ONEFUN`), so a role name reads better than `TOKEN_SGN` / `TOKEN_CHR`, the
  alternative. SCRATK and ENDTK keep their keywords (`TOKEN_NEW`, `TOKEN_END`), even though they also serve as
  bounds.
- ERRBD prints BAD DATA in BASIC 1 and FILE DATA later. Recommend `ERROR_FILE_DATA`: four builds of five, and
  file INPUT is its only use. Alternative: `ERROR_BAD_DATA`.
- I followed the draft's `ERROR_<MESSAGE>` for message offsets. DOS's X11 used MESSAGE_* for offsets, because DOS's
  error numbers are not offsets. In BASIC the error code is the offset, so ERROR_* fits. Please confirm.

**C-Q6. CheckBreak.** AppleSoft's ISCNTC (Control-C) is in my part. The PET's ISCNTC (the kernal STOP check) is in
D-workspace's Commodore.Equates. They do the same job, so recommend that D use `CheckBreak` too. Alternatives:
`CheckStop`, `CheckControlC` (Apple only).

**C-Q7. Wrappers in front of shared statements.**
- AppleSoft's RUNSTM (decrements CURLIN+1 and falls into the shared RUN) is the table's RUN entry. Recommend
  `Statements::PrepareRun`, with `Statements::Run` kept for the shared code. Alternative: give the table entry
  `Statements::Run` and rename the shared code's label in AppleSoft only. That breaks same job, same name.
- BASIC 2's SNERRX runs GO TO from the dispatcher; BASIC 4's GO is a table entry. Recommend `CheckGoStatement` for
  SNERRX and `Statements::Go` for GO. The contracts differ (SNERRX tests the token itself), as D5 says.
- AppleSoft's POP handles both POP and RETURN (STMDSP sends RETURN there too). It is named `Statements::Pop`; the
  shared RETURN keeps its own name.

**C-Q8. AppleSoft's REDDY = $00 and GOTK = $FF.** These are Microsoft constants AppleSoft defines but never uses: it
has no READY text and no GO keyword.
- Recommend: DROP both, with their names in prose. The PET has the real things: `ReadyMessage`, `TOKEN_GO`.
- Alternative: keep them as documented constants. They would state values that mean nothing in AppleSoft.
- Q, the assembly-time token counter, is DROP too, under the fill-arithmetic rule.

**C-Q9. Unused Microsoft configuration constants in AppleSoft.**
- BUFOFS (set to 0, then to $0200) → `INPUT_BUFFER_BASE`.
- NCMPOS ($0E; AppleSoft compares with $18 inline) → `LAST_COMMA_COLUMN`.
- Commodore's own BUFOFS and NCMPOS are D-workspace rows. D should use the same names; they are not in the
  glossary.
- Alternative: DROP AppleSoft's two copies, since nothing reads them.

**C-Q10. Macro parameters.** All are the SDK's own names, so they stay KEEP, apart from three:
- COMMODORE_ERROR_READY's `suppressOutput` (it clears CNTWFL) → `clearSuppression`.
- COMMODORE_CHARACTER_OUTPUT's `suppressOutput` (it honors CNTWFL) → `honorSuppression`.
- COMMODORE_INPUT_STATEMENT's `suppressWait` (its doc says "output-wait flag", the code clears CNTWFL) →
  `clearSuppression`.
- COMMODORE_INITIALIZE's `lineWidth` → `setLineWidth`, because it differs from the location `LineWidth` only in
  case.

The macros themselves only change case (COMMODORE_TOKENIZE → `CommodoreTokenize`) and get no `Also:`.

**C-Q11. The alias files** (AppleSoft.InterpreterAliases COMBYTE; Commodore.InterpreterAliases COPYC, STRD, CHRD,
LEFTD, RIGHTD, MIDD).
- Recommend: KEEP. These are the vendor's old names for shared code, and under D3 they belong in the vendor's own
  file. Each is re-pointed at the target's new name (B2's names for COMBYT and COPYZC; `Functions::Str` and so
  on), with its document in a `;;` comment.
- Alternative: write them as `;; Also:` on the shared definition, guarded per vendor, if the tools support that.

#### Per module

- **Tokenize (CRUNCH)** is one `.proc` with locals in both vendors. The shared BASIC_TOKEN_STORE macro expands
  inside it, and its labels (GETBPT, STUFFH, STR1, STRNG: part B1's) become `Tokenize::` locals. The macro branches
  to KLOOP and CRDONE, which I named `Tokenize::NextCharacter` and `Tokenize::Finish`, so B1 must write them
  unqualified inside the macro. The same holds for BASIC_DELETE_OLD_LINE / BASIC_LINK_LINE inside `CommandLoop`
  and `LinkProgram` (NODEL → `CommandLoop::InsertLine`, CHEAD → `LinkProgram::NextLine`), and for
  INTEGER_VARIABLE_VALUE (GOOO, GOOOOO) inside `LoadVariableValue`.
- **ColdStart** is one `.proc` across PET's three macros (INIT, the memory probe, the program start). AppleSoft's
  is the same.
- **Bug found (document, do not fix):** BASIC 1's token-tested SPC(0) loops 256 times (`dex; bne XSPAC` with
  X = 0). This is already stated in the macro's comment.
- AppleSoft's CRUNCH runs the program (RUNC, then NXTCO1) when LOCK is set, so a run-only program ignores any
  command line. This is worth a comment; it is not a bug.
- `PrintNewline` / `PrintCharacter` avoid the Monitor's `PrintReturn` (CROUT) and `CharacterOut` (COUT).
- BASIC 1's INPSTP (F part, editor-ROM patch) and BASIC 4's INPSTP (here) do the same job. Recommend the top-level
  `StopEmptyInput` for both; BASIC 4 falls into it.

#### Same old name, different job (intended)

| Old | AppleSoft | Commodore |
| --- | --- | --- |
| QSTATV | `LoadVariableValue::LoadFloat` (AppleSoft has no ST, so Microsoft's QSTATV is just MOVFM) | `LoadVariableValue::MatchStatus` |
| NTHIS1 / NTHIS2 | AdvanceTable / SkipWord | SkipWord / TestWordEnd (named by job: AppleSoft NTHIS2 = PET NTHIS1, AppleSoft NTHIS3 = PET NTHIS2) |
| TRMNO1 | DROP (same address as DOAGIN) | `HandleBadInput::CheckChannel` |
| TRYOUT | DROP (same address as OUTLOC) | `PrintCharacter::RestoreCharacter` |
| REDDY, GOTK | DROP | `ReadyMessage`, `TOKEN_GO` |

Same job under different old names, given one name: Apple ERROR1 = PET ERRCRD, Apple NODEL1 = PET STOLOP, Apple
RESPU1 = PET RESCON (`Tokenize::CompareCharacter`), Apple COMPR1 / IIeE LINCHK (`PrintComma::NextZone`), IIeE TABER
= II+ LINCH1 (`PrintTabOrSpace`), Apple QSTATV = PET GOMOVF.

#### Names chosen to match other parts (please align)

- SNERR, FCERR, LET, RUNC, BLTU, ENDCON, STPEND, PRINTC, ISFUN, COMBYT and COPYZC are other parts' names. My reasons
  use the old names, and my To-names (`ToLet`) assume LET becomes `Statements::Let`.
- `Statements::Run` / `Statements::Return` (shared, B1) are assumed by `Statements::PrepareRun` and `Statements::Pop`.
- D-workspace: `CheckBreak` for PET ISCNTC, `INPUT_BUFFER_BASE` for BUFOFS, `LAST_COMMA_COLUMN` for NCMPOS.
- F-commodore-only: `StopEmptyInput` for BASIC 1's INPSTP, `EvaluateVariable` for BASIC 4's trampoline ISVAR. The
  patches TISTR/TINUM return to `LoadVariableValue::MatchClockString` / `MatchClockNumber` / `MatchStatus` /
  `LoadFloat`.
- E-apple-only: HANDLE (ONERR), and AppleSoft.PlatformHelpers' use of VARTIO (`SetCassetteLengthRange`).

#### Glossary names I disagree with

None that block this part. One minor point: `LastCommaColumn` (NCMWID) is a location, while NCMPOS, its initial
value, has no glossary entry. I used `LAST_COMMA_COLUMN` for the constant; the two names differ only in case style,
so the owner may prefer `LAST_ZONE_COLUMN` for the constant.

### D: The workspace and build switches
Part D covers AppleSoft.Equates, Commodore.Equates, Commodore.Basic4SystemEquates and the build switches in the
roots AppleSoft.asm, Basic1.asm, Basic2.asm and Basic4.asm. The table has 605 rows for this part. I checked names against the code by grepping every use in the MsBasic, AppleSoft and Commodore sources and
reading the routines that use them. K4S79 and HVK4 document most of Basic4SystemEquates. HVK4's other spellings (T1, RCNT, FSBLK, STAL, ZZZ1,
TAPE2) are in the notes for the `Also:` lists.

#### Cross-cutting

##### D-Q1. Should AppleSoft include IIeEquates.asm and MonitorEntries.asm instead of redefining them? (owner decision)

AppleSoft.Equates redefines about 90 Apple names: the Monitor's page zero, the IIe soft switches, and Monitor and
firmware entries. I gave every one the name the converted sources use: WindowLeft, CursorColumn, Address1,
TextOff, Page2On, InternalCxRomOn, Columns80State, LowRes::Plot, Cassette::ReadBit, GetLine, SetInput,
CharacterOut, EightyColumns::CursorColumn (OURCH), and AppleSoftCassette ($C500, the Enhanced firmware's
proc).

- **Recommendation:** AppleSoft includes `../System/IIeEquates.asm` and `../System/MonitorEntries.asm`.
  MonitorEntries gains the entries AppleSoft calls that it lacks. For the Monitor's scoped routines that means
  `.scope LowRes` (Plot, HorizontalLine, VerticalLine, SetColor, ReadColor) and `.scope Cassette` (ReadBit),
  written the way it already exports SetPcFromA1::Loop. The top-level ones are ReadKey, CharacterOut, GetLine,
  GetLineAfterReturn, SetInput, SetOutput, ReadCassette, WriteCassette, ReadPaddle, SetText, SetGraphics and
  VerticalTabTo (Home and Delay are already there). AppleSoft.Equates then defines only BASIC's own workspace.
  Microsoft's second names for Monitor addresses (CQINLN, CQPRMP, CQINCH, CQCOUT, CQCSIN, MPLOT, MSCRN, MWAIT,
  MWRITE, MREAD, OUTPOR, CZGETL) go in an AppleSoft alias file, following D3. EightyColumns::CursorColumn either
  comes from FirmwareEquates.asm or gets a one-name scope in AppleSoft.Equates.
- Alternative (DOS's X7): keep the include of IIeEquates only, and define the missing Monitor entries in
  AppleSoft.Equates with `Inherit:`.
- Alternative: AppleSoft keeps its own copies under the new names. That doubles maintenance, and the copies can
  drift apart.
- Consequences of including:
  - InputBuffer ($0200) is already defined there, so BUF joins its `Also:`.
  - CV is not in IIeEquates (Monitor/Equates.asm keeps it; see D-Q7), and neither is $3F5 (AmpersandJump).
  - Two glossary names clash with IIeEquates: RandomSeed (D-Q2) and SavedOutputY (KIMY, which I dropped).
  - The II Plus build would see IIe-only names. That emits no bytes, but the owner may prefer an Apple II-wide
    subset.
- Most of the Monitor page-zero names are unused in AppleSoft (CH, BASL, CSWL, the A3 to A5 registers, XREG ...).
  If AppleSoft includes IIeEquates they cost nothing. Otherwise they should be DROPped.

##### D-Q2. RandomSeed clash (glossary RNDX)

IIeEquates already has `RandomSeed = $4E` (the Monitor's RNDL). In AppleSoft that clashes with the glossary's
RandomSeed for RNDX ($C9). **Recommendation:** rename the glossary entry to `RandomValue` (RND's last value,
which is what the code keeps there). Alternative: `LastRandom`. I used RandomSeed in the table, as the draft rules say.

##### D-Q3. Glossary names the code disagrees with (used anyway, as instructed)

- **SIZE** (FunctionJumpTarget): nothing reaches JMPER+1 by this name. All four uses are the string collector's
  descriptor-offset scratch (GRBPAS). Recommend a collector alias `CollectorOffset` and no top-level name.
- **OLDOV** (FunctionJumpHigh): FADD stores the smaller operand's extension byte here, and EXP keeps a rounding
  byte here. It is never a jump address. Recommend `ArgExtension`, or a scoped alias in FADD and EXP.
- **LSTPNT** (ListString): LIST uses this one byte to save its Y index into the line (sty/ldy). It is not a pointer
  to a keyword. Recommend `ListPosition`.
- **KIMY** (SavedOutputY): no code uses it, and the name clashes with IIeEquates' SavedOutputY (YSAV1). I marked
  it DROP, with KIMY going into Dimensioning's `Also:`.
- **LINWID** in AppleSoft (LineWidth): it is an unused equate at $25, which is the Monitor's CV, not a width. I
  marked it DROP.
- **NCMWID** in AppleSoft (LastCommaColumn): its only use, in READY, stores MEMSIZ's high byte at $70, which is
  StringsBottom+1. Recommend writing `StringsBottom + 1` there and putting NCMWID in prose.
- **DECCNT** (DigitsBeforePoint): FIN counts the digits *after* the decimal point here. Only FOUT uses it for the
  digits before the point. Recommend `DigitCount`.
- **DPTFLG/TENEXP**: the code confirms the glossary. Microsoft's comments for the two names are swapped (a doc
  bug; nothing to change). **SGNFLG** (InputSign) is also confirmed.
- **LOWDS** (DestinationStart): no code reads it by name. It only anchors the layout of DECCNT and TENEXP. I kept
  the glossary name.
- **QNUM/CHRRTS**: I had written that no code used either name, because the template has its own CHZ* labels; that was
  wrong (R5). I wrote `GetNextCharacter::TestColon` and `::Return` as placeholders until the CharacterReader part names
  them.

##### D-Q4. Unused Microsoft configuration constants in AppleSoft

GETCMD, RORSW, ROMSW, LONGI, KIMROM, NULCMD, CLMWID, LINLEN, BUFLEN, NUMLEV, CONTW, RAMLOC, CQINLN, CQPRMP, CQCOUT
and CQCSIN are referenced by nothing in AppleSoft or the shared modules. **Recommendation:** keep the
configuration ones as one block under the new UPPER_SNAKE names (GET_COMMAND, ROTATE_INSTRUCTION, ROM_RESIDENT,
LONG_INITIALIZATION, KIM_ROM, NULL_COMMAND, ZONE_WIDTH, LINE_LENGTH, INPUT_BUFFER_LENGTH, STACK_LEVELS,
SUPPRESS_OUTPUT_KEY, RAM_ORIGIN). They cost nothing and record Microsoft's configuration (M6502 documents each).
The CQ* ones go in the alias file (D-Q1). Alternative: DROP them all and list Microsoft's settings in the file's
prose.

##### D-Q5. Names for the PET kernal (no converted source)

- The jump table at $FF93 to $FFE7 becomes `Kernal*` at top level: KernalOpen, KernalClose, KernalSelectInput,
  KernalSelectOutput, KernalResetChannels, KernalCharacterIn, KernalCharacterOut, KernalLoad, KernalSave,
  KernalVerify and KernalSys. The BASIC 4 disk entries are named for their keywords: KernalDiskOpen,
  KernalHeader, KernalDirectory, KernalReadDiskStatus and so on. "Kernal" is Commodore's own term.
- Exceptions: the three vectors shared code calls get vendor-neutral names that AppleSoft also defines.
  - ISCNTC becomes `CheckStop`. AppleSoft's own ISCNTC routine, in part C or E, must take the same name.
  - CZGETL becomes `GetCharacter`. On the Apple it is an alias of ReadKey.
  - CQCALL becomes `CloseAllFiles`.
- The internal kernal routines in Basic4SystemEquates get descriptive names: InputCharacter (BASIN),
  OutputCharacter (BSOUT), GetInput (GETIN), RestoreChannels, Talk, Listen, Untalk, Unlisten, ReceiveByte,
  FindLogicalFile and so on.
- The PET monitor's saved registers reuse IIeEquates' names (SavedA, SavedX, SavedY, SavedStatus,
  SavedStackPointer, ProgramCounter), since they do the same job. ScreenOut (PRT) also matches the Apple Monitor's
  name.
- Alternatives:
  - a scope `Kernal::Open ...`. Rejected: Kernal::CharacterIn and similar would sit too close to the top-level
    vector names, and the shared vectors must be unscoped anyway.
  - the C64 manual's names (CHRIN, CHROUT, CLALL) as `Also:` only. They are not documented for the PET here.
- The six statement handlers that live in the kernal (LOAD, SAVE, VERIFY, OPEN, CLOSE, SYS, and BASIC 4's disk
  commands) are dispatch-table targets outside BASIC. I named them Kernal* rather than `Statements::Load`.
  Alternative: add `Statements::Load = KernalLoad` aliases so the Statements scope is complete.
- OUTCH is CharacterOut on the Apple (the Monitor's COUT) but KernalCharacterOut on the PET. No shared code calls
  it, so the PET name follows the jump table's names. Alternative: CharacterOut in both vendors.

##### D-Q6. One definition for names defined twice at one address

SATUS and CQSTAT become `IoStatus` ($96 in BASIC 4), with both names in `Also:`. The other pairs are MS1/MSG1
(KernalMessages), CLRCH/CLRCHN (RestoreChannels), CLOS5/FCLOSE (CloseLogicalFile) and INDEX/INDEX1 (Pointer1).

Some constants copy table values: PI, PLUSTK, MINUTK, ONTK (TOKEN_PI, TOKEN_PLUS, TOKEN_MINUS, TOKEN_ON), ERROV and
ERRDV0 (ERROR_OVERFLOW, ERROR_DIVISION_BY_ZERO). Each should be one definition, shared with the token or error
table, as the file's header already asks.

CR is CHARACTER_RETURN. It must match whatever the other PET parts call carriage return. KEY_RETURN is the Apple
precedent, but there it is a key with bit 7 set.

BAD ($0100) is the same byte as NumberBuffer: it should be an alias in BASIC 4.

The monitor stores PCH below PCL, so ProgramCounterHigh is at the lower address. A note is enough.

##### D-Q7. CV

The Monitor conversion left CV unconverted (the DOS log's X7: "BASIC names wait for the BASICs' conversion").
**Recommendation:** `CursorLine`, matching the firmware's `EightyColumns::CursorLine` ("its copy of CV"). The
Monitor's Equates.asm would take the name. Alternative: `CursorRow`.

##### D-Q8. C# looks up workspace names

`Retrocore.Debug/PetDebugTarget.Basic.cs` reads Symbol("CURLIN"), ("TXTPTR"), ("TEMPST"), ("TEMPPT"),
("SUBFLG"), ("OLDTXT") and ("STKEND"). After the rename, either the C# moves to the new names or the symbol lookup
resolves `Also:` names. **Recommendation:** update the C# when converting, and keep the old names in `Also:`
either way. REVISD, ENHNCD, APLPLS, TIME, EXTIO, DISKO and REALIO stay (KEEP): C# and the tests predefine them.

##### D-Q9. String descriptor size

STRSIZ becomes DESCRIPTOR_SIZE, per the glossary. Alternative: a `StringDescriptor` struct (LENGTH, ADDRESS) with
`StringDescriptor::sizeof`, which would also serve TemporaryDescriptors. That is a structs decision for the whole
BASIC conversion.

##### D-Q10. Kernal bytes BASIC 4 reuses for another purpose

WSW (the cassette write flag) and CNTDN (the cassette countdown) are used only by CATALOG, which saves its output
file and device in them. I named them for that use (CatalogOutputFile, CatalogOutputDevice). Alternative: kernal
names at top level (CassetteWriteFlag, CassetteCountdown) with scoped aliases in the catalog routine, following
the "shared bytes get scoped aliases" rule. That is better once a kernal source exists.

#### Per module

- **Build switches.** I kept the SDK's descriptive Basic1 switches (KEEP) except where a name spells a Microsoft
  name or abbreviation that is itself being renamed:
  - LOCAL_TRMPOS becomes LOCAL_TERMINAL_POSITION
  - VARTXT_IN_LINNUM becomes VARIABLE_LIST_IN_LINE_NUMBER
  - INTIDX_USE_FRMNUM becomes SUBSCRIPT_CHECKS_NUMERIC (FRMNUM is FRMEVL plus the numeric check)
  - POSINT_CHECK_TYPE becomes POSITIVE_INTEGER_CHECKS_TYPE
  - STRING_CLEAR_FACOV becomes STRING_CLEARS_FAC_EXTENSION
  - GC_* becomes COLLECTOR_*
  - PREAM_INDIRECT_RETURN becomes STRING_PREAMBLE_INDIRECT_RETURN
  - SHORT_FMUL_ZERO becomes SHORT_MULTIPLY_ZERO
  - EARLY_FIN_LIMIT becomes EARLY_INPUT_EXPONENT_LIMIT
  - PRECISE_FOUT_LIMIT becomes PRECISE_OUTPUT_LIMIT
  - ZERO_AT_FHALF becomes ZERO_IN_HALF_CONSTANT

  Optional, not applied: INIT_* to INITIALIZE_*. Microsoft's own switches become their glossary names (BUFPAG is
  INPUT_BUFFER_PAGE, BUFLEN INPUT_BUFFER_LENGTH, NULCMD NULL_COMMAND, NUMLEV STACK_LEVELS, STKEND STACK_END).
- **ROMLOC/LASTWR.** ROMLOC becomes ROM_ORIGIN. LASTWR becomes `InterpreterEnd`, the label after BASIC's last
  byte: PEEK's ROM guard ends at its page, and BASIC 4's extension starts there. Commodore.Basic1Patches' LASTWR,
  in another part, should take the same name.
- **AppleSoft's own workspace.**
  - Hi-res: HighRes* (HighResX, HighResY, HighResPage, HighResColor, HighResColorByte ...) and Shape* (ShapeTable,
    ShapeScale, ShapeRotation, ShapePointer/ShapePointerHigh). SHAPEL and SHAPEH are two definitions, so they follow
    the Name/NameHigh rule.
  - ONERR: OnErrorActive, OnErrorText, OnErrorLine (the handler's position), and ErrorLine, ErrorText, ErrorCode,
    ErrorStack (the trapped error, for RESUME).
  - Others: StatementStack (REMSTK), RunOnly (LOCK), TraceMode, OutputDelay (SPEEDZ), FlashMask, ProgramEnd,
    AmpersandJump ($3F5), RestartJump (START).
  - Hi-res code reuses two Monitor bytes for its own purposes: GBASL as the hi-res byte address (ASTIL HBAS) and
    COLOR as the pixel mask. I recommend scoped aliases (HighResBase, HighResMask) in the hi-res scope.
- **Commodore.Equates.** CurrentChannel (CHANNL; shared code reads it), NullCount, EditorCursorColumn (CQPNTR),
  InputBufferBase (BUFOFS), DiskStatusDescriptor, JiffyClock (CQTIMR), IoStatus (CQSTAT) and RandomTimer (CQHTIM).
  BITS is `ShiftFill` in both vendors (not in the glossary).

#### Names I matched to another part's routine or definition

- GetCharacter and CheckStop: AppleSoft's ISCNTC routine (part C or E) must be CheckStop.
- InterpreterEnd: Commodore.Basic1Patches' LASTWR.
- LAST_ZONE_COLUMN: AppleSoft.Print's NCMPOS.
- InputBufferBase: AppleSoft.ErrorAndInput's BUFOFS `.set`.
- ERROR_OVERFLOW and ERROR_DIVISION_BY_ZERO: AppleSoft.DispatchTables' ERROV and ERRDV0.
- TOKEN_PI, TOKEN_PLUS, TOKEN_MINUS and TOKEN_ON: the token tables.
- POSITIVE_INTEGER_CHECKS_TYPE and STRING_PREAMBLE_INDIRECT_RETURN: these depend on part B2's names for POSINT and
  PREAM.
- GetNextCharacter::TestColon and ::Return: settled by R5 as ClassifyCharacter and CharacterReaderReturn.
- The Apple names follow IIeEquates, MonitorEntries, Monitor/ (LowRes, Cassette), FirmwareEquates
  (EightyColumns::CursorColumn) and Firmware.Enhanced (AppleSoftCassette).

### E: AppleSoft's own statements and graphics
Modules: AppleSoft.AppleCommands, AppleSoft.HighResolution, AppleSoft.PlatformHelpers. 150 rows. Monitor, soft switch and page-zero names are reused from the converted Monitor, IIeEquates,
FirmwareEquates and the Enhanced IIe firmware: SetInput, SetOutput, LowRes::Plot, LowRes::HorizontalLine,
LowRes::VerticalLine, LowRes::SetColor, VerticalTabTo, SetGraphics, SetText, WriteCassette, ReadCassette,
Cassette::ReadBit, HiResOn/Off, TextOff, MixedOn/Off, Page2On/Off, InternalCxRomOn/Off, Columns80State,
Address1/Address2(High), LowResBase(High), HorizontalLineEnd, VerticalLineEnd, PlotColor, InverseMask, WindowWidth,
EightyColumns::CursorColumn, AppleSoftCassette. AppleSoft's own page zero (FIRST, HPAG, HCOLR1 ...) belongs to the
workspace part, so the reasons use the old names for it.

#### Scopes used, and why

- `Statements`: every dispatch target, named for its keyword (the draft's default), plus the helpers only
  statements use: ReadLowResLine, SetInverseMask, SetTextMasks, ReadShapeNumber, FindCassetteArray,
  CallAppleSoftCassette, SetArrayBlock, ToSyntaxError.
- `HighRes`: the hi-res engine (page select, clear, fill, position, plot, steps, line, find, draw, the tables). I
  used it because the Monitor's lo-res family is the scope `LowRes`, and Monitor rule 18 keeps subsystem routines
  in their family even when programs call them (`LowRes::Plot`).
- Top level: what other modules reach (TrapError, ReadLowResCoordinates, ToIllegalQuantity, the enhanced IIe's
  tokenizer, lister and PRINT helpers), the two TIL "text" readers, and BasicEnd (settled as InterpreterEnd, K3).

#### Questions

**E-Q1. Labels that other routines branch into from the middle or end of a routine.** HiMem::ToOutOfMemory (LoMem),
StepHorizontal::AdjustColor (Position, Fill), PlotStep::WritePixel and ::Move (XorStep), FindCoordinates::Done
(Line), HColor::Done (HPlot), DistanceToColumn::SetPosition and ::Done (HTab), XorStep::Across and
PlotStep::Across (the shape loops). The draft rules say such a label becomes its own `.proc` or a scope-level label. Here
each one sits inside a routine that runs into it, so splitting would cut a routine into two or three pieces.
- Recommend: write them as `Proc::Label` entries listed under the routine's `Entry:`, as the Monitor does with
  `ReadCassette::Finish`, which WriteCassette branches to.
- Alternative: split each one into a proc with "Falls into" (StepHorizontal into three procs, HiMem into three).

Where the label follows an `rts` or `jmp`, I made it its own proc as the draft rules say (ToIllegalQuantity,
RejectHighResArgument, Statements::ToSyntaxError, ReadBufferCharacter, SelectPage, SetInverseMask, SetTextMasks).

**E-Q2. The TIL's hi-res entries: scope or top level, and the scope's name.** The draft rules say the TIL entries are
top-level candidates. I put HPOSN, HPLOT ($F457), HLIN ($F53A), HFIND, DRAW ($F601), XDRAW ($F65D), HCLR and BKGND
in `HighRes`, following Monitor rule 18. Each still keeps its `.assert`. I kept HFNS and PLOTFNS at top level, as
`ReadHighResCoordinates` and `ReadLowResCoordinates`: SCRN calls PLOTFNS from another module, and HFNS is its
hi-res twin.
- Recommend: `HighRes` (the name you suggested, and the full-word partner of the Monitor's `LowRes`).
- Alternatives: `HiRes`, which matches IIeEquates' `HiResOn` and `HiResState`; or no scope, with every TIL entry
  at top level (`HighResPlot`, `HighResLine` ...).

**E-Q3. TIL names that clash with other definitions, and TIL entries that have no label.**
- ASTIL's HPLOT, HLIN, DRAW and XDRAW name the engine entries ($F457, $F53A, $F601, $F65D). In the same assembly,
  the statement handlers are already HPLOT, HLIN, DRAW and XDRAW (AS82 and the source). Recommend: one old name to
  one definition, so the handlers keep `Also:` and the engine entries name the TIL in prose ("Apple's Technical
  Information Library calls it HPLOT"). Alternative: give `Also:` to the TIL's addresses and drop the statement
  handlers' old names.
- ASTIL's SETHCOL is $F6EC, inside HCOLOR right after its GETBYT (X = color). No label is there now. Recommend:
  split it out as `HighRes::SetColor` (Also: SETHCOL (ASTIL)), with Statements::HColor falling into it after the
  GETBYT. That name does not shadow the Monitor's `LowRes::SetColor`.
- ASTIL gives RESUME as $F317, one byte before the handler at $F318. That is the dispatch-table value (address
  minus one). Recommend: keep `Also: RESUME (ASTIL)` on Statements::Resume, with the address noted in prose.

**E-Q4. How keywords are cased in statement names.** I split each keyword into its words, as in the draft's
`Statements::OnErr`: HGr, HGr2, HColor, HPlot, XDraw, HTab, VTab, HLin, VLin, ShLoad, HiMem, LoMem, NoTrace, Gr,
Rot. PR# and IN# are PrNumber and InNumber, after DOS's `Commands::PrNumber`. COLOR= is Color, and SPEED=, ROT=
and SCALE= drop the `=`. NORMAL and INVERSE are Normal and Inverse; the Monitor's top-level names are SetNormal and
SetInverse, so nothing is shadowed.
- Recommend: as drafted.
- Alternative: whole keywords as single words (Hgr2, Hcolor, Xdraw).

**E-Q5. Bytes the hi-res code borrows from the Monitor.** It uses PlotColor ($30) as its pixel mask (Apple's HMASK),
LowResBase/LowResBaseHigh as the screen byte's address, HGRDX+1 as the current shape byte, and HGRQUA as the
rotation quadrant. FacExponent is HFNS's scratch byte.
- Recommend: scoped aliases in `HighRes` (`PixelMask = PlotColor`, `ByteAddress = LowResBase`,
  `ByteAddressHigh = LowResBaseHigh`), as the Monitor's `Checksum = PlotMask`. These are the workspace part's rows:
  please route them there.
- Alternative: leave them as they are and explain in comments.

**E-Q6. The enhanced IIe's helpers that other modules call.** These are UppercaseNextCharacter, UppercaseInput,
UppercaseBufferCharacter, UppercaseCharacter and ReadBufferCharacter (the tokenizer), PrintSpaceAndLineNumber
(the lister) and CompareCommaColumn and DistanceToColumn (PRINT).
- Recommend: top level, because other modules reach them and none is documented.
- Alternative: put them in the families' scopes (`Tokenizer::`, `Lister::`, `Print::`), if the parts that own those
  modules make those scopes.

**E-Q7. Names that depend on other parts or on the firmware.**
- ToIllegalQuantity, Statements::ToSyntaxError and the ToOutOfMemory locals take "To" plus the target, whatever the
  error routines' new names turn out to be.
- HFNS11 only jumps on to ToIllegalQuantity. Calling it `HighRes::ToIllegalQuantity` would shadow the top-level
  name, so it is `RejectHighResArgument`. If the error part names FCERR's stub differently, this can follow.
- SETA2 is `Statements::SetArrayBlock`, after the firmware's `AppleSoftCassette::ArrayBlock` (the same code).
  Alternative: `SetArrayRange`, following DOS P9 ("range, not block").
- CALLC5 is `CallAppleSoftCassette`, after the firmware routine it calls. The II Plus and IIe SHLOAD's locals reuse
  the firmware's StoreEnd and ShapeTable. SHLOD2 is ToOutOfMemory, because the firmware's OutOfMemory returns
  carry instead.

**E-Q8. Operand bytes read as data.** MASK03 and MASK04 are `* + 1` equates on `and #3` and `adc #4`, which `bit`
reads as masks. MASK1C is a real `.byte`.
- Recommend: names for the locations (LowTwoBitsMask, BitTwoMask, RowInGroupMask), with the original names in
  `Also:` and a comment on the operand trick.
- Alternative: one `RowInGroupMask`-style name per bit field of the screen address (group bits, third bits) once the
  conversion documents the layout.

**E-Q9. Unreachable code at $F530.** After StepVertical's last `bcc`, 10 bytes ($F530-$F539) zero HGRX and HGRY and fall into
HighRes::Line, drawing a line from (0,0). Nothing branches there, and the `bcc` is always taken: the `asl` clears
bit 0 of LowResBase, the `ror` moves that bit into carry, and no path between them sets it.
- Recommend: no label; document the bytes as unreachable, with what they would do.
- Alternative: a named local `StepVertical::LineFromOrigin`, if a document gives this address a name.

**E-Q10. LASTWR.** (Settled as `InterpreterEnd`, K3.) It was drafted as `BasicEnd` (Also: LASTWR (M6502)), "End" being the byte after, as in DOS X5. It needs the
same name as the Commodore part's LASTWR. Its `.res 100` is Microsoft's temporary-stack block. In AppleSoft it
covers $F800-$F863, which is Monitor ROM code (LowRes::Plot to just before LowRes::SetColor), not the "Monitor
workspace" the comment says. That comment is wrong and should be fixed in the conversion.

#### Found in the code (document, not fix)

- HIMEM sets StringsBottom to the new top without moving strings that are already above it.
- SHLOAD checks the fit on high bytes only, in both its own copy (II Plus, IIe) and the firmware's.
- Shape number 0 is accepted. It reads the table's count byte and unused byte as an offset.
- XDRAW's collision count (COLCNT) counts pixels that were clear before XDRAW toggled them. DRAW's counts pixels
  that already had the color.
- The overlay's DRWPNT is XDRAW's step and XDRPNT is DRAW's step: the names are the wrong way round for this code.
- An HSCALE of 0 draws 256 steps per vector.
- The enhanced IIe's uppercase conversion also folds $7B-$7F to $5B-$5F. When the byte after the current one has
  bit 7 set, UPNXT returns the current byte instead of the next (likely unreachable).
- StepHorizontal wraps within the row (0 to 39) instead of stopping at its edge.
- In the TIL, HFNS's exit says Y is the vertical coordinate's msb; it is the column's high byte.

#### Glossary names

I disagree with none. One remark: AppleSoft's TRMPOS is $24, the Monitor's `CursorColumn`, so TerminalPosition
should be an alias of it in AppleSoft's file (`TerminalPosition = CursorColumn`), not a second location.

#### Named to match another part or source

- BasicEnd (settled as InterpreterEnd, K3): matches the Commodore part's LASTWR (Basic2, Basic4, Basic1Patches).
- Statements::PrNumber and InNumber: follow DOS's Commands::PrNumber.
- ShLoad::StoreEnd, ShLoad::ShapeTable, SetArrayBlock and CallAppleSoftCassette: follow the Enhanced IIe firmware's
  AppleSoftCassette.
- HTab::NextLine: the same local name in both HTAB builds.

### F: Commodore's own code
Rows: 343. Every label nothing
references has a K4S79/HVK4 name, so none is dropped. They are kept as locals, and each says so in its note.

#### Cross-cutting

**F-Q1. Disk statement handlers: the keyword or full words?**
Recommendation: name them for the keyword, in `Statements`: `Statements::Dopen`, `Dclose`, `Dsave`, `Dload`,
`Header` (FORMAT), `Collect` (COLECT), `Backup`, `Copy` (DCOPY), `Append`, `Catalog` (CATLOG, also DIRECTORY),
`Rename`, `Scratch` (DSCRTC), `Concat`, `Record`. This is the default for statement handlers, and it follows the DOS
precedent (`Commands::PrNumber` keeps the command word). A reader looks the handler up by the keyword, and
`Statements::Dopen` sits clearly beside `Statements::Open`.
Alternative: full words (`Statements::DiskOpen`, `DiskClose`, `DiskSave`, `DiskLoad`). They read better, but they
break the keyword-lookup rule, and DOS's `FileManager::OpenFile` precedent applies to a request word, not to a keyword.
Either way, Kernal4's jump-table entries (CQDOPN ...) call them by the qualified name. The $FFxx names DOPEN etc.
(CBM4S79/HV4) belong to the kernal's entries and go there in prose, not in `Also:`.

**F-Q2. A scope `Disk` for the disk helpers?**
Recommendation: put the parser, checks, command builder, status reader, confirmation and file-closing helpers in
`.scope Disk`, continued across Basic4Record, Basic4DiskCommands, Basic4DiskParser and Basic4RomEnd
(`Disk::StoreStatusLink`). They are one family that only the disk statements use. The one exception is
`ForgetDiskStatus` (OLDCLR), which stays top level because Kernal4's TALK and LISTEN call it.
Alternatives: put them in `Statements`, which makes the scope crowded with non-handlers; or put them at top level,
which pollutes it with about 30 names.

**F-Q3. Undocumented overlay spellings: DCOPY, DSCRTC, MGO, GTVLCN.**
The source changed these from Commodore's names (BasicEntries.asm says so for DCOPY and DSCRTC), so no document
gives them. Recommendation: give them no `Also:`, and give Commodore's real spelling in prose. That spelling is
probably COPY, SCRTCH and GO, but it should be checked against K4S79. It clashes with m6502's names, so it cannot be
an `Also:` (DOS X8 rule).

**F-Q4. Labels that other routines branch into.**
This ROM saves bytes by sharing tails. My choices:
- Where code falls through or jumps into another routine's start, I split it into separate procs with "Falls
  into": ReadStatus, AllocateStatus and ReadErrorChannel; BuildCommand, BuildCommandAt and SetCommandName;
  SendCommand and OpenCommandChannel; SaveState, Prompt and Dispatch; AlterMemory and AlterBytes; PrintAddress,
  PrintByte and PrintPair; CheckTwoNames and RequireTwoNames.
- Bare `rts` or `jmp` tails become scope-level labels: `Disk::Return`, `Disk::ToSyntaxError`,
  `Disk::RejectParameter`, `Monitor::Return`, `Monitor::ToPrompt`, `Monitor::ToReportError`,
  `Statements::ToSyntaxError`.
- Two entries stay as `Proc::Local` written from another routine:
  - `Statements::DLoad::Reject` (Rename branches to it);
  - `FindStringLink::CompareStatusLow` and `::AddLength` (the revised ROM's TestStatusString jumps back into them,
    see F-Q9).

Recommendation: accept these choices. The alternative is to make every such target a scope-level label.
Per-routine `jmp SNERR` relays are named `Reject` (or `Fail` in the monitor), not `ToSyntaxError`, so that they do
not shadow the scope-level `ToSyntaxError`.

**F-Q5. Disk-command template offsets and codes.**
XFN1 through XD2 become prefixed constants `INSERT_*`. Each handler's template offset and length are bare numbers
(`ldy #26`, `lda #8`). Recommendation: write CommandTemplates with a macro that defines `TEMPLATE_<COMMAND>` offsets
and `_LENGTH` sizes and asserts each position, as DOS X11 does for messages.
Alternative: leave the numbers and add a comment table.

**F-Q6. PRSCHK bits (part D's location).** The parser and the checks test the masks $01, $02, $04, $08, $10, $20,
$40 and $80, and combinations such as $E6, $E7, $C4 and $F3. Recommendation: define bit constants `PARSED_FIRST_NAME`,
`PARSED_SECOND_NAME`, `PARSED_FILE`, `PARSED_UNIT`, `PARSED_FIRST_DRIVE`, `PARSED_SECOND_DRIVE`, `PARSED_RECORD`
and `PARSED_REPLACE`, and write each check's mask as an OR of the bits it rejects. This needs agreement with part D.

**F-Q7. The monitor as `.scope Monitor`.**
Recommendation: make the monitor one scope with flat routine names (`Monitor::DisplayMemory`, `Monitor::Go`,
`Monitor::LoadOrSave` ...). It is self-contained, the kernal reaches only EnterByCall, EnterByBreak and ReportError,
and its short generic names (Space, Byte, Exit) would otherwise crowd top level. I chose not to add an inner
`Commands` scope: the command routines are the monitor's main content, and the Apple Monitor's `Commands` scope
precedent served a ROM that has many other families.
BASIC 2's Kernal2.asm (and partly Editor2.asm) holds the same monitor with the same old names. When it is converted,
it should take the same new names ("same job, same name").
Alternative: `MachineMonitor`, if the owner wants to avoid any confusion with the Apple Monitor sources.

**F-Q8. The linked collector's structure.** GARBA2 becomes top-level `CollectGarbage`, and its jsr helpers (SkipLinks,
SkipSourceLink, LowerSource, LowerDestination, LoadDescriptorAddress) are nested routines. ENDGRB becomes the local
`CollectGarbage::Finish`, because only GRBEND jumps to it. The name must match part B2's choice for the classic
GARBA2. Alternative: a scope `Collector` with `Collector::Collect`. In this collector, HIGHDS (glossary:
`DestinationEnd`) is a mode flag, not an address (bit 7 means a gap is open). Recommendation: give it a scoped alias
(`GapOpen = HIGHDS`).

**F-Q9. FindStringLink and its revised-ROM patch.** The revised ROM replaces the inline DS$ check with `jmp ADJDS`
(TestStatusString at $BF10), which jumps back to ADJDS1 and ADJ02. Recommendation: keep FindStringLink as one proc
with two documented entries (`CompareStatusLow`, `AddLength`), and keep TestStatusString as its own top-level proc.
Alternative: split FindStringLink into three fall-through procs. That gives about 30 bytes four contracts.
Bug, to document and not fix: the original ROM's check compares only DS$'s address and not its length. After
ForgetDiskStatus releases the buffer, a string that later occupies that address is mistaken for DS$ and never gets
linked. The revised ROM's TestStatusString adds the length test.

**F-Q10. Qualifiers that depend on part B2.** The STRING_STATUS_CHECK and LINKED_STRING_STORE labels are locals of
B2's GETSPT, which I called `AssignString`. The TI$ labels are locals of B2's INPCOM, which I called
`AssignStringResult`. COPYZC is `AssignString::StoreDescriptor`, the same as B2's COPYZC entry. When the parts are
merged, replace these qualifiers with B2's names. TI$'s TIMNUM is a nested routine (`AddClockDigit`). Its FCERR2,
shared with the length check, is `AssignStringResult::ToIllegalQuantity`.

**F-Q11. Names chosen to match part C.**
- `StopOnBlankInput` matches part C's INPSTP in ChannelInput.
- `GetDataLine` matches GETDTL in ChannelInput and AppleSoft. The BASIC 1 version is a subroutine and returns the
  line in A/Y; the others are inline. Check that the job is the same.
- `EvaluateVariable` is the BASIC 4 ISVAR trampoline and matches part C's ISVAR.
- `RouteNumericVariable::ToClockNumber` needs part C's name for TINUM1, and `HandleBlankInput::ToInputContinue`
  needs B2's name for INPCON.

**F-Q12. LASTWR → `InterpreterEnd`.** BASIC 1's label marks the end of the interpreter's ROM code (MemoryAccess's
ROM guard compares against it). It must take one name with part D's Basic2/Basic4 LASTWR and part E's AppleSoft
LASTWR. Alternative: `BasicEnd`, or `RomCodeEnd` per DOS X5's `<Range>End`.

#### Per module

- **Basic1Patches.** TISTR is entered by `jmp`, so its `rts` returns from the whole variable evaluation. The
  comment should say so. GETSTR and GETST1 are one patch split around other patches, so they are two procs:
  `BeginGetString` jumps to `ResumeGetString`.
- **Basic4DiskCommands.**
  - AllocateStatus's backlink low byte is the literal $0D, which is DSDESC's address. Recommendation: write it as
    `<DSDESC` with an `.assert`.
  - ReadErrorChannel does not bound its loop: a reply of more than 40 characters overruns into the link and beyond.
    Document it.
  - Header closes the unit's files before asking for confirmation, even when the answer is no. Document it.
  - Confirm accepts the answer when a zero byte arrives while it drains a rejected answer. Document it.
  - Every template inserts the second name before the first, because INSERT_FIRST_NAME (AppendFirstName) overwrites
    the second name's pointer. Document it on CommandTemplates.
  - COPY's whole-drive and file forms share one template; empty names drop their separators.
- **Basic4DiskParser.** R is accepted and skipped with no effect. DIDCHK shares LRECL's byte, so ParseParameters
  clears it. A filename without @ is limited to 16 characters, and to 17 with @. A second `@` name gives SYNTAX ERROR.
- **Basic4Monitor.**
  - EnterByCall reaches SaveState's `adc #$FF` without setting the carry, while EnterByBreak clears it (`lsr`). This
    is harmless at reset, but the comment should say it.
  - The comment "after a CALL" is inaccurate: the kernal jumps there at reset when the diagnostic line is low.
  - LoadOrSave's L2 through L14 are branch relays. I named each for the test at the relay rather than `To...`,
    because each relay also tests something.
- **Basic4Patches / RomEnd.** The unlabeled first byte of the $B000 patch area is that chip's checksum byte. It
  could take a name, `InterpreterChecksum`, beside `ExtensionChecksum` (CKSUMD), but it is not a row here. (Part F
  gave it that name, with HV4's and HV4R's CKSUMB: F8.)
  SIGNON becomes `SignOnMessage`, which should match whatever parts C and D call BASIC 1/2's banner (FREMES etc.).
- **Switches and parameters.** DISK_STATUS_STRING, LINE_WIDTH_STORAGE and EXTENDED_DISK_VECTORS are KEEP. They are
  the SDK's names, and their `.ifndef` defaults here duplicate Basic4.asm's. `revised`, `patchedStatus` and
  `longLengthError` are KEEP. The macros are renamed to PascalCase (`CommodoreBasic4Monitor` ...).

#### Glossary names I disagree with

- HIGHDS = `DestinationEnd`: the name is right for the block mover, but in BASIC 4's collector the byte is a flag
  (see F-Q8). Use the glossary name, with a scoped alias.
- POKER = `PokeAddress`: Disk::PositionRecord sends it as the record number that RECORD stores through GETADR. The
  glossary name is fine for POKE; the disk code should use a scoped alias (`RecordNumber = POKER`).

## The workspace glossary

The shared workspace names both vendors define, named before the parts were drafted so that every part used them. The parts checked them against the code; the four marked are corrected.

| Old | New | Note |
| --- | --- | --- |
| TXTTAB | `ProgramStart` | pointer to the first program line |
| VARTAB | `VariablesStart` | pointer to the simple variables, after the program |
| ARYTAB | `ArraysStart` | pointer to the arrays, after the simple variables |
| STREND | `ArraysEnd` | end of the arrays: the bottom of free memory |
| FRETOP | `StringsBottom` | lowest string; strings grow down from MemoryTop |
| MEMSIZ | `MemoryTop` | highest byte BASIC uses + 1 (HIMEM) |
| FRESPC | `NewString` | pointer to the string just allocated |
| TXTPTR | `TextPointer` | CHRGET's operand: the program or buffer text being read |
| CHRGET | `GetNextCharacter` | the page-zero reader: advances TextPointer, then reads |
| CHRGOT | `GetCurrentCharacter` | the page-zero reader's entry that rereads the current character |
| CURLIN | `CurrentLine` | line number executing; $FFxx in direct mode |
| OLDLIN | `StoppedLine` | line STOP or END left, for CONT |
| OLDTXT | `StoppedText` | text pointer STOP or END left, for CONT |
| DATLIN | `DataLine` | line number of the DATA being read, for errors |
| DATPTR | `DataPointer` | READ's position in DATA |
| INPPTR | `InputPointer` | where INPUT or READ is reading from |
| LINNUM | `LineNumber` | 16-bit integer work area (line numbers, addresses) |
| VARNAM | `VariableName` | the two-byte encoded name being looked up |
| VARPNT | `VariablePointer` | pointer to the value of the variable found |
| FORPNT | `AssignedVariable` | pointer to the variable LET, FOR, INPUT or READ stores into |
| VALTYP | `ValueType` | $FF string, $00 numeric |
| INTFLG | `IntegerType` | $80 integer, $00 float |
| DIMFLG | `Dimensioning` | set while DIM is defining arrays |
| SUBFLG | `SubscriptMode` | corrected in the merge |
| INPFLG | `InputMode` | INPUT ($00), GET ($40) or READ ($98) |
| DORES | `TokenizeState` | whether the tokenizer may crunch reserved words (DATA, quotes) |
| GARBFL | `CollectionState` | alias of TokenizeState's byte, used by string allocation |
| CHARAC | `Delimiter` | the delimiting character a scan stops at |
| ENDCHR | `EndDelimiter` | the other delimiting character |
| INTEGR | `SmallInteger` | alias of Delimiter: QINT's one-byte integer |
| COUNT | `Counter` | a general counter |
| TEMPPT | `NextTemporary` | offset of the first free temporary descriptor |
| LASTPT | `LastTemporary` | pointer to the last-used temporary descriptor |
| TEMPST | `TemporaryDescriptors` | storage for the temporary string descriptors |
| NUMTMP | `TEMPORARY_COUNT` | number of temporary descriptors |
| STRSIZ | `DESCRIPTOR_SIZE` | a string descriptor's size (StringDescriptor .sizeof) |
| DSCTMP | `NewDescriptor` | where a temporary descriptor is built (alias of the FAC) |
| DSCPNT | `DescriptorPointer` | pointer to a string descriptor |
| STRNG1 | `StringPointer` | pointer to a string or descriptor |
| STRNG2 | `SecondStringPointer` | pointer to a second string or descriptor |
| FOUR6 | `CollectorStep` | the collector's step through descriptors (DESCRIPTOR_SIZE) |
| GRBPNT | `CollectorPointer` | scoped alias in the collector |
| GRBTOP | `CollectorTop` | scoped alias in the collector |
| LOWTR | `SourceStart` | general pointer: the low end of a block move's source; FindLine's result |
| HIGHTR | `SourceEnd` | general pointer: the high end of a block move's source |
| LOWDS | `DestinationStart` | general pointer: the low end of a block move's destination |
| HIGHDS | `DestinationEnd` | general pointer: the high end of a block move's destination |
| ARYPNT | `ArrayPointer` | alias of DestinationEnd, used in array building |
| INDEX1 | `Pointer1` | general pointer 1 (INDEX is its other name: one definition, Also: INDEX, INDEX1) |
| INDEX | `Pointer1` | see INDEX1 |
| INDEX2 | `Pointer2` | general pointer 2 |
| TRMPOS | `TerminalPosition` | output column |
| LINWID | `LineWidth` | terminal line width |
| NCMWID | `LastCommaColumn` | column beyond which a comma starts a new line |
| CLMWID | `ZONE_WIDTH` | width of a comma's print zone |
| LINLEN | `LINE_LENGTH` | the build's terminal line length |
| CNTWFL | `OutputSuppressed` | set to suppress output (Control-O) |
| CONTW | `SUPPRESS_OUTPUT_KEY` | the key that suppresses output |
| BUF | `InputBuffer` | the line input and tokenizing buffer |
| BUFLEN | `INPUT_BUFFER_LENGTH` | its length |
| BUFPAG | `INPUT_BUFFER_PAGE` | its page (build switch) |
| BUFPTR | `TokenizePointer` | alias: the tokenizer's pointer into InputBuffer |
| FAC | `Fac` | the floating-point accumulator, unpacked (see the cross-cutting question on FAC) |
| FACEXP | `FacExponent` | its exponent; the same byte as Fac |
| FACHO | `FacMantissa1` | its mantissa, most significant byte |
| FACMOH | `FacMantissa2` |  |
| FACMO | `FacMantissa3` |  |
| FACLO | `FacMantissa4` | least significant byte |
| FACSGN | `FacSign` |  |
| FACOV | `FacExtension` | the FAC's overflow (rounding) byte |
| ARGEXP | `ArgExponent` | the argument register, unpacked: its exponent (ARG is its other name) |
| ARGHO | `ArgMantissa1` |  |
| ARGMOH | `ArgMantissa2` |  |
| ARGMO | `ArgMantissa3` |  |
| ARGLO | `ArgMantissa4` |  |
| ARGSGN | `ArgSign` |  |
| ARISGN | `ResultSign` | the sign comparing Fac's and Arg's |
| RESHO | `Result1` | the multiplier's and divider's result, most significant byte |
| RESMOH | `Result2` |  |
| RESMO | `Result3` |  |
| RESLO | `Result4` |  |
| ADDEND | `Addend` | alias of Result3 used by the array-size multiplier |
| TEMPF1 | `FloatTemporary1` | packed float temporaries |
| TEMPF2 | `FloatTemporary2` |  |
| TEMPF3 | `FloatTemporary3` |  |
| RNDX | `RandomValue` | corrected in the merge |
| TANSGN | `TangentSign` |  |
| DOMASK | `RelationMask` | alias of TangentSign: the relation operators' mask |
| SGNFLG | `InputSign` | FIN's sign; (verify from code) |
| DEGREE | `PolynomialDegree` | alias of InputSign's byte |
| POLYPT | `PolynomialPointer` |  |
| EXPSGN | `ExponentSign` | FIN's sign of the decimal exponent (verify DPTFLG/TENEXP from code) |
| DPTFLG | `DecimalPointSeen` | verify from code: Microsoft's comments for DPTFLG and TENEXP may be swapped |
| TENEXP | `DecimalExponent` | verify from code |
| DECCNT | `DigitCount` | corrected in the merge |
| FDECPT | `PowerTablePointer` | FOUT's pointer into the powers of ten |
| FBUFFR | `NumberBuffer` | FOUT's output buffer |
| FBUFPT | `NumberBufferPointer` |  |
| LOFBUF | `NumberBufferPrefix` | the byte before NumberBuffer (verify from code) |
| CURTOL | `LinearIndex` | alias: an array element's linear index is formed here |
| INDICE | `ArrayIndex` | alias: QINT leaves the subscript here |
| OPMASK | `OperatorMask` | the relation mask of the current operator |
| OPPTR | `OperatorPointer` | pointer to the current operator's entry in OperatorTable |
| VARTXT | `VariableListPointer` | alias: READ/INPUT's pointer into the variable list |
| DEFPNT | `FunctionPointer` | pointer used in a DEF FN definition |
| JMPER | `FunctionJump` | a JMP the function dispatcher stores its target into |
| SIZE | `CollectorOffset` | alias: JMPER+1, the string collector's offset (W8) |
| OLDOV | `FunctionJumpHigh` | alias: JMPER+2, the unshifted operand's extension while adding (W8) |
| USRPOK | `UserVector` | the JMP that USR calls |
| KIMY | `SavedOutputY` | alias of Dimensioning; dropped, in Dimensioning's `Also:` (W3) |
| ANDMSK | `WaitAndMask` | WAIT's AND mask (alias of AssignedVariable) |
| EORMSK | `WaitXorMask` | WAIT's EOR mask |
| POKER | `PokeAddress` | alias of LineNumber: POKE's and WAIT's address |
| LSTPNT | `ListOffset` | corrected in the merge |
| NULCMD | `NULL_COMMAND` | build switch: the NULL command's storage |
| NUMLEV | `STACK_LEVELS` | the stack reserve in two-byte levels |
| STKEND | `STACK_END` | the build's upper stack limit |
| RAMLOC | `RAM_ORIGIN` | the build's RAM origin |
| ROMLOC | `ROM_ORIGIN` | the build's ROM origin |
| REALIO | `REALIO` | Microsoft's build target: kept (SDK option name used by the roots and tests; C# predefines it) |
