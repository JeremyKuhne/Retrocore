// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.I8080;

public sealed partial class I8080Processor<TBus> : ICpuDebugView
{
    /// <inheritdoc/>
    InstructionSet ICpuDebugView.InstructionSet => I8080Isa.Get(_state.Variant);

    /// <inheritdoc/>
    ushort ICpuDebugView.ProgramCounter => _state.Registers.PC;

    /// <inheritdoc/>
    ushort ICpuDebugView.StackAddress => _state.Registers.SP;

    /// <inheritdoc/>
    bool ICpuDebugView.TryGetRegister(string name, out int value)
    {
        I8080Registers r = _state.Registers;
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
            "BC" => r.BC,
            "DE" => r.DE,
            "HL" => r.HL,
            "PSW" => r.PSW,
            "SP" => r.SP,
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
        bool wide = register.Length > 1;
        I8080Registers r = _state.Registers;
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
            case "BC": r.BC = word;
                break;
            case "DE": r.DE = word;
                break;
            case "HL": r.HL = word;
                break;
            case "PSW": r.PSW = word;
                break;
            case "SP": r.SP = word;
                break;
            case "PC": r.PC = word;
                break;
            default:
                return false;
        }

        Registers = r;
        return true;
    }
}
