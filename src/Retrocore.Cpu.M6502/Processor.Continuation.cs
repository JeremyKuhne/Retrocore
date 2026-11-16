// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

public sealed partial class Processor<TBus> where TBus : IProcessorBus
{
    private static ProcessorContinuation GetContinuation(OpCode opcode) => opcode.Instruction switch
    {
        Instruction.JMP => ProcessorContinuation.Jump,
        Instruction.JSR => ProcessorContinuation.Jsr,
        Instruction.RTS or Instruction.RTI => ProcessorContinuation.Return,
        Instruction.BRK => ProcessorContinuation.Brk,
        Instruction.PHA or Instruction.PHP or Instruction.PHX or Instruction.PHY => ProcessorContinuation.Push,
        Instruction.PLA or Instruction.PLP or Instruction.PLX or Instruction.PLY => ProcessorContinuation.Pull,
        Instruction.WAI or Instruction.STP or Instruction.JAM => ProcessorContinuation.Halt,
        _ => opcode.AddressMode switch
        {
            AddressMode.Immediate => ProcessorContinuation.Immediate,
            AddressMode.ZeroPage => ProcessorContinuation.ZeroPageAddress,
            AddressMode.ZeroPageIndexedX or AddressMode.ZeroPageIndexedY => ProcessorContinuation.IndexedZeroPageAddress,
            AddressMode.Absolute or AddressMode.AbsoluteIndexedX or AddressMode.AbsoluteIndexedY => ProcessorContinuation.AbsoluteLow,
            AddressMode.ZeroPageIndexedIndirect => ProcessorContinuation.IndexedIndirectPointer,
            AddressMode.ZeroPageIndirect or AddressMode.ZeroPageIndirectIndexedY => ProcessorContinuation.IndirectPointer,
            AddressMode.ProgramCounterRelative or AddressMode.ZeroPageRelative => ProcessorContinuation.Branch,
            AddressMode.Accumulator when opcode.Instruction is Instruction.ASL or Instruction.ROL or Instruction.LSR or Instruction.ROR =>
                ProcessorContinuation.Accumulator,
            AddressMode.Implied or AddressMode.Accumulator => ProcessorContinuation.Implied,
            _ => throw new InvalidOperationException("Invalid instruction addressing mode.")
        }
    };

