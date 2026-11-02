// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Cpu.M6502;

public sealed partial class Processor<TBus> where TBus : IProcessorBus
{
    private bool IsStore => _state.Instruction.Instruction is
        Instruction.STA
            or Instruction.STX
            or Instruction.STY
            or Instruction.STZ
            or Instruction.SAX
            or Instruction.AHX
            or Instruction.SHX
            or Instruction.SHY
            or Instruction.TAS;

    private bool IsModify => _state.Instruction.Instruction is
        Instruction.ASL
            or Instruction.LSR
            or Instruction.ROL
            or Instruction.ROR
            or Instruction.INC
            or Instruction.DEC
            or Instruction.SLO
            or Instruction.SRE
            or Instruction.RLA
            or Instruction.RRA
            or Instruction.DCP
            or Instruction.ISC
            or Instruction.TSB
            or Instruction.TRB
            or Instruction.RMB
            or Instruction.SMB;

    private bool IndexedExtra =>
        (_state.Address & 0xFF00) != (_state.BaseAddress & 0xFF00)
            || IsStore
            || (IsModify && (Variant == ProcessorVariant.Mos6502
                || _state.Instruction.Instruction is Instruction.INC or Instruction.DEC));

    private ushort IndexedDummyAddress => Variant == ProcessorVariant.Mos6502
        ? (ushort)((_state.BaseAddress & 0xFF00) | (_state.Address & 0xFF))
        : (ushort)(_state.Registers.ProgramCounter - 1);

    private void AdvanceMemory()
    {
        switch (_state.Instruction.AddressMode)
        {
            case AddressMode.Immediate:
                _state.Address = _state.Registers.ProgramCounter;
                FinishRead(Read(_state.Registers.ProgramCounter++));
                break;
            case AddressMode.ZeroPage:
                if (_state.Phase++ == 1)
                {
                    _state.Address = Read(_state.Registers.ProgramCounter++);
                }
                else
                {
                    AccessData();
                }

                break;
            case AddressMode.ZeroPageIndexedX:
            case AddressMode.ZeroPageIndexedY:
                switch (_state.Phase++)
                {
                    case 1:
                        _state.Address = Read(_state.Registers.ProgramCounter++);
                        break;
                    case 2:
                        Read(_state.Address);
                        byte index = _state.Instruction.AddressMode == AddressMode.ZeroPageIndexedX
                            ? _state.Registers.X : _state.Registers.Y;

                        _state.Address = (byte)(_state.Address + index);
                        break;
                    case 3:
                        AccessData();
                        break;
                }

                break;
            case AddressMode.Absolute:
            case AddressMode.AbsoluteIndexedX:
            case AddressMode.AbsoluteIndexedY:
                switch (_state.Phase++)
                {
                    case 1:
                        _state.Data = Read(_state.Registers.ProgramCounter++);
                        break;
                    case 2:
                        _state.BaseAddress = (ushort)(_state.Data | (Read(_state.Registers.ProgramCounter++) << 8));
                        _state.Address = _state.BaseAddress;
                        if (_state.Instruction.AddressMode != AddressMode.Absolute)
                        {
                            _state.Address += _state.Instruction.AddressMode == AddressMode.AbsoluteIndexedX
                                ? _state.Registers.X : _state.Registers.Y;
                        }

                        break;
                    case 3:
                        if (Variant != ProcessorVariant.Mos6502 && _state.Instruction.Instruction == Instruction.NOP)
                        {
                            Read((ushort)(_state.Registers.ProgramCounter - 1));
                            Complete();
                        }
                        else if (_state.Instruction.AddressMode != AddressMode.Absolute && IndexedExtra)
                        {
                            Read(IndexedDummyAddress);
                        }
                        else
                        {
                            AccessData();
                        }

                        break;
                    case 4:
                        AccessData();
                        break;
                }

                break;
            case AddressMode.ZeroPageIndexedIndirect:
                switch (_state.Phase++)
                {
                    case 1:
                        _state.Pointer = Read(_state.Registers.ProgramCounter++);
                        break;
                    case 2:
                        Read(_state.Pointer);
                        _state.Pointer += _state.Registers.X;
                        break;
                    case 3:
                        _state.Data = Read(_state.Pointer);
                        break;
                    case 4:
                        _state.Address = (ushort)(_state.Data | (Read((byte)(_state.Pointer + 1)) << 8));
                        break;
                    case 5:
                        AccessData();
                        break;
                }

                break;
            case AddressMode.ZeroPageIndirect:
            case AddressMode.ZeroPageIndirectIndexedY:
                switch (_state.Phase++)
                {
                    case 1:
                        _state.Pointer = Read(_state.Registers.ProgramCounter++);
                        break;
                    case 2:
                        _state.Data = Read(_state.Pointer);
                        break;
                    case 3:
                        _state.BaseAddress = (ushort)(_state.Data | (Read((byte)(_state.Pointer + 1)) << 8));
                        _state.Address = _state.BaseAddress;
                        if (_state.Instruction.AddressMode == AddressMode.ZeroPageIndirectIndexedY)
                        {
                            _state.Address += _state.Registers.Y;
                        }

                        break;
                    case 4:
                        if (_state.Instruction.AddressMode == AddressMode.ZeroPageIndirectIndexedY && IndexedExtra)
                        {
                            Read(IndexedDummyAddress);
                        }
                        else
                        {
                            AccessData();
                        }

                        break;
                    case 5:
                        AccessData();
                        break;
                }

                break;
            default:
                throw new InvalidOperationException("Invalid memory addressing mode.");
        }
    }

