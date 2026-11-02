// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Cpu.M6502;

public sealed partial class Processor<TBus> where TBus : IProcessorBus
{
    private void Flag(StatusRegister flag, bool value)
    {
        _state.Registers.Status = value ? _state.Registers.Status | flag : _state.Registers.Status & ~flag;
    }

    private void Compare(byte register, byte value)
    {
        Flag(StatusRegister.Carry, register >= value);
        SetNegativeZero((byte)(register - value));
    }

    private void Add(byte value)
    {
        int a = _state.Registers.Accumulator;
        int carry = (_state.Registers.Status & StatusRegister.Carry) != 0 ? 1 : 0;
        int binary = a + value + carry;
        int result = binary;
        bool decimalMode = (_state.Registers.Status & StatusRegister.DecimalMode) != 0;
        if (decimalMode)
        {
            int low = (a & 15) + (value & 15) + carry;
            if (low > 9) { low = ((low + 6) & 15) + 16; }
            result = (a & 0xF0) + (value & 0xF0) + low;
        }

        Flag(StatusRegister.Overflow, (~(a ^ value) & (a ^ result) & 0x80) != 0);
        if (decimalMode && Variant == ProcessorVariant.Mos6502)
        {
            Flag(StatusRegister.Zero, (byte)binary == 0);
            Flag(StatusRegister.Negative, (result & 0x80) != 0);
        }

        if (decimalMode && result >= 0xA0) { result += 0x60; }
        Flag(StatusRegister.Carry, result > 255);
        _state.Registers.Accumulator = (byte)result;
        if (!decimalMode || Variant != ProcessorVariant.Mos6502)
        {
            SetNegativeZero((byte)result);
        }
    }

    private void Subtract(byte value)
    {
        int a = _state.Registers.Accumulator;
        int borrow = (_state.Registers.Status & StatusRegister.Carry) != 0 ? 0 : 1;
        int binary = a - value - borrow;
        int result = binary;
        bool decimalMode = (_state.Registers.Status & StatusRegister.DecimalMode) != 0;
        Flag(StatusRegister.Overflow, ((a ^ value) & (a ^ binary) & 0x80) != 0);
        Flag(StatusRegister.Carry, binary >= 0);
        if (decimalMode)
        {
            int low = (a & 15) - (value & 15) - borrow;
            if (Variant == ProcessorVariant.Mos6502)
            {
                if (low < 0) { low = ((low - 6) & 15) - 16; }
                result = (a & 0xF0) - (value & 0xF0) + low;
                if (result < 0) { result -= 0x60; }
            }
            else
            {
                if (low < 0) { result -= 6; }
                if (binary < 0) { result -= 0x60; }
            }
        }

        _state.Registers.Accumulator = (byte)result;
        SetNegativeZero((byte)(decimalMode && Variant == ProcessorVariant.Mos6502 ? binary : result));
    }

