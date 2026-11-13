// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.M6809.M6809ConditionCode;

namespace Retrocore.Cpu.M6809;

public sealed partial class M6809Processor<TBus>
{
    private void ApplyAlu8(ref M6809Registers r, byte value)
    {
        bool accumulatorA = _state.Opcode < 0xC0;
        byte accumulator = accumulatorA ? r.A : r.B;
        int operation = _state.Opcode & 0x0F;
        byte result = accumulator;

        switch (operation)
        {
            case 0x0:
                result = Subtract8(ref r, accumulator, value, borrowIn: false);
                break;
            case 0x1:
                _ = Subtract8(ref r, accumulator, value, borrowIn: false);
                if (accumulatorA) { SetFlagGroup(M6809FlagGroup.ZeroSet); }
                return;
            case 0x2:
                result = Subtract8(ref r, accumulator, value, (r.CC & (byte)Carry) != 0);
                break;
            case 0x4:
                result = (byte)(accumulator & value);
                SetNZ8(ref r, result);
                r.CC &= unchecked((byte)~Overflow);
                break;
            case 0x5:
                SetNZ8(ref r, (byte)(accumulator & value));
                r.CC &= unchecked((byte)~Overflow);
                if (accumulatorA) { SetFlagGroup(M6809FlagGroup.ZeroSet); }
                return;
            case 0x6:
                result = value;
                SetNZ8(ref r, result);
                r.CC &= unchecked((byte)~Overflow);
                break;
            case 0x8:
                result = (byte)(accumulator ^ value);
                SetNZ8(ref r, result);
                r.CC &= unchecked((byte)~Overflow);
                break;
            case 0x9:
                result = Add8(ref r, accumulator, value, (r.CC & (byte)Carry) != 0);
                break;
            case 0xA:
                result = (byte)(accumulator | value);
                SetNZ8(ref r, result);
                r.CC &= unchecked((byte)~Overflow);
                break;
            default:
                result = Add8(ref r, accumulator, value, carryIn: false);
                break;
        }

        if (accumulatorA) { r.A = result; }
        else { r.B = result; }

        if (accumulatorA)
        {
            SetFlagGroup(operation switch
            {
                0x1 or 0x5 => M6809FlagGroup.ZeroSet,
                0x6 => M6809FlagGroup.AccumulatorA,
                _ => M6809FlagGroup.AccumulatorAInverted
            });
        }
    }

    private void ApplyLoad16(ref M6809Registers r, ushort value)
    {
        if (_state.Page == 0x10)
        {
            if (_state.Opcode >= 0xCE)
            {
                r.S = value;
                r.NmiArmed = true;
            }
            else
            {
                r.Y = value;
            }
        }
        else if ((_state.Opcode & 0x0F) == 0x0C)
        {
            r.D = value;
            SetFlagGroup(M6809FlagGroup.AccumulatorA);
        }
        else if (_state.Opcode >= 0xC0)
        {
            r.U = value;
        }
        else
        {
            r.X = value;
        }

        SetNZ16(ref r, value);
        r.CC &= unchecked((byte)~Overflow);
    }

    private void ApplyAlu16(ref M6809Registers r, ushort value)
    {
        if (_state.Page == 0)
        {
            int low = _state.Opcode & 0x0F;
            if (low == 0x03)
            {
                if (_state.Opcode >= 0xC0)
                {
                    r.D = Add16(ref r, r.D, value);
                }
                else
                {
                    r.D = Subtract16(ref r, r.D, value, borrowIn: false);
                    SetFlagGroup(M6809FlagGroup.AccumulatorADecrement);
                }
            }
            else
            {
                ushort compare = Subtract16(ref r, r.X, value, borrowIn: false);
                SetFlagGroup(M6809FlagGroup.LatchedDecrement, (byte)(compare >> 8));
            }

            return;
        }

        ushort result;
        if (_state.Opcode >= 0xC0)
        {
            // The undocumented XADDD and XADDU add as ADDD does without storing the sum; XADDU adds to U with
            // its high byte forced to $FF (Banks's wiki).
            result = _state.Page == 0x10
                ? Add16(ref r, r.D, value)
                : Add16(ref r, (ushort)(r.U | 0xFF00), value);
        }
        else
        {
            ushort lhs = _state.Page == 0x10
                ? (_state.Opcode & 0x0F) == 0x03 ? r.D : r.Y
                : (_state.Opcode & 0x0F) == 0x03 ? r.U : r.S;

            result = Subtract16(ref r, lhs, value, borrowIn: false);
        }

        SetFlagGroup(M6809FlagGroup.LatchedDecrement, (byte)(result >> 8));
    }