    private void AccessData()
    {
        if (IsStore)
        {
            byte value = _state.Instruction.Instruction switch
            {
                Instruction.STA => _state.Registers.Accumulator,
                Instruction.STX => _state.Registers.X,
                Instruction.STY => _state.Registers.Y,
                Instruction.STZ => 0,
                Instruction.SAX => (byte)(_state.Registers.Accumulator & _state.Registers.X),
                _ => UnstableStore()
            };

            Write(_state.Address, value);
            Complete();
        }
        else if (IsModify)
        {
            _state.Data = Read(_state.Address);
            _state.Phase = 240;
        }
        else
        {
            FinishRead(Read(_state.Address));
        }
    }

    private byte UnstableStore()
    {
        byte mask = (byte)((_state.BaseAddress >> 8) + 1);
        if (_state.Instruction.Instruction == Instruction.TAS)
        {
            _state.Registers.StackPointer = (byte)(_state.Registers.Accumulator & _state.Registers.X);
        }

        byte value = _state.Instruction.Instruction switch
        {
            Instruction.SHX => (byte)(_state.Registers.X & mask),
            Instruction.SHY => (byte)(_state.Registers.Y & mask),
            _ => (byte)(_state.Registers.Accumulator & _state.Registers.X & mask)
        };

        if ((_state.BaseAddress & 0xFF00) != (_state.Address & 0xFF00))
        {
            _state.Address = (ushort)((value << 8) | (_state.Address & 0xFF));
        }

        return value;
    }

    private void FinishRead(byte value)
    {
        if (Variant != ProcessorVariant.Mos6502
            && (_state.Registers.Status & StatusRegister.DecimalMode) != 0
            && _state.Instruction.Instruction is Instruction.ADC or Instruction.SBC)
        {
            _state.Data = value;
            _state.Phase = 250;
            if (_state.Instruction.AddressMode == AddressMode.Immediate)
            {
                // The pinned bus profiles expose different idle addresses for decimal ADC immediate.
                _state.Address = _state.Instruction.Instruction != Instruction.ADC ? (ushort)0
                    : Variant == ProcessorVariant.Wdc65C02 ? (ushort)0x7F : (ushort)0x59;
            }
        }
        else
        {
            ExecuteRead(value);
            Complete();
        }
    }

    private void AdvanceData()
    {
        if (_state.Phase == 250)
        {
            Read(_state.Address);
            ExecuteRead(_state.Data);
            Complete();
        }
        else if (_state.Phase == 240)
        {
            if (Variant == ProcessorVariant.Mos6502)
            {
                Write(_state.Address, _state.Data);
            }
            else
            {
                Read(_state.Address);
            }

            _state.Phase = 241;
        }
        else if (_state.Phase == 241)
        {
            Write(_state.Address, Modify(_state.Data));
            Complete();
        }
        else
        {
            throw new InvalidOperationException("Invalid data microsequence.");
        }
    }

