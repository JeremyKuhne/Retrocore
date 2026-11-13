// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.M6809.M6809ConditionCode;

namespace Retrocore.Cpu.M6809;

public sealed partial class M6809Processor<TBus>
{
    private void AdvanceReset()
    {
        switch (_state.Step)
        {
            case 0:
            case 1:
            case 2:
            case 3:
                _state.Step++;
                return;
            case 4:
                _state.Step = 5;
                return;
            case 5:
                // Hold in reset before reading the vector while RESET remains asserted.
                if ((_state.Signals & M6809Signals.Reset) != 0)
                {
                    return;
                }

                _state.High = BusRead(0xFFFE);
                _state.Step = 6;
                return;
            default:
                byte low = BusRead(0xFFFF);
                _state.Registers.PC = (ushort)((_state.High << 8) | low);
                _state.Registers.DP = 0;
                _state.Registers.CC |= (byte)(InterruptMask | FastInterruptMask);
                _state.Registers.NmiArmed = false;
                Complete();
                return;
        }
    }

    private void AdvanceInterrupt()
    {
        ref M6809Registers r = ref _state.Registers;
        if (_state.InterruptPrestacked)
        {
            switch (_state.Step)
            {
                case 0:
                case 1:
                case 2:
                    _state.Step++;
                    return;
                case 3:
                    ApplyInterruptMasks(ref r, _state.Postbyte);
                    _state.Step = 4;
                    return;
                case 4:
                    _state.High = BusRead(_state.Effective);
                    _state.Step = 5;
                    return;
                case 5:
                    _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                    _state.Step = 6;
                    return;
                default:
                    r.PC = _state.Effective;
                    Complete();
                    return;
            }
        }

        // FIRQ (Postbyte == 2): 3 internal + 3 stack writes + 1 internal + 2 vector reads + 1 internal = 10 cycles.
        if (_state.Postbyte == 2)
        {
            switch (_state.Step)
            {
                case 0:
                case 1:
                    _state.Step++;
                    return;
                case 2:
                    r.CC &= unchecked((byte)~Entire);
                    _state.Step = 3;
                    return;
                case 3:
                    PushByte(ref r, system: true, (byte)r.PC);
                    _state.Step = 4;
                    return;
                case 4:
                    PushByte(ref r, system: true, (byte)(r.PC >> 8));
                    _state.Step = 5;
                    return;
                case 5:
                    PushByte(ref r, system: true, r.CC);
                    _state.Step = 6;
                    return;
                case 6:
                    r.CC |= (byte)(InterruptMask | FastInterruptMask);
                    _state.Step = 7;
                    return;
                case 7:
                    _state.High = BusRead(_state.Effective);
                    _state.Step = 8;
                    return;
                case 8:
                    _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                    _state.Step = 9;
                    return;
                default:
                    r.PC = _state.Effective;
                    Complete();
                    return;
            }
        }

        // Full frame IRQ / NMI: 3 internal + 12 stack writes + 1 internal + 2 vector reads + 1 internal = 19 cycles.
        switch (_state.Step)
        {
            case 0:
            case 1:
                _state.Step++;
                return;
            case 2:
                r.CC |= (byte)Entire;
                _state.Remaining = 0;
                _state.Step = 3;
                return;
            case 3:
                PushFrameSlot(ref r, system: true, _state.Remaining);
                if (++_state.Remaining == 12)
                {
                    _state.Step = 4;
                }

                return;
            case 4:
                ApplyInterruptMasks(ref r, _state.Postbyte);
                _state.Step = 5;
                return;
            case 5:
                _state.High = BusRead(_state.Effective);
                _state.Step = 6;
                return;
            case 6:
                _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                _state.Step = 7;
                return;
            default:
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceAddress()
    {
        ref M6809Registers r = ref _state.Registers;
        switch (_state.AddressPhase)
        {
            case M6809AddressPhase.DirectFetch:
                _state.Effective = (ushort)((r.DP << 8) | ReadOperand(opcode: false));
                _state.Indirect = false;
                _state.Remaining = 1;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case M6809AddressPhase.ExtendedHigh:
                _state.High = ReadOperand(opcode: false);
                _state.AddressPhase = M6809AddressPhase.ExtendedLow;
                return;
            case M6809AddressPhase.ExtendedLow:
                _state.Effective = (ushort)((_state.High << 8) | ReadOperand(opcode: false));
                _state.Indirect = false;
                _state.Remaining = 1;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case M6809AddressPhase.IndexedPostbyte:
                DecodeIndexedPostbyte(ref r, ReadOperand(opcode: false));
                return;
            case M6809AddressPhase.IndexedOffset8:
                sbyte offset8 = unchecked((sbyte)ReadOperand(opcode: false));
                ushort base8 = (_state.Postbyte & 0x0F) == 12 ? r.PC : GetIndexRegister(in r, _state.Postbyte);
                _state.Effective = (ushort)(base8 + offset8);
                _state.Remaining = 1;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case M6809AddressPhase.IndexedWordHigh:
                _state.High = ReadOperand(opcode: false);
                _state.AddressPhase = M6809AddressPhase.IndexedWordLow;
                return;
            case M6809AddressPhase.IndexedWordLow:
                ushort word = (ushort)((_state.High << 8) | ReadOperand(opcode: false));
                int mode = _state.Postbyte & 0x0F;
                if (mode == 15)
                {
                    _state.Effective = word;
                    _state.Remaining = 1;
                }
                else if (mode == 13)
                {
                    _state.Effective = (ushort)(r.PC + unchecked((short)word));
                    _state.Remaining = 4;
                }
                else
                {
                    _state.Effective = (ushort)(GetIndexRegister(in r, _state.Postbyte) + unchecked((short)word));
                    _state.Remaining = 3;
                }

                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case M6809AddressPhase.InternalDelay:
                if (--_state.Remaining > 0)
                {
                    return;
                }

                if (_state.Indirect)
                {
                    _state.AddressPhase = M6809AddressPhase.IndirectHigh;
                    return;
                }

                FinishEffectiveAddress(ref r);
                return;
            case M6809AddressPhase.IndirectHigh:
                _state.High = BusRead(_state.Effective);
                _state.AddressPhase = M6809AddressPhase.IndirectLow;
                return;
            case M6809AddressPhase.IndirectLow:
                _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                _state.AddressPhase = M6809AddressPhase.IndirectDelay;
                return;
            default:
                FinishEffectiveAddress(ref r);
                return;
        }
    }

    private void DecodeIndexedPostbyte(ref M6809Registers r, byte postbyte)
    {
        _state.Postbyte = postbyte;
        ushort index = GetIndexRegister(in r, postbyte);
        if ((postbyte & 0x80) == 0)
        {
            int offset5 = (postbyte & 0x10) != 0 ? (postbyte | ~0x1F) : (postbyte & 0x1F);
            _state.Effective = (ushort)(index + offset5);
            _state.Indirect = false;
            _state.Remaining = 2;
            _state.AddressPhase = M6809AddressPhase.InternalDelay;
            return;
        }

        _state.Indirect = (postbyte & 0x10) != 0;

        // Auto-increment and auto-decrement of S arm NMI as loading S does (Flamand, page 9).
        if ((postbyte & 0x6C) == 0x60)
        {
            r.NmiArmed = true;
        }

        switch (postbyte & 0x0F)
        {
            case 0:
                _state.Effective = index;
                SetIndexRegister(ref r, postbyte, (ushort)(index + 1));
                _state.Remaining = 3;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 1:
                _state.Effective = index;
                SetIndexRegister(ref r, postbyte, (ushort)(index + 2));
                _state.Remaining = 4;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 2:
                index--;
                SetIndexRegister(ref r, postbyte, index);
                _state.Effective = index;
                _state.Remaining = 3;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 3:
                index -= 2;
                SetIndexRegister(ref r, postbyte, index);
                _state.Effective = index;
                _state.Remaining = 4;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 4:
                _state.Effective = index;
                _state.Remaining = 1;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 5:
                _state.Effective = (ushort)(index + unchecked((sbyte)r.B));
                _state.Remaining = 2;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 6:
            case 7:
                // Mode 7 is an undocumented second encoding of A,R (Flamand, page 6).
                _state.Effective = (ushort)(index + unchecked((sbyte)r.A));
                _state.Remaining = 2;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 8:
            case 12:
                _state.AddressPhase = M6809AddressPhase.IndexedOffset8;
                return;
            case 9:
            case 13:
            case 15:
                _state.AddressPhase = M6809AddressPhase.IndexedWordHigh;
                return;
            case 11:
                _state.Effective = (ushort)(index + unchecked((short)r.D));
                _state.Remaining = 5;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            case 14:
                // Undocumented: the address is $FFFF, five cycles more than ,R (Flamand, page 6).
                _state.Effective = 0xFFFF;
                _state.Remaining = 6;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
            default:
                // ,R, and the undocumented mode 10, whose PC-derived address and change to A are not modelled.
                _state.Effective = index;
                _state.Remaining = 1;
                _state.AddressPhase = M6809AddressPhase.InternalDelay;
                return;
        }
    }

    private void FinishEffectiveAddress(ref M6809Registers r)
    {
        if (_state.Operation == M6809Operation.Jump)
        {
            r.PC = _state.Effective;
            Complete();
            return;
        }

        _state.AddressPhase = M6809AddressPhase.Ready;
    }

    private void AdvanceOperation()
    {
        if (_state.AddressPhase != M6809AddressPhase.Ready)
        {
            AdvanceAddress();
            return;
        }

        ref M6809Registers r = ref _state.Registers;
        switch (_state.Operation)
        {
            case M6809Operation.DecodePage:
                DecodePrefixed(_state.Page, ReadOperand(opcode: false));
                return;
            case M6809Operation.Inherent:
                if (--_state.Remaining > 0)
                {
                    return;
                }

                ExecuteInherent(ref r);
                return;
            case M6809Operation.Immediate8:
                AdvanceImmediate8(ref r);
                return;
            case M6809Operation.Immediate16Load:
                if (_state.Step == 0)
                {
                    _state.High = ReadOperand(opcode: false);
                    _state.Step = 1;
                    return;
                }

                ApplyLoad16(ref r, (ushort)((_state.High << 8) | ReadOperand(opcode: false)));
                Complete();
                return;
            case M6809Operation.Immediate16Alu:
                switch (_state.Step)
                {
                    case 0:
                        _state.High = ReadOperand(opcode: false);
                        _state.Step = 1;
                        return;
                    case 1:
                        _state.Effective = (ushort)((_state.High << 8) | ReadOperand(opcode: false));
                        _state.Step = 2;
                        return;
                    default:
                        ApplyAlu16(ref r, _state.Effective);
                        Complete();
                        return;
                }

            case M6809Operation.BranchShort:
                if (_state.Step == 0)
                {
                    _state.High = ReadOperand(opcode: false);
                    _state.Step = 1;
                    return;
                }

                if (BranchCondition(r.CC, (byte)(_state.Opcode & 0x0F)))
                {
                    r.PC = (ushort)(r.PC + unchecked((sbyte)_state.High));
                }

                Complete();
                return;
            case M6809Operation.BranchLong:
                AdvanceBranchLong(ref r);
                return;
            case M6809Operation.BranchSubroutineShort:
                AdvanceBranchSubroutineShort(ref r);
                return;
            case M6809Operation.BranchSubroutineLong:
                AdvanceBranchSubroutineLong(ref r);
                return;
            case M6809Operation.TransferExchange:
                if (_state.Step == 0)
                {
                    _state.Postbyte = ReadOperand(opcode: false);
                    _state.Remaining = _state.Opcode == 0x1E ? (byte)6 : (byte)4;
                    _state.Step = 1;
                    return;
                }

                if (--_state.Remaining > 0)
                {
                    return;
                }

                ApplyTransferExchange(ref r, _state.Postbyte, transfer: _state.Opcode == 0x1F);
                Complete();
                return;
            case M6809Operation.StackPush:
                AdvanceStackPush(ref r, system: _state.Opcode == 0x34);
                return;
            case M6809Operation.StackPull:
                AdvanceStackPull(ref r, system: _state.Opcode == 0x35);
                return;
            case M6809Operation.ReturnSubroutine:
                AdvanceReturnSubroutine(ref r);
                return;
            case M6809Operation.ReturnInterrupt:
                AdvanceReturnInterrupt(ref r);
                return;
            case M6809Operation.Cwai:
                AdvanceCwai(ref r);
                return;
            case M6809Operation.SoftwareInterrupt:
                AdvanceSoftwareInterrupt(ref r);
                return;
            case M6809Operation.LoadEffectiveAddress:
                SetFlagGroup(M6809FlagGroup.LatchedDecrement, (byte)((_state.Effective >> 8) | (_state.Effective & 0xFF)));
                switch (_state.Opcode)
                {
                    case 0x30:
                        r.X = _state.Effective;
                        SetZeroOnly(ref r, r.X);
                        break;
                    case 0x31:
                        r.Y = _state.Effective;
                        SetZeroOnly(ref r, r.Y);
                        break;
                    case 0x32:
                        r.S = _state.Effective;
                        r.NmiArmed = true;
                        break;
                    default:
                        r.U = _state.Effective;
                        break;
                }

                Complete();
                return;
            case M6809Operation.MemoryRead8:
                ApplyAlu8(ref r, BusRead(_state.Effective));
                Complete();
                return;
            case M6809Operation.MemoryWrite8:
                byte store8 = _state.Opcode < 0xC0 ? r.A : r.B;
                BusWrite(_state.Effective, store8);
                SetNZ8(ref r, store8);
                r.CC &= unchecked((byte)~Overflow);
                Complete();
                return;
            case M6809Operation.MemoryRead16:
                if (_state.Step == 0)
                {
                    _state.High = BusRead(_state.Effective);
                    _state.Step = 1;
                    return;
                }

                ApplyLoad16(ref r, (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1))));
                Complete();
                return;
            case M6809Operation.MemoryWrite16:
                ushort store16 = GetStoreWord(in r);
                if (_state.Step == 0)
                {
                    BusWrite(_state.Effective, (byte)(store16 >> 8));
                    _state.Step = 1;
                    return;
                }

                BusWrite((ushort)(_state.Effective + 1), (byte)store16);
                SetNZ16(ref r, store16);
                r.CC &= unchecked((byte)~Overflow);
                Complete();
                return;
            case M6809Operation.MemoryAlu16:
                switch (_state.Step)
                {
                    case 0:
                        _state.High = BusRead(_state.Effective);
                        _state.Step = 1;
                        return;
                    case 1:
                        _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                        _state.Step = 2;
                        return;
                    default:
                        ApplyAlu16(ref r, _state.Effective);
                        Complete();
                        return;
                }

            case M6809Operation.MemoryModify8:
                switch (_state.Step)
                {
                    case 0:
                        _state.High = BusRead(_state.Effective);
                        _state.Step = 1;
                        return;
                    case 1:
                        _state.High = Unary(ref r, (byte)(_state.Opcode & 0x0F), _state.High);
                        _state.Step = 2;
                        return;
                    default:
                        BusWrite(_state.Effective, _state.High);
                        Complete();
                        return;
                }

            case M6809Operation.MemoryTest8:
                switch (_state.Step)
                {
                    case 0:
                        _state.High = BusRead(_state.Effective);
                        _state.Step = 1;
                        return;
                    case 1:
                        _state.Step = 2;
                        return;
                    default:
                        SetNZ8(ref r, _state.High);
                        r.CC &= unchecked((byte)~Overflow);
                        Complete();
                        return;
                }

            case M6809Operation.StoreImmediate8:
                // Reads the operand and stores nothing.
                _ = ReadOperand(opcode: false);
                ApplyStoreImmediateFlags(ref r, wide: false, registerLow: 0);
                Complete();
                return;
            case M6809Operation.StoreImmediate16:
                if (_state.Step == 0)
                {
                    _state.High = ReadOperand(opcode: false);
                    _state.Step = 1;
                    return;
                }

                // Writes the register's low byte over the operand's low byte; the high byte is untouched.
                byte low = (byte)GetStoreImmediateRegister(in r);
                BusWrite(r.PC++, low);
                ApplyStoreImmediateFlags(ref r, wide: true, low);
                Complete();
                return;
            case M6809Operation.ShiftConditionCodes:
                if (_state.Step == 0)
                {
                    // The mask is the next byte, read without advancing PC.
                    _state.High = BusRead(r.PC);
                    _state.Step = 1;
                    return;
                }

                // Each flag takes the one below it ANDed with the mask's bit; V also takes Z and bit 2; C clears.
                int masked = r.CC & _state.High;
                r.CC = (byte)((masked << 1) | ((masked & 0x04) >> 1));
                Complete();
                return;
            case M6809Operation.HaltAndCatchFire:
                // Reads up through memory a byte a cycle until RESET; no interrupt is taken.
                _ = BusRead(r.PC++);
                return;
            default:
                AdvanceJumpSubroutine(ref r);
                return;
        }
    }

