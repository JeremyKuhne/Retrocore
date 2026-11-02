// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal partial struct LayoutStatement
{
    /// <summary>
    ///  Which optional values are present.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   One shared byte replaces the flag that each <see cref="Nullable{T}"/> field would otherwise pad to its
    ///   value's alignment.
    ///  </para>
    /// </remarks>
    [Flags]
    private enum LayoutValues : byte
    {
        /// <summary>
        ///  No optional value is present.
        /// </summary>
        None = 0,

        /// <summary>
        ///  The operand syntax allows a narrow (zero-page) alternative to the classified wide form.
        /// </summary>
        NarrowForm = 1,

        /// <summary>
        ///  The instruction has a resolved encoding.
        /// </summary>
        Encoding = 2,

        /// <summary>
        ///  The layout expression's value was fixed by its text alone.
        /// </summary>
        LiteralValue = 4,

        /// <summary>
        ///  A width prefix or suffix requires the absolute form of an address operand.
        /// </summary>
        ForcesAbsolute = 8,

        /// <summary>
        ///  A z: prefix requires zero-page addressing.
        /// </summary>
        ForcesZeroPage = 16,

        /// <summary>
        ///  Address width is fixed by the first layout pass.
        /// </summary>
        SourceOrder = 32,

        /// <summary>
        ///  The statement is in BSS or a dummy region.
        /// </summary>
        NoOutput = 64,

        /// <summary>
        ///  The statement belongs to a dummy region rather than BSS.
        /// </summary>
        IsDummy = 128
    }
}
