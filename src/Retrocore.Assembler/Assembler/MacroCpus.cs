// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The CPUs a source writes only with macros: their instruction sets have no instructions, and a macro defined
///  while one's <c>.cpu</c> is in effect expands only while it is in effect again.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal's p-code is one: <c>Pcode.asm</c> defines a macro for each p-code under <c>.cpu Pcode</c>, so
///   p-code's <c>LDA</c>, <c>INC</c>, <c>NOP</c> and <c>STP</c> never take the place of the 6502's in an assembled
///   procedure written under <c>.cpu Mos6502</c> in the same file.
///  </para>
/// </remarks>
internal static class MacroCpus
{
    /// <summary>
    ///  Apple Pascal's p-code.
    /// </summary>
    internal const string Pcode = "Pcode";

    /// <summary>
    ///  Tests whether a <c>.cpu</c> name is a macro-only CPU's.
    /// </summary>
    /// <param name="name">The name, in any case; null before any <c>.cpu</c>.</param>
    /// <returns>Whether macros defined under it belong to it.</returns>
    internal static bool Contains(string? name) => string.Equals(name, Pcode, StringComparison.OrdinalIgnoreCase);
}
