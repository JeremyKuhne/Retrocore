// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6809;

/// <summary>
///  The Motorola MC6809's instruction-set description, read from <c>M6809Isa.txt</c>.
/// </summary>
/// <remarks>
///  <para>
///   The native syntax uses Motorola's mnemonics with <c>#</c> immediates, <c>&lt;</c> and <c>&gt;</c> width
///   forcing for direct-page versus extended and indexed offsets, and brackets for indirection such as
///   <c>LDA [,X]</c>, <c>LDA [$1234,Y]</c> and <c>JMP [$FFFE]</c>, so parentheses always group expressions.
///  </para>
/// </remarks>
public static partial class M6809Isa
{
    /// <summary>
    ///  The name <c>.cpu</c> selects the MC6809 with.
    /// </summary>
    public const string Name = "M6809";

    /// <summary>
    ///  Gets the description, parsed once on first use.
    /// </summary>
    public static IsaDescription Description => Parsed.Description;

    /// <summary>
    ///  Gets the MC6809's instruction set.
    /// </summary>
    public static InstructionSet InstructionSet => Parsed.Set;
}