    private static byte Unary(ref M6809Registers r, byte operation, byte value)
    {
        byte result;
        int flags;

        // XNC ($x2) is NEG when C is clear and COM when C is set.
        if (operation == 0x2)
        {
            operation = (r.CC & (byte)Carry) != 0 ? (byte)0x3 : (byte)0x0;
        }

        switch (operation)
        {
            case 0x0:
            case 0x1:
                result = (byte)-value;
                flags = (r.CC & ~(byte)(Negative | Zero | Overflow | Carry))
                    | ((result & 0x80) != 0 ? (byte)Negative : 0)
                    | (result == 0 ? (byte)Zero : 0)
                    | (value == 0x80 ? (byte)Overflow : 0)
                    | (value != 0 ? (byte)Carry : 0);

                r.CC = (byte)flags;
                return result;
            case 0x3:
                result = (byte)~value;
                SetNZ8(ref r, result);
                r.CC = (byte)((r.CC & ~(byte)Overflow) | (byte)Carry);
                return result;
            case 0x4:
            case 0x5:
                result = (byte)(value >> 1);
                flags = (r.CC & ~(byte)(Negative | Zero | Carry))
                    | (result == 0 ? (byte)Zero : 0)
                    | ((value & 1) != 0 ? (byte)Carry : 0);

                r.CC = (byte)flags;
                return result;
            case 0x6:
                result = (byte)((value >> 1) | ((r.CC & (byte)Carry) << 7));
                SetNZ8(ref r, result);
                SetRightShiftCarry(ref r, value);
                return result;
            case 0x7:
                result = (byte)((value >> 1) | (value & 0x80));
                SetNZ8(ref r, result);
                SetRightShiftCarry(ref r, value);
                return result;
            case 0x8:
                result = (byte)(value << 1);
                SetNZ8(ref r, result);
                flags = (r.CC & ~(byte)(Overflow | Carry))
                    | ((((result & 0x80) != 0) ^ ((value & 0x80) != 0)) ? (byte)Overflow : 0)
                    | ((value & 0x80) != 0 ? (byte)Carry : 0);

                r.CC = (byte)flags;
                return result;
            case 0x9:
                result = (byte)((value << 1) | ((r.CC & (byte)Carry) != 0 ? 1 : 0));
                SetNZ8(ref r, result);
                flags = (r.CC & ~(byte)(Overflow | Carry))
                    | ((((result & 0x80) != 0) ^ ((value & 0x80) != 0)) ? (byte)Overflow : 0)
                    | ((value & 0x80) != 0 ? (byte)Carry : 0);

                r.CC = (byte)flags;
                return result;
            case 0xA:
                result = (byte)(value - 1);
                SetNZ8(ref r, result);
                r.CC = (byte)((r.CC & ~(byte)Overflow) | (value == 0x80 ? (byte)Overflow : 0));
                return result;
            case 0xB:
                // XDEC: DEC, with C cleared when the operand is zero and set otherwise.
                result = (byte)(value - 1);
                SetNZ8(ref r, result);
                flags = (r.CC & ~(byte)(Overflow | Carry))
                    | (value == 0x80 ? (byte)Overflow : 0)
                    | (value != 0 ? (byte)Carry : 0);

                r.CC = (byte)flags;
                return result;
            case 0xC:
                result = (byte)(value + 1);
                SetNZ8(ref r, result);
                r.CC = (byte)((r.CC & ~(byte)Overflow) | (value == 0x7F ? (byte)Overflow : 0));
                return result;
            case 0xD:
                SetNZ8(ref r, value);
                r.CC &= unchecked((byte)~Overflow);
                return value;
            case 0xE:
                // XCLRA and XCLRB: CLR with C unchanged.
                r.CC = (byte)((r.CC & ~(byte)(Negative | Overflow)) | (byte)Zero);
                return 0;
            default:
                r.CC = (byte)((r.CC & ~(byte)(Negative | Overflow | Carry)) | (byte)Zero);
                return 0;
        }
    }

