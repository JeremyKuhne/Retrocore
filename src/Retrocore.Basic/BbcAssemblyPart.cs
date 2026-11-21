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
    ///  What the assembler skips to the end of the statement: a comment, or anything after the operand.
    /// </summary>
    Skipped
}
