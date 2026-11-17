// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.I8080.I8080Flags;

namespace Retrocore.Cpu.I8080;

public sealed partial class I8080Processor<TBus>
{
    // Registers by index: B C D E H L - A; 6 is M, which callers handle.
    private byte Get(int register)
    {
        ref I8080Registers r = ref _state.Registers;
        return register switch
        {
            0 => r.B,
            1 => r.C,
            2 => r.D,
            3 => r.E,
            4 => r.H,
            5 => r.L,
            _ => r.A
        };
    }

    private void Set(int register, byte value)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (register)
        {
            case 0: r.B = value;
                break;
            case 1: r.C = value;
                break;
            case 2: r.D = value;
                break;
            case 3: r.E = value;
                break;
            case 4: r.H = value;
                break;
            case 5: r.L = value;
                break;
            default: r.A = value;
                break;
        }
    }

    // Pairs by index: B D H, then SP, or PSW for PUSH and POP.
    private ushort GetPair(int pair, bool psw)
    {
        ref I8080Registers r = ref _state.Registers;
        return pair switch
        {
            0 => r.BC,
            1 => r.DE,
            2 => r.HL,
            _ => psw ? r.PSW : r.SP
        };
    }

    private void SetPair(int pair, ushort value, bool psw)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (pair)
        {
            case 0: r.BC = value;
                break;
            case 1: r.DE = value;
                break;
            case 2: r.HL = value;
                break;
            default:
                if (!psw)
                {
                    r.SP = value;
                    break;
                }

                // POP PSW keeps only the flag bits the CPU has.
                r.A = (byte)(value >> 8);
                r.F = NormalizeFlags((byte)value);
                break;
        }
    }

    // INX and DCX change no flags but the 8085's K, which is the carry out of the 16-bit incrementer: set when
    // INX wraps from $FFFF to 0 or DCX from 0 to $FFFF.
    private void StepPair(int pair, int step)
    {
        ushort value = (ushort)(GetPair(pair, psw: false) + step);
        SetPair(pair, value, psw: false);
        if (!Is8085) { return; }
        bool wrapped = step > 0 ? value == 0 : value == 0xFFFF;
        ref I8080Registers r = ref _state.Registers;
        r.F = (byte)((r.F & ~K) | (wrapped ? K : 0));
    }

    // Sets the flags of an 8-bit result. On the 8085, V is the overflow and K is V exclusive-or S, as Ken Shirriff
    // traced them in the silicon; on the 8080 bit 1 reads 1.
    private void SetFlags(byte result, bool carry, bool auxiliary, bool overflow)
    {
        int flags = SignZeroParity[result] | (carry ? CY : 0) | (auxiliary ? AC : 0);
        if (Is8085)
        {
            if (overflow) { flags |= V; }
            if (overflow != ((result & S) != 0)) { flags |= K; }
        }
        else
        {
            flags |= V;
        }

        _state.Registers.F = (byte)flags;
    }

    private bool Carry => (_state.Registers.F & CY) != 0;

    private void SetCarry(bool carry)
    {
        ref I8080Registers r = ref _state.Registers;
        r.F = (byte)((r.F & ~CY) | (carry ? CY : 0));
    }

    // Adds with a carry in: the flags from the carries out of bits 3, 6 and 7.
    private byte Add(byte left, byte right, int carryIn)
    {
        int sum = left + right + carryIn;
        bool auxiliary = ((left & 0x0F) + (right & 0x0F) + carryIn) > 0x0F;
        bool carry7 = ((left & 0x7F) + (right & 0x7F) + carryIn) > 0x7F;
        bool carry = sum > 0xFF;
        SetFlags((byte)sum, carry, auxiliary, carry7 != carry);
        return (byte)sum;
    }

    // Subtracts as the ALU does, adding the complement with the inverted borrow: the carry is the borrow, and AC
    // is the carry out of bit 3 of that addition.
    private byte Subtract(byte left, byte right, int borrow)
    {
        byte complement = (byte)~right;
        int carryIn = 1 - borrow;
        int sum = left + complement + carryIn;
        bool auxiliary = ((left & 0x0F) + (complement & 0x0F) + carryIn) > 0x0F;
        bool carry7 = ((left & 0x7F) + (complement & 0x7F) + carryIn) > 0x7F;
        bool carry = sum > 0xFF;
        SetFlags((byte)sum, !carry, auxiliary, carry7 != carry);
        return (byte)sum;
    }

    // ADD ADC SUB SBB ANA XRA ORA CMP by index.
    private void Arithmetic(int operation, byte value)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (operation)
        {
            case 0:
                r.A = Add(r.A, value, 0);
                break;
            case 1:
                r.A = Add(r.A, value, Carry ? 1 : 0);
                break;
            case 2:
                r.A = Subtract(r.A, value, 0);
                break;
            case 3:
                r.A = Subtract(r.A, value, Carry ? 1 : 0);
                break;
            case 4:
                // ANA sets AC from bit 3 of the operands ORed on the 8080, and always on the 8085.
                bool auxiliary = Is8085 || ((r.A | value) & 0x08) != 0;
                r.A &= value;
                SetFlags(r.A, carry: false, auxiliary, overflow: false);
                break;
            case 5:
                r.A ^= value;
                SetFlags(r.A, carry: false, auxiliary: false, overflow: false);
                break;
            case 6:
                r.A |= value;
                SetFlags(r.A, carry: false, auxiliary: false, overflow: false);
                break;
            default:
                Subtract(r.A, value, 0);
                break;
        }
    }

    // INR and DCR keep the carry.
    private byte Increment(byte value)
    {
        bool carry = Carry;
        byte result = Add(value, 1, 0);
        SetCarry(carry);
        return result;
    }

    private byte Decrement(byte value)
    {
        bool carry = Carry;
        byte result = Subtract(value, 1, 0);
        SetCarry(carry);
        return result;
    }

    // DAD: HL plus a pair; only the carry changes.
    private void AddPair(ushort value)
    {
        ref I8080Registers r = ref _state.Registers;
        int sum = r.HL + value;
        r.HL = (ushort)sum;
        SetCarry(sum > 0xFFFF);
    }

    // DSUB (8085): HL minus BC, as two 8-bit subtractions; Z is for the whole word.
    private void SubtractPair(ushort value)
    {
        ref I8080Registers r = ref _state.Registers;
        byte low = Subtract(r.L, (byte)value, 0);
        byte high = Subtract(r.H, (byte)(value >> 8), Carry ? 1 : 0);
        r.HL = (ushort)((high << 8) | low);
        r.F = (byte)((r.F & ~Z) | (r.HL == 0 ? Z : 0));
    }

    // RDEL (8085): DE rotates left through the carry; V is set when bit 15 changes.
    private void RotateDE()
    {
        ref I8080Registers r = ref _state.Registers;
        ushort de = r.DE;
        int rotated = (de << 1) | (Carry ? 1 : 0);
        r.DE = (ushort)rotated;
        bool overflow = ((de ^ rotated) & 0x8000) != 0;
        r.F = (byte)((r.F & ~(CY | V)) | ((rotated & 0x10000) != 0 ? CY : 0) | (overflow ? V : 0));
    }

    // RLC RRC RAL RAR DAA CMA STC CMC by index.
    private void Accumulator(int operation)
    {
        ref I8080Registers r = ref _state.Registers;
        byte a = r.A;
        switch (operation)
        {
            case 0:
                r.A = (byte)((a << 1) | (a >> 7));
                SetCarry((a & 0x80) != 0);
                break;
            case 1:
                r.A = (byte)((a >> 1) | (a << 7));
                SetCarry((a & 1) != 0);
                break;
            case 2:
                r.A = (byte)((a << 1) | (Carry ? 1 : 0));
                SetCarry((a & 0x80) != 0);
                break;
            case 3:
                r.A = (byte)((a >> 1) | (Carry ? 0x80 : 0));
                SetCarry((a & 1) != 0);
                break;
            case 4:
                DecimalAdjust();
                break;
            case 5:
                r.A = (byte)~a;
                break;
            case 6:
                SetCarry(carry: true);
                break;
            default:
                SetCarry(!Carry);
                break;
        }
    }

    // DAA adds 6 to each digit that is over 9 or carried, then keeps the carry if it was set.
    private void DecimalAdjust()
    {
        ref I8080Registers r = ref _state.Registers;
        byte a = r.A;
        bool carry = Carry;
        int correction = 0;
        if ((r.F & AC) != 0 || (a & 0x0F) > 9) { correction = 0x06; }
        if (carry || (a >> 4) > 9 || ((a >> 4) >= 9 && (a & 0x0F) > 9))
        {
            correction |= 0x60;
            carry = true;
        }

        r.A = Add(a, (byte)correction, 0);
        SetCarry(carry);
    }
}