    private void ExecuteInherent(ref M6809Registers r)
    {
        switch (_state.Opcode)
        {
            case 0x12 or 0x1B:
                Complete();
                return;
            case 0x13:
                _state.Wait = M6809WaitState.Sync;
                Complete();
                _state.Status = ProcessorExecutionStatus.Waiting;
                return;
            case 0x19:
                DecimalAdjust(ref r);
                SetFlagGroup(M6809FlagGroup.AccumulatorADecrement);
                Complete();
                return;
            case 0x1D:
                // V is unchanged, though the datasheet says cleared (the wiki and MAME agree).
                r.A = (r.B & 0x80) != 0 ? (byte)0xFF : (byte)0;
                SetNZ16(ref r, r.D);
                SetFlagGroup(M6809FlagGroup.AccumulatorBDecrement);
                Complete();
                return;
            case 0x3A:
                r.X = (ushort)(r.X + r.B);
                Complete();
                return;
            case 0x3D:
                ushort product = (ushort)(r.A * r.B);
                r.D = product;
                int mulFlags = (r.CC & ~(byte)(Zero | Carry))
                    | (product == 0 ? (byte)Zero : 0)
                    | ((product & 0x80) != 0 ? (byte)Carry : 0);

                r.CC = (byte)mulFlags;
                Complete();
                return;
            default:
                bool isA = _state.Opcode < 0x50;
                byte kind = (byte)(_state.Opcode & 0x0F);
                byte result = Unary(ref r, kind, isA ? r.A : r.B);
                if (kind != 0x0D)
                {
                    if (isA) { r.A = result; }
                    else { r.B = result; }
                }

                if (isA && kind < 0x0E)
                {
                    SetFlagGroup(M6809FlagGroup.AccumulatorADecrement);
                }

                Complete();
                return;
        }
    }

