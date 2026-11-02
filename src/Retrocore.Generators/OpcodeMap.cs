// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Generators;

/// <summary>
///  Build-time state for one symbolic opcode section, including inherited and locally overridden entries.
/// </summary>
internal sealed class OpcodeMap
{
    /// <summary>
    ///  Creates a map associated with a definition-file section.
    /// </summary>
    /// <param name="line">The zero-based section-header line.</param>
    internal OpcodeMap(int line) => Line = line;

    /// <summary>
    ///  Gets the section-header line for diagnostics.
    /// </summary>
    internal int Line { get; }

    /// <summary>
    ///  Gets the packed code, addressing-mode, and instruction bytes.
    /// </summary>
    internal byte[] Data { get; } = new byte[InstructionEncoding.OpcodeCount * InstructionEncoding.PackedOpcodeSize];

    /// <summary>
    ///  Gets flags indicating which opcodes have definitions, including inherited entries.
    /// </summary>
    internal bool[] Defined { get; } = new bool[InstructionEncoding.OpcodeCount];

    /// <summary>
    ///  Gets flags indicating which opcodes were explicitly defined in this section.
    /// </summary>
    internal bool[] Overridden { get; } = new bool[InstructionEncoding.OpcodeCount];
}
