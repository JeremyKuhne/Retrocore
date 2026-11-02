// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The Z80's instruction-set description, read from <c>Z80Isa.txt</c>.
/// </summary>
/// <remarks>
///  <para>
///   The native syntax uses Zilog's mnemonics with memory operands in brackets, such as <c>LD A,[HL]</c> and
///   <c>LD [IX+5],A</c>, so parentheses always group an expression. The undocumented instructions (the
///   <c>IXH</c>-style halves, <c>SLL</c>, the <c>DD CB</c> register copies, <c>IN [C]</c>, <c>OUT [C],0</c> and
///   the prefix and <c>ED</c> aliases) assemble as written and are marked undocumented.
///  </para>
/// </remarks>
public static partial class Z80Isa
{
    /// <summary>
    ///  The name <c>.cpu</c> selects the Z80 with.
    /// </summary>
    public const string Name = "Z80";

    /// <summary>
    ///  Gets the description, parsed once on first use.
    /// </summary>
    public static IsaDescription Description => Parsed.Description;

    /// <summary>
    ///  Gets the Z80's instruction set.
    /// </summary>
    public static InstructionSet InstructionSet => Parsed.Set;
}
