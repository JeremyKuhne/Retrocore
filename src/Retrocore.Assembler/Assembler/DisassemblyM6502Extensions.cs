// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Assembler;

/// <summary>
///  6502 family views of decoded instructions, for tools that work with the 6502's own enums.
/// </summary>
public static class DisassemblyM6502Extensions
{
    /// <param name="instruction">A 6502 family instruction.</param>
    extension(DisassembledInstruction instruction)
    {
        /// <summary>
        ///  Gets the 6502 core's opcode metadata.
        /// </summary>
        /// <exception cref="ArgumentException">The instruction is not from a 6502 family set.</exception>
        public OpCode OpCode => OpcodeTable.Get(M6502Isa.VariantOf(instruction.InstructionSet))[instruction.GetByte(0)];
    }
}