    private static void SetRightShiftCarry(ref M6809Registers r, byte value)
    {
        if ((value & 1) != 0)
        {
            r.CC |= (byte)Carry;
        }
        else
        {
            r.CC &= unchecked((byte)~Carry);
        }
    }

    private static void DecimalAdjust(ref M6809Registers r)
    {
        int correction = 0;
        bool carry = (r.CC & (byte)Carry) != 0;
        if ((r.A & 0x0F) > 9 || (r.CC & (byte)HalfCarry) != 0)
        {
            correction |= 0x06;
        }

        if (r.A > 0x99 || carry)
        {
            correction |= 0x60;
        }

        int result = r.A + correction;
        r.A = (byte)result;
        // V is the new C XOR the new bit 7 of A, though the datasheet says cleared (Banks's wiki).
        bool newCarry = result > 0xFF || carry;
        int flags = (r.CC & ~(byte)(Negative | Zero | Overflow | Carry))
            | ((r.A & 0x80) != 0 ? (byte)Negative : 0)
            | (r.A == 0 ? (byte)Zero : 0)
            | (newCarry != ((r.A & 0x80) != 0) ? (byte)Overflow : 0)
            | (newCarry ? (byte)Carry : 0);

        r.CC = (byte)flags;
    }

    // Flamand, page 8: 16 bits to 8 keeps the low byte; A or B to 16 bits is $FF:r, CC or DP is r:r; an undefined
    // source reads $FF or $FFFF and an undefined destination is not written. EXG is three transfers through a
    // temporary: the low-nibble register to it, the high-nibble register to the low, then it to the high.
    private static void ApplyTransferExchange(ref M6809Registers r, byte postbyte, bool transfer)
    {
        byte high = (byte)(postbyte >> 4);
        byte low = (byte)(postbyte & 0x0F);
        if (transfer)
        {
            SetTransferRegister(ref r, low, ReadTransferRegister(in r, high, IsWideTransferRegister(low)));
            return;
        }

        bool lowWide = IsWideTransferRegister(low);
        bool highWide = IsWideTransferRegister(high);
        ushort temporary = ReadTransferRegister(in r, low, highWide);
        SetTransferRegister(ref r, low, ReadTransferRegister(in r, high, lowWide));

        // The temporary keeps the size it was read at, so an 8-bit value reaches a 16-bit register as $FF:r.
        SetTransferRegister(
            ref r,
            high,
            highWide && !lowWide && IsDefinedTransferRegister(low) ? (ushort)(0xFF00 | (byte)temporary) : temporary);
    }

    private static bool IsWideTransferRegister(byte code) => code < 8;

    private static bool IsDefinedTransferRegister(byte code) => code is <= 5 or (>= 8 and <= 11);

    private static ushort ReadTransferRegister(in M6809Registers r, byte code, bool wide)
    {
        ushort value = code switch
        {
            0 => r.D,
            1 => r.X,
            2 => r.Y,
            3 => r.U,
            4 => r.S,
            5 => r.PC,
            8 => (ushort)(0xFF00 | r.A),
            9 => (ushort)(0xFF00 | r.B),
            10 => (ushort)((r.CC << 8) | r.CC),
            11 => (ushort)((r.DP << 8) | r.DP),
            _ => 0xFFFF
        };

        return wide ? value : (byte)value;
    }

    private static void SetTransferRegister(ref M6809Registers r, byte code, ushort value)
    {
        switch (code)
        {
            case 0:
                r.D = value;
                return;
            case 1:
                r.X = value;
                return;
            case 2:
                r.Y = value;
                return;
            case 3:
                r.U = value;
                return;
            case 4:
                r.S = value;
                r.NmiArmed = true;
                return;
            case 5:
                r.PC = value;
                return;
            case 8:
                r.A = (byte)value;
                return;
            case 9:
                r.B = (byte)value;
                return;
            case 10:
                r.CC = (byte)value;
                return;
            case 11:
                r.DP = (byte)value;
                return;
        }
    }

