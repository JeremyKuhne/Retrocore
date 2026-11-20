# Microsoft 6502 BASIC

`m6502.asm` is Microsoft's BASIC 1.1 6502 source from
[microsoft/BASIC-M6502](https://github.com/microsoft/BASIC-M6502), retained unchanged. Its SHA-256 is
`F3EC99C91DEDB8EB3441DED866F45797BB3E03ED26567A253E24CECF23CD63AC`.
The original MIT `LICENSE` is kept beside the source.

The AppleSoft and Commodore PET MACRO-10 overlays refer to this shared base. Apple's native `AppleSoft.asm`
includes the floating-point routines from the `MsBasic.*.asm` modules here; the Apple-specific startup, I/O,
graphics and command code remains under `AppleSoft`.

`MsBasic.FloatConstants.asm` defines macros for the five-byte `ADDPRC=1` constants and polynomial tables shared
by AppleSoft and all three PET BASIC versions. A native variant can emit each block where its ROM needs it.
`MsBasic.AdditionCore.asm` supplies addition, normalization and shifting. `MsBasic.Logarithm.asm` provides the
shared `LOG` routine, which must immediately precede `FMULT` because it falls through to that routine.
`MsBasic.ArithmeticCore.asm` supplies multiplication and division,
including the short zero-result branch used by PET BASIC 1; `MsBasic.MovementCore.asm` supplies the movement and
rounding routines. `MsBasic.ConversionCore.asm` supplies sign, comparison and integer conversion;
`MsBasic.DecimalInputCore.asm` supplies decimal input with either exponent limit;
`MsBasic.OutputCore.asm` supplies decimal output with either positive-sign convention; and
`MsBasic.TranscendentalCore.asm` provides power, exponential, polynomial evaluation and trigonometric routines.
`MsBasic.RandomCore.asm` provides the random-number generator, including the PET timer-seeding variant.

The [Commodore floating-point module](../../../Retrocore.Machines.Commodore/Roms/Basic/Commodore.FloatingPoint.asm)
composes these macros in PET ROM order, including BASIC 2's WAIT message and BASIC 4's checksum and padding. Its
caller supplies the external symbols and puts this directory on the include path. Tests compare the complete
`FADDH`-to-`INITAT` region, including its editor-ROM spill, against all five PET overlay builds.

The PET BASIC 1 (both revisions), 2 and 4 (both revisions) builds still use their MACRO-10 overlays. Their native
roots and the rest of the shared interpreter have not yet been ported, so PET continues to use its existing
overlay path; no native PET selection is offered until those roots exist.
