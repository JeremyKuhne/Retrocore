// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.Z80;

public sealed partial class Z80Processor<TBus> : ICpuDebugView
{
    /// <inheritdoc/>
    InstructionSet ICpuDebugView.InstructionSet => Z80Isa.InstructionSet;

    /// <inheritdoc/>
    ushort ICpuDebugView.ProgramCounter => _state.Registers.PC;

    /// <inheritdoc/>
    ushort ICpuDebugView.StackAddress => _state.Registers.SP;

    /// <inheritdoc/>
    bool ICpuDebugView.TryGetRegister(string name, out int value)
    {
        Z80Registers r = _state.Registers;
        int? result = name.ToUpperInvariant() switch
        {
            "A" => r.A,
            "F" => r.F,
            "B" => r.B,
            "C" => r.C,
            "D" => r.D,
            "E" => r.E,
            "H" => r.H,
            "L" => r.L,
            "I" => r.I,
            "R" => r.R,
            "AF" => r.AF,
            "BC" => r.BC,
            "DE" => r.DE,
            "HL" => r.HL,
            "IX" => r.IX,
            "IY" => r.IY,
            "SP" => r.SP,
            "PC" => r.PC,
            "AF'" => r.AlternateAF,
            "BC'" => r.AlternateBC,
            "DE'" => r.AlternateDE,
            "HL'" => r.AlternateHL,
            _ => null
        };

        value = result.GetValueOrDefault();
        return result.HasValue;
    }

    /// <inheritdoc/>
    bool ICpuDebugView.TrySetRegister(string name, int value)
    {
        string register = name.ToUpperInvariant();
        bool wide = register.Length > 1;
        Z80Registers r = _state.Registers;
        ArgumentOutOfRangeException.ThrowIfNegative(value);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(value, wide ? ushort.MaxValue : byte.MaxValue);
        byte low = (byte)value;
        ushort word = (ushort)value;
        switch (register)
        {
            case "A": r.A = low;
                break;
            case "F": r.F = low;
                break;
            case "B": r.B = low;
                break;
            case "C": r.C = low;
                break;
            case "D": r.D = low;
                break;
            case "E": r.E = low;
                break;
            case "H": r.H = low;
                break;
            case "L": r.L = low;
                break;
            case "I": r.I = low;
                break;
            case "R": r.R = low;
                break;
            case "AF": r.AF = word;
                break;
            case "BC": r.BC = word;
                break;
            case "DE": r.DE = word;
                break;
            case "HL": r.HL = word;
                break;
            case "IX": r.IX = word;
                break;
            case "IY": r.IY = word;
                break;
            case "SP": r.SP = word;
                break;
            case "PC": r.PC = word;
                break;
            case "AF'": r.AlternateAF = word;
                break;
            case "BC'": r.AlternateBC = word;
                break;
            case "DE'": r.AlternateDE = word;
                break;
            case "HL'": r.AlternateHL = word;
                break;
            default:
                return false;
        }

        Registers = r;
        return true;
    }
}
