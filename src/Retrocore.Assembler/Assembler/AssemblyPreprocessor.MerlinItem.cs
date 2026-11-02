// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  How each item of a comma-separated Merlin operand is translated.
    /// </summary>
    private enum MerlinItem
    {
        /// <summary>
        ///  A symbol name, such as in ENT.
        /// </summary>
        Name,

        /// <summary>
        ///  A byte that keeps its low bits, with an optional &lt;, &gt; or ^ selector.
        /// </summary>
        Byte,

        /// <summary>
        ///  A full expression.
        /// </summary>
        Expression
    }
}