    private static bool BranchCondition(byte cc, byte condition) => condition switch
    {
        0 => true,
        1 => false,
        2 => (cc & (byte)(Carry | Zero)) == 0,
        3 => (cc & (byte)(Carry | Zero)) != 0,
        4 => (cc & (byte)Carry) == 0,
        5 => (cc & (byte)Carry) != 0,
        6 => (cc & (byte)Zero) == 0,
        7 => (cc & (byte)Zero) != 0,
        8 => (cc & (byte)Overflow) == 0,
        9 => (cc & (byte)Overflow) != 0,
        10 => (cc & (byte)Negative) == 0,
        11 => (cc & (byte)Negative) != 0,
        12 => ((cc & (byte)Negative) == 0) == ((cc & (byte)Overflow) == 0),
        13 => ((cc & (byte)Negative) == 0) != ((cc & (byte)Overflow) == 0),
        14 => (cc & (byte)Zero) == 0 && (((cc & (byte)Negative) == 0) == ((cc & (byte)Overflow) == 0)),
        _ => (cc & (byte)Zero) != 0 || (((cc & (byte)Negative) == 0) != ((cc & (byte)Overflow) == 0))
    };

    private static void SetNZ8(ref M6809Registers r, byte value)
    {
        int flags = (r.CC & ~(byte)(Negative | Zero))
            | ((value & 0x80) != 0 ? (byte)Negative : 0)
            | (value == 0 ? (byte)Zero : 0);

        r.CC = (byte)flags;
    }

    private static void SetNZ16(ref M6809Registers r, ushort value)
    {
        int flags = (r.CC & ~(byte)(Negative | Zero))
            | ((value & 0x8000) != 0 ? (byte)Negative : 0)
            | (value == 0 ? (byte)Zero : 0);

        r.CC = (byte)flags;
    }

    private static void SetZeroOnly(ref M6809Registers r, ushort value)
    {
        r.CC = (byte)((r.CC & ~(byte)Zero) | (value == 0 ? (byte)Zero : 0));
    }

    private static byte Add8(ref M6809Registers r, byte left, byte right, bool carryIn)
    {
        int carry = carryIn ? 1 : 0;
        int sum = left + right + carry;
        byte result = (byte)sum;
        int flags = (r.CC & ~(byte)(HalfCarry | Negative | Zero | Overflow | Carry))
            | ((((left & 0x0F) + (right & 0x0F) + carry) > 0x0F) ? (byte)HalfCarry : 0)
            | ((result & 0x80) != 0 ? (byte)Negative : 0)
            | (result == 0 ? (byte)Zero : 0)
            | (((~(left ^ right) & (left ^ result) & 0x80) != 0) ? (byte)Overflow : 0)
            | (sum > 0xFF ? (byte)Carry : 0);

        r.CC = (byte)flags;
        return result;
    }

    private static byte Subtract8(ref M6809Registers r, byte left, byte right, bool borrowIn)
    {
        int borrow = borrowIn ? 1 : 0;
        int difference = left - right - borrow;
        byte result = (byte)difference;
        int flags = (r.CC & ~(byte)(Negative | Zero | Overflow | Carry))
            | ((result & 0x80) != 0 ? (byte)Negative : 0)
            | (result == 0 ? (byte)Zero : 0)
            | (((left ^ right) & (left ^ result) & 0x80) != 0 ? (byte)Overflow : 0)
            | (difference < 0 ? (byte)Carry : 0);

        r.CC = (byte)flags;
        return result;
    }

    private static ushort Add16(ref M6809Registers r, ushort left, ushort right)
    {
        uint sum = (uint)left + right;
        ushort result = (ushort)sum;
        int flags = (r.CC & ~(byte)(Negative | Zero | Overflow | Carry))
            | ((result & 0x8000) != 0 ? (byte)Negative : 0)
            | (result == 0 ? (byte)Zero : 0)
            | (((~(left ^ right) & (left ^ result) & 0x8000) != 0) ? (byte)Overflow : 0)
            | (sum > 0xFFFF ? (byte)Carry : 0);

        r.CC = (byte)flags;
        return result;
    }

    private static ushort Subtract16(ref M6809Registers r, ushort left, ushort right, bool borrowIn)
    {
        int difference = left - right - (borrowIn ? 1 : 0);
        ushort result = (ushort)difference;
        int flags = (r.CC & ~(byte)(Negative | Zero | Overflow | Carry))
            | ((result & 0x8000) != 0 ? (byte)Negative : 0)
            | (result == 0 ? (byte)Zero : 0)
            | (((left ^ right) & (left ^ result) & 0x8000) != 0 ? (byte)Overflow : 0)
            | (difference < 0 ? (byte)Carry : 0);

        r.CC = (byte)flags;
        return result;
    }
}
