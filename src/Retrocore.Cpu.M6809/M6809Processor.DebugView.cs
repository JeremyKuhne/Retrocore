// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6809;

public sealed partial class M6809Processor<TBus> : ICpuDebugView
{
    /// <inheritdoc/>
    InstructionSet ICpuDebugView.InstructionSet => M6809Isa.InstructionSet;

    /// <inheritdoc/>
    ushort ICpuDebugView.ProgramCounter => _state.Registers.PC;

    /// <inheritdoc/>
    ushort ICpuDebugView.StackAddress => _state.Registers.S;

    /// <inheritdoc/>
    bool ICpuDebugView.TryGetRegister(string name, out int value)
    {
        M6809Registers r = _state.Registers;
        int? result = name.ToUpperInvariant() switch
        {
            "A" => r.A,
            "B" => r.B,
            "D" => r.D,
            "X" => r.X,
            "Y" => r.Y,
            "U" => r.U,
            "S" => r.S,
            "DP" => r.DP,
            "CC" => r.CC,
            "PC" => r.PC,
            _ => null
        };

        value = result.GetValueOrDefault();
        return result.HasValue;
    }

    /// <inheritdoc/>
    bool ICpuDebugView.TrySetRegister(string name, int value)
    {
        string register = name.ToUpperInvariant();
        if (register is not ("A" or "B" or "D" or "X" or "Y" or "U" or "S" or "DP" or "CC" or "PC"))
        {
            return false;
        }

        bool wide = register is "D" or "X" or "Y" or "U" or "S" or "PC";
        ArgumentOutOfRangeException.ThrowIfNegative(value);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(value, wide ? ushort.MaxValue : byte.MaxValue);

        M6809Registers r = _state.Registers;
        switch (register)
        {
            case "A":
                r.A = (byte)value;
                break;
            case "B":
                r.B = (byte)value;
                break;
            case "D":
                r.D = (ushort)value;
                break;
            case "X":
                r.X = (ushort)value;
                break;
            case "Y":
                r.Y = (ushort)value;
                break;
            case "U":
                r.U = (ushort)value;
                break;
            case "S":
                r.S = (ushort)value;
                r.NmiArmed = true;
                break;
            case "DP":
                r.DP = (byte)value;
                break;
            case "CC":
                r.CC = (byte)value;
                break;
            default:
                r.PC = (ushort)value;
                break;
        }

        Registers = r;
        return true;
    }
}
