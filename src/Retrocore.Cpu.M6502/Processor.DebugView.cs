// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6502;

public sealed partial class Processor<TBus> : ICpuDebugView
{
    private const ushort StackPage = 0x0100;

    /// <inheritdoc/>
    InstructionSet ICpuDebugView.InstructionSet => M6502Isa.Get(Variant);

    /// <inheritdoc/>
    ushort ICpuDebugView.ProgramCounter => _state.Registers.ProgramCounter;

    /// <inheritdoc/>
    ushort ICpuDebugView.StackAddress => (ushort)(StackPage | _state.Registers.StackPointer);

    /// <inheritdoc/>
    bool ICpuDebugView.TryGetRegister(string name, out int value)
    {
        ProcessorRegisters registers = _state.Registers;
        int? result = name.ToUpperInvariant() switch
        {
            "A" => registers.Accumulator,
            "X" => registers.X,
            "Y" => registers.Y,
            "S" => registers.StackPointer,
            "P" => (byte)registers.Status,
            "PC" => registers.ProgramCounter,
            _ => null
        };

        value = result.GetValueOrDefault();
        return result.HasValue;
    }

    /// <inheritdoc/>
    bool ICpuDebugView.TrySetRegister(string name, int value)
    {
        string register = name.ToUpperInvariant();
        int maximum = register == "PC" ? ushort.MaxValue : byte.MaxValue;
        if (register is not ("A" or "X" or "Y" or "S" or "P" or "PC")) { return false; }
        ArgumentOutOfRangeException.ThrowIfNegative(value);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(value, maximum);

        ProcessorRegisters registers = _state.Registers;
        switch (register)
        {
            case "A": registers.Accumulator = (byte)value;
                break;
            case "X": registers.X = (byte)value;
                break;
            case "Y": registers.Y = (byte)value;
                break;
            case "S": registers.StackPointer = (byte)value;
                break;
            case "P": registers.Status = (StatusRegister)value;
                break;
            default: registers.ProgramCounter = (ushort)value;
                break;
        }

        // The public setter checks the instruction boundary and keeps the unused status bit set.
        Registers = registers;
        return true;
    }
}
