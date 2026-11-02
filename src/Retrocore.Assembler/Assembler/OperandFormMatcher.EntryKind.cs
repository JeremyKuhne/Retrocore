// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class OperandFormMatcher
{
    /// <summary>
    ///  How a pattern matches an operand.
    /// </summary>
    private enum EntryKind : byte
    {
        /// <summary>
        ///  The operand is the literal text, and the mnemonic has the form.
        /// </summary>
        Literal,

        /// <summary>
        ///  Any operand, when the mnemonic has the form.
        /// </summary>
        Exclusive,

        /// <summary>
        ///  The operand has the pattern's syntax, whatever the mnemonic has.
        /// </summary>
        Syntax
    }
}