    private void AdvanceImmediate8(ref M6809Registers r)
    {
        if (_state.Opcode is 0x1A or 0x1C or 0x38)
        {
            if (_state.Step == 0)
            {
                _state.High = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            }

            // The undocumented XANDCC ($38) is ANDCC with one more cycle.
            if (_state.Opcode == 0x38 && _state.Step == 1)
            {
                _state.Step = 2;
                return;
            }

            if (_state.Opcode == 0x1A) { r.CC |= _state.High; }
            else { r.CC &= _state.High; }
            Complete();
            return;
        }

        ApplyAlu8(ref r, ReadOperand(opcode: false));
        Complete();
    }

    private void AdvanceBranchLong(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.High = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            case 1:
                _state.Effective = (ushort)((_state.High << 8) | ReadOperand(opcode: false));
                _state.Step = 2;
                return;
            case 2:
                if (_state.Page == 0)
                {
                    // Page-0 LBRA ($16): 1 op + 2 offset + 2 internal = 5 cycles.
                    _state.Step = 3;
                    return;
                }

                if (_state.Opcode == 0x21 || !BranchCondition(r.CC, (byte)(_state.Opcode & 0x0F)))
                {
                    Complete();
                    return;
                }

                _state.Step = 3;
                return;
            default:
                r.PC = (ushort)(r.PC + unchecked((short)_state.Effective));
                Complete();
                return;
        }
    }

    private void AdvanceBranchSubroutineShort(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.High = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            case 1:
            case 2:
                _state.Step++;
                return;
            case 3:
                _state.Effective = (ushort)(r.PC + unchecked((sbyte)_state.High));
                _state.Step = 4;
                return;
            case 4:
                PushByte(ref r, system: true, (byte)r.PC);
                _state.Step = 5;
                return;
            default:
                PushByte(ref r, system: true, (byte)(r.PC >> 8));
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceBranchSubroutineLong(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.High = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            case 1:
                _state.Effective = (ushort)((_state.High << 8) | ReadOperand(opcode: false));
                _state.Effective = (ushort)(r.PC + unchecked((short)_state.Effective));
                _state.Step = 2;
                return;
            case 2:
            case 3:
            case 4:
            case 5:
                _state.Step++;
                return;
            case 6:
                PushByte(ref r, system: true, (byte)r.PC);
                _state.Step = 7;
                return;
            default:
                PushByte(ref r, system: true, (byte)(r.PC >> 8));
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceJumpSubroutine(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
            case 1:
                _state.Step++;
                return;
            case 2:
                PushByte(ref r, system: true, (byte)r.PC);
                _state.Step = 3;
                return;
            default:
                PushByte(ref r, system: true, (byte)(r.PC >> 8));
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceStackPush(ref M6809Registers r, bool system)
    {
        switch (_state.Step)
        {
            case 0:
                // PSHS and PULS arm NMI, even with no registers (Flamand, page 9).
                r.NmiArmed |= system;
                _state.Postbyte = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            case 1:
            case 2:
                _state.Step++;
                return;
            case 3:
                if (_state.Postbyte == 0)
                {
                    Complete();
                    return;
                }

                _state.Remaining = NextPushSlot(_state.Postbyte, 0);
                _state.Step = 4;
                return;
            default:
                PushFrameSlot(ref r, system, _state.Remaining);
                byte next = NextPushSlot(_state.Postbyte, (byte)(_state.Remaining + 1));
                if (next >= 12)
                {
                    Complete();
                    return;
                }

                _state.Remaining = next;
                return;
        }
    }

    private void AdvanceStackPull(ref M6809Registers r, bool system)
    {
        switch (_state.Step)
        {
            case 0:
                r.NmiArmed |= system;
                _state.Postbyte = ReadOperand(opcode: false);
                _state.Step = 1;
                return;
            case 1:
                _state.Step = 2;
                return;
            case 2:
                if (_state.Postbyte == 0)
                {
                    _state.Step = 4;
                    return;
                }

                _state.Remaining = NextPullSlot(_state.Postbyte, 0);
                _state.Step = 3;
                return;
            case 3:
                PullFrameSlot(ref r, system, _state.Remaining);
                byte next = NextPullSlot(_state.Postbyte, (byte)(_state.Remaining + 1));
                if (next >= 12)
                {
                    _state.Step = 4;
                    return;
                }

                _state.Remaining = next;
                return;
            default:
                Complete();
                return;
        }
    }

    private void AdvanceReturnSubroutine(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.Step = 1;
                return;
            case 1:
                _state.High = PullByte(ref r, system: true);
                _state.Step = 2;
                return;
            case 2:
                _state.Effective = (ushort)((_state.High << 8) | PullByte(ref r, system: true));
                _state.Step = 3;
                return;
            default:
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceReturnInterrupt(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.Step = 1;
                return;
            case 1:
                r.CC = PullByte(ref r, system: true);
                _state.Step = (r.CC & (byte)Entire) != 0 ? (byte)2 : (byte)11;
                return;
            case 2:
                r.A = PullByte(ref r, system: true);
                _state.Step = 3;
                return;
            case 3:
                r.B = PullByte(ref r, system: true);
                _state.Step = 4;
                return;
            case 4:
                r.DP = PullByte(ref r, system: true);
                _state.Step = 5;
                return;
            case 5:
                _state.High = PullByte(ref r, system: true);
                _state.Step = 6;
                return;
            case 6:
                r.X = (ushort)((_state.High << 8) | PullByte(ref r, system: true));
                _state.Step = 7;
                return;
            case 7:
                _state.High = PullByte(ref r, system: true);
                _state.Step = 8;
                return;
            case 8:
                r.Y = (ushort)((_state.High << 8) | PullByte(ref r, system: true));
                _state.Step = 9;
                return;
            case 9:
                _state.High = PullByte(ref r, system: true);
                _state.Step = 10;
                return;
            case 10:
                r.U = (ushort)((_state.High << 8) | PullByte(ref r, system: true));
                _state.Step = 11;
                return;
            case 11:
                _state.High = PullByte(ref r, system: true);
                _state.Step = 12;
                return;
            case 12:
                _state.Effective = (ushort)((_state.High << 8) | PullByte(ref r, system: true));
                _state.Step = 13;
                return;
            default:
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private void AdvanceCwai(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                r.CC = (byte)((r.CC & ReadOperand(opcode: false)) | (byte)Entire);
                _state.Step = 1;
                return;
            case 1:
            case 2:
            case 3:
            case 4:
            case 5:
                _state.Step++;
                return;
            case 6:
                _state.Remaining = 0;
                _state.Step = 7;
                return;
            default:
                PushFrameSlot(ref r, system: true, _state.Remaining);
                if (++_state.Remaining == 12)
                {
                    _state.Wait = M6809WaitState.Cwai;
                    Complete();
                    _state.Status = ProcessorExecutionStatus.Waiting;
                }

                return;
        }
    }

    private void AdvanceSoftwareInterrupt(ref M6809Registers r)
    {
        switch (_state.Step)
        {
            case 0:
                _state.Step = 1;
                return;
            case 1:
                // The undocumented XRES, XSWI2 and XFIRQ ($3E) stack CC without setting E.
                if (_state.Opcode == 0x3F)
                {
                    r.CC |= (byte)Entire;
                }

                _state.Remaining = 0;
                _state.Step = 2;
                return;
            case 2:
                PushFrameSlot(ref r, system: true, _state.Remaining);
                if (++_state.Remaining == 12)
                {
                    _state.Step = 3;
                }

                return;
            case 3:
                if (_state.Page == 0 && _state.Opcode == 0x3F)
                {
                    r.CC |= (byte)(InterruptMask | FastInterruptMask);
                }

                _state.Step = 4;
                return;
            case 4:
                _state.High = BusRead(_state.Effective);
                _state.Step = 5;
                return;
            case 5:
                _state.Effective = (ushort)((_state.High << 8) | BusRead((ushort)(_state.Effective + 1)));
                _state.Step = 6;
                return;
            default:
                r.PC = _state.Effective;
                Complete();
                return;
        }
    }

    private static void ApplyInterruptMasks(ref M6809Registers r, byte interruptKind)
    {
        if (interruptKind is 1 or 2)
        {
            r.CC |= (byte)(InterruptMask | FastInterruptMask);
        }
        else
        {
            r.CC |= (byte)InterruptMask;
        }
    }

    private static byte NextPushSlot(byte mask, byte start)
    {
        for (byte slot = start; slot < 12; slot++)
        {
            byte bit = slot switch
            {
                0 or 1 => 0x80,
                2 or 3 => 0x40,
                4 or 5 => 0x20,
                6 or 7 => 0x10,
                8 => 0x08,
                9 => 0x04,
                10 => 0x02,
                _ => 0x01
            };

            if ((mask & bit) != 0)
            {
                return slot;
            }
        }

        return 12;
    }

    private static byte NextPullSlot(byte mask, byte start)
    {
        for (byte slot = start; slot < 12; slot++)
        {
            byte bit = slot switch
            {
                0 => 0x01,
                1 => 0x02,
                2 => 0x04,
                3 => 0x08,
                4 or 5 => 0x10,
                6 or 7 => 0x20,
                8 or 9 => 0x40,
                _ => 0x80
            };

            if ((mask & bit) != 0)
            {
                return slot;
            }
        }

        return 12;
    }

    private void PushFrameSlot(ref M6809Registers r, bool system, byte slot)
    {
        ushort other = system ? r.U : r.S;
        byte value = slot switch
        {
            0 => (byte)r.PC,
            1 => (byte)(r.PC >> 8),
            2 => (byte)other,
            3 => (byte)(other >> 8),
            4 => (byte)r.Y,
            5 => (byte)(r.Y >> 8),
            6 => (byte)r.X,
            7 => (byte)(r.X >> 8),
            8 => r.DP,
            9 => r.B,
            10 => r.A,
            _ => r.CC
        };

        PushByte(ref r, system, value);
    }

    private void PullFrameSlot(ref M6809Registers r, bool system, byte slot)
    {
        byte value = PullByte(ref r, system);
        switch (slot)
        {
            case 0:
                r.CC = value;
                return;
            case 1:
                r.A = value;
                return;
            case 2:
                r.B = value;
                return;
            case 3:
                r.DP = value;
                return;
            case 4:
            case 6:
            case 8:
            case 10:
                _state.High = value;
                return;
            case 5:
                r.X = (ushort)((_state.High << 8) | value);
                return;
            case 7:
                r.Y = (ushort)((_state.High << 8) | value);
                return;
            case 9:
                ushort other = (ushort)((_state.High << 8) | value);
                if (system)
                {
                    r.U = other;
                }
                else
                {
                    r.S = other;
                    r.NmiArmed = true;
                }

                return;
            default:
                r.PC = (ushort)((_state.High << 8) | value);
                return;
        }
    }

    private void PushByte(ref M6809Registers r, bool system, byte value)
    {
        ushort sp = system ? (ushort)(r.S - 1) : (ushort)(r.U - 1);
        if (system) { r.S = sp; }
        else { r.U = sp; }
        BusWrite(sp, value);
    }

    private byte PullByte(ref M6809Registers r, bool system)
    {
        ushort sp = system ? r.S : r.U;
        byte value = BusRead(sp);
        if (system) { r.S = (ushort)(sp + 1); }
        else { r.U = (ushort)(sp + 1); }
        return value;
    }

    private static ushort GetIndexRegister(in M6809Registers r, byte postbyte) => (postbyte & 0x60) switch
    {
        0x00 => r.X,
        0x20 => r.Y,
        0x40 => r.U,
        _ => r.S
    };

    private static void SetIndexRegister(ref M6809Registers r, byte postbyte, ushort value)
    {
        switch (postbyte & 0x60)
        {
            case 0x00:
                r.X = value;
                return;
            case 0x20:
                r.Y = value;
                return;
            case 0x40:
                r.U = value;
                return;
            default:
                r.S = value;
                return;
        }
    }

    private ushort GetStoreWord(in M6809Registers r)
    {
        if (_state.Page == 0x10)
        {
            return _state.Opcode >= 0xDF ? r.S : r.Y;
        }

        return (_state.Opcode & 0x0F) == 0x0D
            ? r.D
            : _state.Opcode >= 0xC0 ? r.U : r.X;
    }

    // $8F and $CF store X and U, Y and S after $10, and X and U after $11.
    private ushort GetStoreImmediateRegister(in M6809Registers r) => _state.Page == 0x10
        ? _state.Opcode >= 0xC0 ? r.S : r.Y
        : _state.Opcode >= 0xC0 ? r.U : r.X;

    private void SetFlagGroup(M6809FlagGroup group, byte value = 0)
    {
        _state.FlagGroup = group;
        _state.FlagGroupValue = value;
    }

    // An undocumented store immediate sets N, Z and V from what the previous instruction left in the ALU, or
    // after a prefix sets N and clears Z and V (Banks's wiki).
    private void ApplyStoreImmediateFlags(ref M6809Registers r, bool wide, byte registerLow)
    {
        bool negative;
        bool zero;
        bool overflow = false;
        if (_state.Page != 0)
        {
            negative = true;
            zero = false;
        }
        else
        {
            switch (_state.PreviousFlagGroup)
            {
                case M6809FlagGroup.ZeroSet:
                    negative = false;
                    zero = true;
                    break;
                case M6809FlagGroup.AccumulatorA:
                    negative = (r.A & 0x80) != 0;
                    zero = r.A == 0;
                    break;
                case M6809FlagGroup.AccumulatorAInverted:
                    negative = (r.A & 0x80) == 0;
                    zero = r.A == 0xFF;
                    break;
                case M6809FlagGroup.AccumulatorADecrement:
                case M6809FlagGroup.AccumulatorBDecrement:
                case M6809FlagGroup.LatchedDecrement:
                    byte latch = _state.PreviousFlagGroup switch
                    {
                        M6809FlagGroup.AccumulatorADecrement => r.A,
                        M6809FlagGroup.AccumulatorBDecrement => r.B,
                        _ => _state.PreviousFlagGroupValue
                    };

                    negative = ((latch - 1) & 0x80) != 0;
                    zero = latch == 1;
                    overflow = latch == 0x80;
                    break;
                default:
                    negative = true;
                    zero = false;
                    break;
            }

            if (wide)
            {
                zero &= registerLow == 0;
                overflow = false;
            }
        }

        int flags = r.CC & ~(byte)(Negative | Zero | Overflow);
        if (negative) { flags |= (byte)Negative; }
        if (zero) { flags |= (byte)Zero; }
        if (overflow) { flags |= (byte)Overflow; }
        r.CC = (byte)flags;
    }
}
