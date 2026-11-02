// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The opcode table: each unprefixed opcode's group, worked out once from its x, y and z fields.
/// </summary>
internal static class Z80Decoding
{
    private const int MemoryOperand = 6;

    /// <summary>
    ///  Gets the group of each opcode.
    /// </summary>
    internal static byte[] Groups { get; } = [.. Enumerable.Range(0, 256).Select(opcode => (byte)Group(opcode))];

    // x = bits 6-7, y = bits 3-5, z = bits 0-2, p = y / 2, q = y % 2.
    private static Z80OpcodeGroup Group(int opcode)
    {
        int x = opcode >> 6;
        int y = (opcode >> 3) & 7;
        int z = opcode & 7;
        int p = y >> 1;
        int q = y & 1;
        switch (opcode)
        {
            case 0xCB:
                return Z80OpcodeGroup.Bits;
            case 0xED:
                return Z80OpcodeGroup.Extended;
            case 0xDD:
            case 0xFD:
                return Z80OpcodeGroup.IndexPrefix;
        }

        return x switch
        {
            0 => Low(y, z, p, q),
            1 when y == MemoryOperand && z == MemoryOperand => Z80OpcodeGroup.Halt,
            1 when z == MemoryOperand => Z80OpcodeGroup.LoadMemory,
            1 when y == MemoryOperand => Z80OpcodeGroup.StoreMemory,
            1 => Z80OpcodeGroup.LoadRegister,
            2 when z == MemoryOperand => Z80OpcodeGroup.ArithmeticMemory,
            2 => Z80OpcodeGroup.ArithmeticRegister,
            _ => High(y, z, p, q)
        };
    }

    private static Z80OpcodeGroup Low(int y, int z, int p, int q)
    {
        switch (z)
        {
            case 0:
                return y switch
                {
                    0 => Z80OpcodeGroup.Nop,
                    1 => Z80OpcodeGroup.ExchangeAF,
                    2 => Z80OpcodeGroup.DecrementJump,
                    _ => Z80OpcodeGroup.JumpRelative
                };
            case 1:
                return q == 0 ? Z80OpcodeGroup.LoadPairImmediate : Z80OpcodeGroup.AddPair;
            case 2:
                return ((q << 2) | p) switch
                {
                    0 or 1 => Z80OpcodeGroup.StoreIndirect,
                    2 => Z80OpcodeGroup.StorePairAbsolute,
                    3 => Z80OpcodeGroup.StoreAbsolute,
                    4 or 5 => Z80OpcodeGroup.LoadIndirect,
                    6 => Z80OpcodeGroup.LoadPairAbsolute,
                    _ => Z80OpcodeGroup.LoadAbsolute
                };
            case 3:
                return Z80OpcodeGroup.StepPair;
            case 4:
            case 5:
                return y == MemoryOperand ? Z80OpcodeGroup.StepMemory : Z80OpcodeGroup.StepRegister;
            case 6:
                return y == MemoryOperand ? Z80OpcodeGroup.StoreImmediate : Z80OpcodeGroup.LoadImmediate;
            default:
                return Z80OpcodeGroup.Accumulator;
        }
    }

    private static Z80OpcodeGroup High(int y, int z, int p, int q)
    {
        switch (z)
        {
            case 0:
                return Z80OpcodeGroup.ReturnConditional;
            case 1:
                if (q == 0) { return Z80OpcodeGroup.Pop; }
                return p switch
                {
                    0 => Z80OpcodeGroup.Return,
                    1 => Z80OpcodeGroup.ExchangeAll,
                    2 => Z80OpcodeGroup.JumpIndex,
                    _ => Z80OpcodeGroup.LoadStackIndex
                };
            case 2:
                return Z80OpcodeGroup.JumpConditional;
            case 3:
                return y switch
                {
                    0 => Z80OpcodeGroup.Jump,
                    2 => Z80OpcodeGroup.OutputImmediate,
                    3 => Z80OpcodeGroup.InputImmediate,
                    4 => Z80OpcodeGroup.ExchangeStack,
                    5 => Z80OpcodeGroup.ExchangeDEHL,
                    6 => Z80OpcodeGroup.DisableInterrupts,
                    _ => Z80OpcodeGroup.EnableInterrupts
                };
            case 4:
                return Z80OpcodeGroup.CallConditional;
            case 5:
                return q == 0 ? Z80OpcodeGroup.Push : Z80OpcodeGroup.Call;
            case 6:
                return Z80OpcodeGroup.ArithmeticImmediate;
            default:
                return Z80OpcodeGroup.Restart;
        }
    }
}
