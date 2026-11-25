// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Where BBC BASIC's assembler is in one of its statements, as a line is scanned.
/// </summary>
internal enum BbcAssemblyPart
{
    /// <summary>
    ///  Where a statement starts: a label, a mnemonic, a <c>\</c> comment or the <c>]</c> that ends the assembler.
    /// </summary>
    Statement,

    /// <summary>
    ///  In an operand, whose names are BASIC's.
    /// </summary>
    Operand,

    /// <summary>
    ///  Where the operand of <c>ASL</c>, <c>LSR</c>, <c>ROL</c> or <c>ROR</c> starts, where <c>A</c> is the
    ///  accumulator.
    /// </summary>
    ShiftOperand,

    /// <summary>
    ///  After a comma in an operand, where <c>X</c> and <c>Y</c> are the index registers.
    /// </summary>
    Register,

    /// <summary>
    ///  In the operand of <c>LDX</c>, <c>LDY</c>, <c>STX</c> or <c>STY</c>, whose names are BASIC's.
    /// </summary>
    IndexOperand,

    /// <summary>
    ///  After a comma in the operand of <c>LDX</c>, <c>LDY</c>, <c>STX</c> or <c>STY</c>, which compare the index
    ///  register by its low five bits, so <c>x</c> and <c>y</c> are registers too.
    /// </summary>
    IndexRegister,

    /// <summary>
    ///  What the assembler skips to the end of the statement: a <c>\</c> comment, everything after an implied
    ///  instruction, an index register or the shifts' <c>A</c>, and a <c>\</c> or <c>;</c> after an operand. The
    ///  scanner cannot tell where an operand's expression ends, so other text after it is still read as BASIC.
    /// </summary>
    Skipped
}
