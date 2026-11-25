# The Apple II character generators: conversion log

`src/Retrocore.Machines.Apple2/Roms/System/CharacterGenerator.asm`: the IIe's 4 KiB video ROM (342-0133 in the
original IIe, 342-0265 in the Enhanced IIe) and the II and II Plus's 2 KiB character generator (7341-0036). Documents
cited: none. Glyph data, not code.

## Builds and switches

| Build | `IIBOARD` | `ENHANCED` | Digest |
| --- | --- | --- | --- |
| II and II Plus (7341-0036, 2 KiB) | 1 | (asserted, unused) | `Apple2SourceTests` |
| Original IIe (342-0133, 4 KiB) | 0 | 0 | `SystemSourceTests` |
| Enhanced IIe (342-0265, 4 KiB) | 0 | 1 (default) | `SystemSourceTests` |

- `IIBOARD` selects the II's chip; for the IIe, `ENHANCED` puts MouseText at $40-$5F instead of a second inverse
  uppercase set. The source asserts each is 0 or 1.

## Decisions

- G1. No historical names. Every name the source defines is the SDK's own (the glyph macros, the drawing state, the
  build switches): no manual or listing names the parts of a character generator, which Apple shipped as a mask ROM
  with no source. So no `Also:` and no bibliography keys; the chips' part numbers stay in prose.
- G2. The build switches `IIBOARD` and `ENHANCED`, which C# predefines (`SdkModules.AssembleSystem`), are unchanged,
  as DOS's `MASTER` and `YEAR` were ([Dos.md](Dos.md), X13).
- G3. The macros are PascalCase: `GLYPH` is `Glyph` and `ROW` is `Row`. The set macros are named for what they draw,
  with `Glyphs` appended: `UppercaseGlyphs`, `SymbolGlyphs`, `LowercaseGlyphs`, and `MouseTextGlyphs` for the
  Enhanced IIe's set, which was written inline before. `MouseText` alone would be a definition the IIe firmware's
  prose names as a plain word throughout, and the lint would ask it to be linked there.
- G4. The drawing state's `.set` variables: `Row` (the row being drawn) is `GlyphRow`, clear of the `Row` macro; `Lit`
  is `Dots`; `Flash` is `HighBit`, which now holds the bit's value ($00 or $80) rather than 0 or 1, since the II's codes
  $C0-$FF set it and are not flashing; `Low` and `High` are `LowNibble` and `HighNibble`; the table's `.repeat` counter
  `Value` is `value`, lower case as most converted sources' counters are. `Inverse` stays.
- G5. Named constants: `GLYPH_SIZE` (8), `GLYPHS_PER_SET` (32), `DOTS_PER_ROW` (7), `DOT_BITS` ($7F) and `HIGH_BIT`
  ($80). The byte table's nibble arithmetic (`* $11`, the rotation by two) and the complements (`Row`'s `^ $FF`, the
  table's `~ ... & $FF` and `~value & DOT_BITS`) stay inline, explained in comments.
- G6. `Row`'s seven dots are gathered with a `.repeat` over the columns instead of one 230-column expression per
  chip; the bytes are the same.
- G7. No `.proc` or scope: there are no routines, and the macros are the only structure. The file's layout at the
  end, set by set, stays at top level under the build `.if`s.
- G8. The title's `II PLUS` is excluded from `unlinked-name` for the file (`ignore=unlinked-name:PLUS`): the all-caps
  title names the machine, not the documented `PLUS` elsewhere in the workspace.

## Checks

- Byte identity of all three builds: the digests named above.
- No contract run: the chips are data the video circuit reads, with no code for the debugger to execute. The glyphs
  are checked by the digests, and against the chips' dumps where those are present.
