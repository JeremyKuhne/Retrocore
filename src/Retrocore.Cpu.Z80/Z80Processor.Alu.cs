// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.Z80.Z80Flags;

namespace Retrocore.Cpu.Z80;

public sealed partial class Z80Processor<TBus>
{
    // Register index 0-7: B C D E H L - A. After DD or FD, H and L are the index register's halves unless
    // the instruction also addresses memory through it.
    private byte Get(int register, bool halves)
    {
        ref Z80Registers r = ref _state.Registers;
        return register switch
        {
            0 => r.B,
            1 => r.C,
            2 => r.D,
            3 => r.E,
            4 => halves && _state.Index != 0 ? (byte)(Index >> 8) : r.H,
            5 => halves && _state.Index != 0 ? (byte)Index : r.L,
            _ => r.A
        };
    }

    private void Set(int register, byte value, bool halves)
    {
        ref Z80Registers r = ref _state.Registers;
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
            case 4:
                if (halves && _state.Index != 0) { Index = (ushort)((value << 8) | (byte)Index); }
                else { r.H = value; }
                break;
            case 5:
                if (halves && _state.Index != 0) { Index = (ushort)((Index & 0xFF00) | value); }
                else { r.L = value; }
                break;
            default: r.A = value;
                break;
        }
    }

    // HL, or IX or IY after a prefix.
    private ushort Index
    {
        get => _state.Index switch
        {
            0 => _state.Registers.HL,
            1 => _state.Registers.IX,
            _ => _state.Registers.IY
        };

        set
        {
            switch (_state.Index)
            {
                case 0: _state.Registers.HL = value;
                    break;
                case 1: _state.Registers.IX = value;
                    break;
                default: _state.Registers.IY = value;
                    break;
            }
        }
    }

    // Pair index 0-3: BC DE HL SP, with HL the index register after a prefix; AF replaces SP for PUSH and POP.
    private ushort GetPair(int pair, bool accumulator) => pair switch
    {
        0 => _state.Registers.BC,
        1 => _state.Registers.DE,
        2 => Index,
        _ => accumulator ? _state.Registers.AF : _state.Registers.SP
    };

    private void SetPair(int pair, ushort value, bool accumulator)
    {
        switch (pair)
        {
            case 0: _state.Registers.BC = value;
                break;
            case 1: _state.Registers.DE = value;
                break;
            case 2: Index = value;
                break;
            default:
                if (accumulator) { _state.Registers.AF = value; }
                else { _state.Registers.SP = value; }
                break;
        }
    }

    private void SetFlags(int flags)
    {
        _state.Registers.F = (byte)flags;
        _state.FlagsWritten = true;
    }

    // Condition 0-7: NZ Z NC C PO PE P M.
    private bool Condition(int condition)
    {
        byte f = _state.Registers.F;
        bool set = (condition >> 1) switch
        {
            0 => (f & Z) != 0,
            1 => (f & C) != 0,
            2 => (f & PV) != 0,
            _ => (f & S) != 0
        };

        return (condition & 1) == 0 ? !set : set;
    }

    // ALU operation 0-7: ADD ADC SUB SBC AND XOR OR CP, with A.
    private void Arithmetic(int operation, byte value)
    {
        ref Z80Registers r = ref _state.Registers;
        int a = r.A;
        int carry = r.F & C;
        int result;
        switch (operation)
        {
            case 0:
            case 1:
                result = a + value + (operation == 1 ? carry : 0);
                int overflow = ((value ^ a ^ 0x80) & (value ^ result) & 0x80) >> 5;
                SetFlags(SignZero[result & 0xFF] | ((result >> 8) & C) | ((a ^ result ^ value) & H) | overflow);

                r.A = (byte)result;
                return;
            case 2:
            case 3:
            case 7:
                result = a - value - (operation == 3 ? carry : 0);
                int flags = ((result >> 8) & C) | N | ((a ^ result ^ value) & H) | (((value ^ a) & (a ^ result) & 0x80) >> 5);

                // CP takes X and Y from the operand, since it keeps no result.
                SetFlags(operation == 7
                    ? flags | (SignZero[result & 0xFF] & ~XY) | (value & XY)
                    : flags | SignZero[result & 0xFF]);

                if (operation != 7) { r.A = (byte)result; }
                return;
            case 4:
                r.A &= value;
                SetFlags(SignZeroParity[r.A] | H);
                return;
            case 5:
                r.A ^= value;
                SetFlags(SignZeroParity[r.A]);
                return;
            default:
                r.A |= value;
                SetFlags(SignZeroParity[r.A]);
                return;
        }
    }

    private byte Increment(byte value)
    {
        byte result = (byte)(value + 1);
        SetFlags((_state.Registers.F & C) | SignZero[result] | (result == 0x80 ? PV : 0) | ((result & 0x0F) == 0 ? H : 0));
        return result;
    }

    private byte Decrement(byte value)
    {
        byte result = (byte)(value - 1);
        SetFlags((_state.Registers.F & C) | SignZero[result] | N | (result == 0x7F ? PV : 0) | ((result & 0x0F) == 0x0F ? H : 0));
        return result;
    }

    // CB rotate or shift 0-7: RLC RRC RL RR SLA SRA SLL SRL.
    private byte Shift(int operation, byte value)
    {
        int carryIn = _state.Registers.F & C;
        (int result, int carry) = operation switch
        {
            0 => ((value << 1) | (value >> 7), value >> 7),
            1 => ((value >> 1) | (value << 7), value & 1),
            2 => ((value << 1) | carryIn, value >> 7),
            3 => ((value >> 1) | (carryIn << 7), value & 1),
            4 => (value << 1, value >> 7),
            5 => ((value >> 1) | (value & 0x80), value & 1),
            6 => ((value << 1) | 1, value >> 7),
            _ => (value >> 1, value & 1)
        };

        byte shifted = (byte)result;
        SetFlags(SignZeroParity[shifted] | carry);
        return shifted;
    }

    // BIT: Z and PV from the bit, S when bit 7 is set, X and Y from the given source.
    private void TestBit(int bit, byte value, int xy)
    {
        int tested = value & (1 << bit);
        SetFlags((_state.Registers.F & C) | H | (tested == 0 ? Z | PV : 0) | (tested & S) | (xy & XY));
    }

    // RLCA RRCA RLA RRA DAA CPL SCF CCF.
    private void Accumulator(int operation)
    {
        ref Z80Registers r = ref _state.Registers;
        int f = r.F;
        int a = r.A;
        int kept = f & (S | Z | PV);
        switch (operation)
        {
            case 0:
                a = ((a << 1) | (a >> 7)) & 0xFF;
                SetFlags(kept | (a & (XY | C)));
                break;
            case 1:
                SetFlags(kept | (a & C) | (((a >> 1) | (a << 7)) & XY));
                a = ((a >> 1) | (a << 7)) & 0xFF;
                break;
            case 2:
                int left = ((a << 1) | (f & C)) & 0xFF;
                SetFlags(kept | (a >> 7) | (left & XY));
                a = left;
                break;
            case 3:
                int right = (a >> 1) | ((f & C) << 7);
                SetFlags(kept | (a & C) | (right & XY));
                a = right;
                break;
            case 4:
                int adjusted = a;
                int correction = ((f & H) != 0 || (a & 0x0F) > 9 ? 0x06 : 0) | ((f & C) != 0 || a > 0x99 ? 0x60 : 0);
                adjusted = (f & N) != 0 ? adjusted - correction : adjusted + correction;
                SetFlags((f & (C | N)) | (a > 0x99 ? C : 0) | ((a ^ adjusted) & H) | SignZeroParity[adjusted & 0xFF]);
                a = adjusted & 0xFF;
                break;
            case 5:
                a ^= 0xFF;
                SetFlags((f & (S | Z | PV | C)) | H | N | (a & XY));
                break;
            case 6:
                // SCF and CCF take X and Y from A, ORed with the flags unless the last instruction wrote them.
                SetFlags(kept | C | (((r.Q ^ f) | a) & XY));
                break;
            default:
                SetFlags((kept | ((f & C) << 4) | (((r.Q ^ f) | a) & XY) | (f & C)) ^ C);
                break;
        }

        r.A = (byte)a;
    }

    // ADD HL,rr: H from bit 11, C from bit 15, X and Y from the high byte; WZ is HL+1.
    private void AddPair(ushort value)
    {
        int hl = Index;
        int result = hl + value;
        _state.Registers.WZ = (ushort)(hl + 1);
        SetFlags((_state.Registers.F & (S | Z | PV)) | (((hl ^ result ^ value) >> 8) & H) | ((result >> 16) & C) | ((result >> 8) & XY));
        Index = (ushort)result;
    }

    // ADC HL,rr and SBC HL,rr.
    private void CarryPair(ushort value, bool subtract)
    {
        int hl = _state.Registers.HL;
        int carry = _state.Registers.F & C;
        int result = subtract ? hl - value - carry : hl + value + carry;
        int overflow = subtract
            ? ((value ^ hl) & (hl ^ result) & 0x8000) >> 13
            : ((value ^ hl ^ 0x8000) & (value ^ result) & 0x8000) >> 13;

        _state.Registers.WZ = (ushort)(hl + 1);
        int bits = (((hl ^ result ^ value) >> 8) & H) | ((result >> 16) & C) | ((result >> 8) & (S | XY));
        SetFlags(bits | ((result & 0xFFFF) == 0 ? Z : 0) | overflow | (subtract ? N : 0));

        _state.Registers.HL = (ushort)result;
    }
}
