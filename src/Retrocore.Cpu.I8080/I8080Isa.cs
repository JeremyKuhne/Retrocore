// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The Intel 8080 and 8085 instruction-set description, read from <c>I8080Isa.txt</c>.
/// </summary>
/// <remarks>
///  <para>
///   The native syntax uses Intel's mnemonics and operands: <c>MOV A,M</c>, <c>MVI B,5</c>, <c>LXI H,Table</c>,
///   <c>PUSH PSW</c> and <c>RST 7</c>. The 8080's undocumented aliases of <c>NOP</c>, <c>JMP</c>, <c>RET</c> and
///   <c>CALL</c> and the 8085's undocumented instructions (<c>DSUB</c>, <c>ARHL</c>, <c>RDEL</c>, <c>LDHI</c>,
///   <c>LDSI</c>, <c>RSTV</c>, <c>SHLX</c>, <c>LHLX</c>, <c>JNK</c> and <c>JK</c>) are marked undocumented.
///  </para>
/// </remarks>
public static partial class I8080Isa
{
    /// <summary>
    ///  The name <c>.cpu</c> selects the 8080 with.
    /// </summary>
    public const string Name = "I8080";

    /// <summary>
    ///  The name <c>.cpu</c> selects the 8085 with.
    /// </summary>
    public const string Name8085 = "I8085";

    /// <summary>
    ///  Gets the description, parsed once on first use.
    /// </summary>
    public static IsaDescription Description => Parsed.Description;

    /// <summary>
    ///  Gets the 8080's instruction set.
    /// </summary>
    public static InstructionSet InstructionSet => Parsed.Set;

    /// <summary>
    ///  Gets the 8085's instruction set.
    /// </summary>
    public static InstructionSet InstructionSet8085 => Parsed.Set8085;

    /// <summary>
    ///  Gets the instruction set of a variant.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <returns>Its instruction set.</returns>
    public static InstructionSet Get(I8080Variant variant) => variant == I8080Variant.I8085 ? Parsed.Set8085 : Parsed.Set;
}
