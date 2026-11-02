// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  One opcode line of an instruction-set section, before its names are resolved.
/// </summary>
/// <param name="Opcode">The opcode bytes, first byte in the low eight bits.</param>
/// <param name="Length">The number of opcode bytes.</param>
/// <param name="Instruction">The instruction name, without a bit suffix.</param>
/// <param name="Form">The operand form name.</param>
/// <param name="Undocumented">Whether the encoding is undocumented.</param>
/// <param name="SplitAt">The number of opcode bytes before the operand bytes, or 0 when they follow the opcode.</param>
internal readonly record struct IsaEntry(uint Opcode, byte Length, string Instruction, string Form, bool Undocumented, byte SplitAt = 0)
{
    /// <summary>
    ///  Gets the nominal clock cycles, or for a conditional instruction those when it is not taken; 0 when the
    ///  description gives none.
    /// </summary>
    internal byte Cycles { get; init; }

    /// <summary>
    ///  Gets the nominal clock cycles of a conditional instruction when it is taken.
    /// </summary>
    internal byte CyclesTaken { get; init; }
}