    private void AdvanceJump()
    {
        AddressMode mode = _state.Instruction.AddressMode;
        switch (_state.Phase++)
        {
            case 1:
                _state.Data = Read(_state.Registers.ProgramCounter++);
                break;
            case 2:
                _state.Address = (ushort)(_state.Data | (Read(_state.Registers.ProgramCounter++) << 8));
                if (mode == AddressMode.Absolute)
                {
                    _state.Registers.ProgramCounter = _state.Address;
                    Complete();
                }
                else if (mode == AddressMode.AbsoluteIndexedIndirect)
                {
                    _state.Address += _state.Registers.X;
                }

                break;
            case 3 when mode == AddressMode.AbsoluteIndexedIndirect:
                Read((ushort)(_state.Registers.ProgramCounter - 2));
                break;
            case 3:
            case 4 when mode == AddressMode.AbsoluteIndexedIndirect:
                _state.Data = Read(_state.Address);
                break;
            case 4:
                byte high = Read((ushort)((_state.Address & 0xFF00) | (byte)(_state.Address + 1)));
                if (Variant == ProcessorVariant.Mos6502)
                {
                    _state.Registers.ProgramCounter = (ushort)(_state.Data | (high << 8));
                    Complete();
                }

                break;
            case 5:
                _state.Registers.ProgramCounter = (ushort)(_state.Data | (Read((ushort)(_state.Address + 1)) << 8));
                Complete();
                break;
        }
    }

    private bool BranchTaken => _state.Instruction.Instruction switch
    {
        Instruction.BPL => (_state.Registers.Status & StatusRegister.Negative) == 0,
        Instruction.BMI => (_state.Registers.Status & StatusRegister.Negative) != 0,
        Instruction.BVC => (_state.Registers.Status & StatusRegister.Overflow) == 0,
        Instruction.BVS => (_state.Registers.Status & StatusRegister.Overflow) != 0,
        Instruction.BCC => (_state.Registers.Status & StatusRegister.Carry) == 0,
        Instruction.BCS => (_state.Registers.Status & StatusRegister.Carry) != 0,
        Instruction.BNE => (_state.Registers.Status & StatusRegister.Zero) == 0,
        Instruction.BEQ => (_state.Registers.Status & StatusRegister.Zero) != 0,
        Instruction.BRA => true,
        Instruction.BBR => (_state.Data & (1 << ((_state.Instruction.Code >> 4) & 7))) == 0,
        Instruction.BBS => (_state.Data & (1 << ((_state.Instruction.Code >> 4) & 7))) != 0,
        _ => throw new InvalidOperationException("Invalid branch instruction.")
    };

    private void AdvanceBranch()
    {
        bool bitBranch = _state.Instruction.AddressMode == AddressMode.ZeroPageRelative;
        int relativePhase = bitBranch ? 4 : 1;
        int phase = _state.Phase++;
        if (bitBranch && phase < 4)
        {
            switch (phase)
            {
                case 1: _state.Address = Read(_state.Registers.ProgramCounter++);
                    break;
                case 2: _state.Data = Read(_state.Address);
                    break;
                case 3: Read(_state.Address);
                    break;
            }

            return;
        }

        if (phase == relativePhase)
        {
            sbyte offset = (sbyte)Read(_state.Registers.ProgramCounter++);
            _state.BaseAddress = _state.Registers.ProgramCounter;
            _state.Address = (ushort)(_state.BaseAddress + offset);
            if (!BranchTaken)
            {
                Complete();
            }
        }
        else if (phase == relativePhase + 1)
        {
            Read(_state.BaseAddress);
            if ((_state.BaseAddress & 0xFF00) == (_state.Address & 0xFF00)
                )
            {
                _state.Registers.ProgramCounter = _state.Address;
                Complete();
            }
        }
        else if (bitBranch)
        {
            Read(_state.BaseAddress);
            _state.Registers.ProgramCounter = _state.Address;
            Complete();
        }
        else
        {
            Read((ushort)((_state.BaseAddress & 0xFF00) | (_state.Address & 0xFF)));
            _state.Registers.ProgramCounter = _state.Address;
            Complete();
        }
    }
}