    private void ExecuteRead(byte value)
    {
        switch (_state.Instruction.Instruction)
        {
            case Instruction.NOP: return;
            case Instruction.ORA: _state.Registers.Accumulator |= value;
                break;
            case Instruction.AND: _state.Registers.Accumulator &= value;
                break;
            case Instruction.EOR: _state.Registers.Accumulator ^= value;
                break;
            case Instruction.ADC: Add(value);
                return;
            case Instruction.SBC: Subtract(value);
                return;
            case Instruction.LDA: _state.Registers.Accumulator = value;
                break;
            case Instruction.LDX: _state.Registers.X = value;
                SetNegativeZero(value);
                return;
            case Instruction.LDY: _state.Registers.Y = value;
                SetNegativeZero(value);
                return;
            case Instruction.CMP: Compare(_state.Registers.Accumulator, value);
                return;
            case Instruction.CPX: Compare(_state.Registers.X, value);
                return;
            case Instruction.CPY: Compare(_state.Registers.Y, value);
                return;
            case Instruction.BIT:
                Flag(StatusRegister.Zero, (_state.Registers.Accumulator & value) == 0);
                if (_state.Instruction.AddressMode != AddressMode.Immediate)
                {
                    Flag(StatusRegister.Negative, (value & 0x80) != 0);
                    Flag(StatusRegister.Overflow, (value & 0x40) != 0);
                }

                return;
            case Instruction.LAX:
                _state.Registers.Accumulator = _state.Instruction.Code == 0xAB
                    ? (byte)((_state.Registers.Accumulator | 0xEE) & value) : value;

                _state.Registers.X = _state.Registers.Accumulator;
                break;
            case Instruction.LAS:
                _state.Registers.Accumulator = (byte)(value & _state.Registers.StackPointer);
                _state.Registers.X = _state.Registers.Accumulator;
                _state.Registers.StackPointer = _state.Registers.Accumulator;
                break;
            case Instruction.ANC:
                _state.Registers.Accumulator &= value;
                Flag(StatusRegister.Carry, (_state.Registers.Accumulator & 0x80) != 0);
                break;
            case Instruction.ALR:
                value &= _state.Registers.Accumulator;
                Flag(StatusRegister.Carry, (value & 1) != 0);
                _state.Registers.Accumulator = (byte)(value >> 1);
                break;
            case Instruction.ARR:
                value &= _state.Registers.Accumulator;
                int result = (value >> 1) | ((_state.Registers.Status & StatusRegister.Carry) != 0 ? 0x80 : 0);
                SetNegativeZero((byte)result);
                Flag(StatusRegister.Overflow, ((result ^ (result << 1)) & 0x40) != 0);
                if ((_state.Registers.Status & StatusRegister.DecimalMode) != 0)
                {
                    if ((value & 15) + (value & 1) > 5) { result = (result & 0xF0) | ((result + 6) & 15); }
                    bool carry = (value & 0xF0) + (value & 0x10) > 0x50;
                    if (carry) { result += 0x60; }
                    Flag(StatusRegister.Carry, carry);
                }
                else
                {
                    Flag(StatusRegister.Carry, (result & 0x40) != 0);
                }

                _state.Registers.Accumulator = (byte)result;
                return;
            case Instruction.XAA:
                _state.Registers.Accumulator = (byte)((_state.Registers.Accumulator | 0xEE) & _state.Registers.X & value);
                break;
            case Instruction.AXS:
                int difference = (_state.Registers.Accumulator & _state.Registers.X) - value;
                _state.Registers.X = (byte)difference;
                Flag(StatusRegister.Carry, difference >= 0);
                SetNegativeZero(_state.Registers.X);
                return;
            default: throw new InvalidOperationException("Invalid read instruction.");
        }

        SetNegativeZero(_state.Registers.Accumulator);
    }

    private byte Modify(byte value)
    {
        Instruction instruction = _state.Instruction.Instruction;
        bool carry = (_state.Registers.Status & StatusRegister.Carry) != 0;
        byte result;
        switch (instruction)
        {
            case Instruction.ASL:
            case Instruction.SLO:
                Flag(StatusRegister.Carry, (value & 0x80) != 0);
                result = (byte)(value << 1);
                break;
            case Instruction.ROL:
            case Instruction.RLA:
                Flag(StatusRegister.Carry, (value & 0x80) != 0);
                result = (byte)((value << 1) | (carry ? 1 : 0));
                break;
            case Instruction.LSR:
            case Instruction.SRE:
                Flag(StatusRegister.Carry, (value & 1) != 0);
                result = (byte)(value >> 1);
                break;
            case Instruction.ROR:
            case Instruction.RRA:
                Flag(StatusRegister.Carry, (value & 1) != 0);
                result = (byte)((value >> 1) | (carry ? 0x80 : 0));
                break;
            case Instruction.INC:
            case Instruction.ISC: result = (byte)(value + 1);
            break;
            case Instruction.DEC:
            case Instruction.DCP: result = (byte)(value - 1);
            break;
            case Instruction.TSB:
            case Instruction.TRB:
                Flag(StatusRegister.Zero, (_state.Registers.Accumulator & value) == 0);
                return instruction == Instruction.TSB
                    ? (byte)(value | _state.Registers.Accumulator) : (byte)(value & ~_state.Registers.Accumulator);

            case Instruction.RMB: return (byte)(value & ~(1 << ((_state.Instruction.Code >> 4) & 7)));
            case Instruction.SMB: return (byte)(value | (1 << ((_state.Instruction.Code >> 4) & 7)));
            default: throw new InvalidOperationException("Invalid modify instruction.");
        }

        switch (instruction)
        {
            case Instruction.SLO: _state.Registers.Accumulator |= result;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.RLA: _state.Registers.Accumulator &= result;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.SRE: _state.Registers.Accumulator ^= result;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.RRA: Add(result);
                break;
            case Instruction.DCP: Compare(_state.Registers.Accumulator, result);
                break;
            case Instruction.ISC: Subtract(result);
                break;
            default: SetNegativeZero(result);
                break;
        }

        return result;
    }
}