    private void AdvanceContinuation()
    {
        ProcessorContinuation step = _state.Continuation;
        switch (step)
        {
            case ProcessorContinuation.Immediate:
                _state.Address = _state.Registers.ProgramCounter;
                FinishRead(Read(_state.Registers.ProgramCounter++));
                break;
            case ProcessorContinuation.ZeroPageAddress:
            case ProcessorContinuation.IndexedZeroPageAddress:
                _state.Continuation = step + 1;
                _state.Address = Read(_state.Registers.ProgramCounter++);
                break;
            case ProcessorContinuation.IndexedZeroPageDummy:
                _state.Continuation = ProcessorContinuation.IndexedZeroPageData;
                Read(_state.Address);
                byte index = _state.Instruction.AddressMode == AddressMode.ZeroPageIndexedX
                    ? _state.Registers.X : _state.Registers.Y;

                _state.Address = (byte)(_state.Address + index);
                break;
            case ProcessorContinuation.AbsoluteLow:
                _state.Continuation = ProcessorContinuation.AbsoluteHigh;
                _state.Data = Read(_state.Registers.ProgramCounter++);
                break;
            case ProcessorContinuation.AbsoluteHigh:
                _state.Continuation = ProcessorContinuation.AbsoluteData;
                _state.BaseAddress = (ushort)(_state.Data | (Read(_state.Registers.ProgramCounter++) << 8));
                _state.Address = _state.BaseAddress;
                if (_state.Instruction.AddressMode != AddressMode.Absolute)
                {
                    _state.Address += _state.Instruction.AddressMode == AddressMode.AbsoluteIndexedX
                        ? _state.Registers.X : _state.Registers.Y;
                }

                break;
            case ProcessorContinuation.AbsoluteData:
                if (Variant != ProcessorVariant.Mos6502 && _state.Instruction.Instruction == Instruction.NOP)
                {
                    Read((ushort)(_state.Registers.ProgramCounter - 1));
                    Complete();
                }
                else if (_state.Instruction.AddressMode != AddressMode.Absolute && IndexedExtra)
                {
                    _state.Continuation = ProcessorContinuation.AbsoluteIndexedData;
                    Read(IndexedDummyAddress);
                }
                else
                {
                    AccessData();
                }

                break;
            case ProcessorContinuation.IndexedIndirectPointer:
            case ProcessorContinuation.IndirectPointer:
                _state.Continuation = step + 1;
                _state.Pointer = Read(_state.Registers.ProgramCounter++);
                break;
            case ProcessorContinuation.IndexedIndirectDummy:
                _state.Continuation = ProcessorContinuation.IndexedIndirectLow;
                Read(_state.Pointer);
                _state.Pointer += _state.Registers.X;
                break;
            case ProcessorContinuation.IndexedIndirectLow:
            case ProcessorContinuation.IndirectLow:
                _state.Continuation = step + 1;
                _state.Data = Read(_state.Pointer);
                break;
            case ProcessorContinuation.IndexedIndirectHigh:
                _state.Continuation = ProcessorContinuation.IndexedIndirectData;
                _state.Address = (ushort)(_state.Data | (Read((byte)(_state.Pointer + 1)) << 8));
                break;
            case ProcessorContinuation.IndirectHigh:
                _state.Continuation = ProcessorContinuation.IndirectData;
                _state.BaseAddress = (ushort)(_state.Data | (Read((byte)(_state.Pointer + 1)) << 8));
                _state.Address = _state.BaseAddress;
                if (_state.Instruction.AddressMode == AddressMode.ZeroPageIndirectIndexedY)
                {
                    _state.Address += _state.Registers.Y;
                }

                break;
            case ProcessorContinuation.IndirectData:
                if (_state.Instruction.AddressMode == AddressMode.ZeroPageIndirectIndexedY && IndexedExtra)
                {
                    _state.Continuation = ProcessorContinuation.IndirectIndexedData;
                    Read(IndexedDummyAddress);
                }
                else
                {
                    AccessData();
                }

                break;
            case ProcessorContinuation.ZeroPageData:
            case ProcessorContinuation.IndexedZeroPageData:
            case ProcessorContinuation.AbsoluteIndexedData:
            case ProcessorContinuation.IndexedIndirectData:
            case ProcessorContinuation.IndirectIndexedData:
                AccessData();
                break;
            case ProcessorContinuation.Halt:
                AdvanceHalt();
                break;
            case ProcessorContinuation.Data:
                AdvanceData();
                break;
            case ProcessorContinuation.Branch:
                AdvanceBranch();
                break;
            case ProcessorContinuation.Accumulator:
                Read(_state.Registers.ProgramCounter);
                _state.Registers.Accumulator = Modify(_state.Registers.Accumulator);
                Complete();
                break;
            case ProcessorContinuation.Jump:
                AdvanceJump();
                break;
            case ProcessorContinuation.Jsr:
                AdvanceJsr();
                break;
            case ProcessorContinuation.Return:
                AdvanceReturn(_state.Instruction.Instruction == Instruction.RTI);
                break;
            case ProcessorContinuation.Brk:
                AdvanceBrk();
                break;
            case ProcessorContinuation.Push:
                AdvancePush();
                break;
            case ProcessorContinuation.Pull:
                AdvancePull(_state.Instruction.Instruction);
                break;
            case ProcessorContinuation.Implied:
                Read(_state.Registers.ProgramCounter);
                ExecuteImplied(_state.Instruction.Instruction);
                Complete();
                break;
            default:
                throw new InvalidOperationException("Invalid CPU continuation.");
        }
    }
}
