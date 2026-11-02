// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

public sealed partial class Z80Processor<TBus>
{
    // Schedules the next machine cycle of the instruction.
    private void Read(ushort address)
    {
        _state.Cycle = Z80MachineCycle.Read;
        _state.Address = address;
        _state.T = 0;
    }

    private void Write(ushort address, byte value)
    {
        _state.Cycle = Z80MachineCycle.Write;
        _state.Address = address;
        _state.Value = value;
        _state.T = 0;
    }

    private void Input(ushort port)
    {
        _state.Cycle = Z80MachineCycle.InputRead;
        _state.Address = port;
        _state.T = 0;
    }

    private void Output(ushort port, byte value)
    {
        _state.Cycle = Z80MachineCycle.OutputWrite;
        _state.Address = port;
        _state.Value = value;
        _state.T = 0;
    }

    private void Internal(byte length)
    {
        _state.Cycle = Z80MachineCycle.Internal;
        _state.Length = length;
        _state.T = 0;
    }

    private void Fetch()
    {
        _state.Cycle = Z80MachineCycle.Fetch;
        _state.T = 0;
    }

    // Reads the byte at PC and advances PC, as operand reads do.
    private void ReadOperand() => Read(_state.Registers.PC++);

    // Ends the instruction: Q keeps the flags it wrote, or zero.
    private void Finish()
    {
        _state.Registers.Q = _state.FlagsWritten ? _state.Registers.F : (byte)0;
        _state.Operation = Z80Operation.None;
        _state.Step = 0;
    }

    // Continues the instruction once its machine cycle ends, choosing the next or finishing.
    private void Continue()
    {
        switch (_state.Operation)
        {
            case Z80Operation.Decode:
                Decode(_state.Value);
                break;
            case Z80Operation.DecodeBits:
                DecodeBits(_state.Value);
                break;
            case Z80Operation.DecodeExtended:
                DecodeExtended(_state.Value);
                break;
            default:
                Execute();
                break;
        }
    }
}
