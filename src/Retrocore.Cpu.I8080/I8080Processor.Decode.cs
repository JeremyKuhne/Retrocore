// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.I8080.I8080Flags;

namespace Retrocore.Cpu.I8080;

public sealed partial class I8080Processor<TBus>
{
    private const int MemoryOperand = 6;

    // Conditions: NZ Z NC C PO PE P M are 0-7, as the opcodes number them.
    private const byte Always = 8;
    private const byte NotK = 9;
    private const byte KSet = 10;
    private const byte VSet = 11;

    // The idle states after T4 of M1 for the instructions with a long M1: one on the 8080 (5 states), two on
    // the 8085 (6 states).
    private byte LongFetch => Is8085 ? (byte)2 : (byte)1;

    // The 8080's undocumented opcodes act as NOP, JMP, RET and CALL.
    private static byte Canonical8080(byte opcode) => opcode switch
    {
        0x08 or 0x10 or 0x18 or 0x20 or 0x28 or 0x30 or 0x38 => 0x00,
        0xCB => 0xC3,
        0xD9 => 0xC9,
        0xDD or 0xED or 0xFD => 0xCD,
        _ => opcode
    };

    // Starts an operation at a step, which runs at once to choose its first machine cycle.
    private void Start(I8080Operation operation, int register = 0, int selector = 0, int step = 0)
    {
        _state.Operation = operation;
        _state.Step = (byte)step;
        _state.Register = (byte)register;
        _state.Selector = (byte)selector;
        Execute();
    }

    private void StartDelay(byte length)
    {
        _state.Operation = I8080Operation.Delay;
        Internal(length);
    }

    // An opcode was fetched or acknowledged: x = bits 6-7, y = bits 3-5, z = bits 0-2, p = y / 2, q = y % 2.
    private void Decode(byte opcode)
    {
        ref I8080Registers r = ref _state.Registers;
        _state.Opcode = opcode;
        r.AfterEnable = false;
        if (!Is8085) { opcode = Canonical8080(opcode); }
        int x = opcode >> 6;
        int y = (opcode >> 3) & 7;
        int z = opcode & 7;
        int p = y >> 1;
        int q = y & 1;
        switch (x)
        {
            case 0:
                DecodeLow(y, z, p, q);
                return;
            case 1:
                if (opcode == 0x76)
                {
                    // HLT: 7 states on the 8080, 5 on the 8085, then the halt states.
                    _state.Operation = I8080Operation.Halt;
                    Internal(Is8085 ? (byte)1 : (byte)3);
                }
                else if (z == MemoryOperand)
                {
                    _state.Word = r.HL;
                    Start(I8080Operation.LoadMemory, y);
                }
                else if (y == MemoryOperand)
                {
                    _state.Word = r.HL;
                    Start(I8080Operation.StoreMemory, z);
                }
                else
                {
                    Set(y, Get(z));
                    FinishShort();
                }

                return;
            case 2:
                if (z == MemoryOperand)
                {
                    Start(I8080Operation.ArithmeticMemory, 0, y);
                }
                else
                {
                    Arithmetic(y, Get(z));
                    Finish();
                }

                return;
            default:
                DecodeHigh(y, z, p, q);
                return;
        }
    }

    private void DecodeLow(int y, int z, int p, int q)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (z)
        {
            case 0:
                DecodeSpecial(y);
                return;
            case 1:
                if (q == 0)
                {
                    Start(I8080Operation.LoadPairImmediate, p);
                }
                else
                {
                    // DAD: two bus-idle machine cycles of 3 states.
                    AddPair(GetPair(p, psw: false));
                    StartDelay(6);
                }

                return;
            case 2:
                switch ((q << 2) | p)
                {
                    case 0:
                    case 1:
                        _state.Word = GetPair(p, psw: false);
                        Start(I8080Operation.StoreMemory, 7);
                        return;
                    case 2:
                        Start(I8080Operation.StorePair);
                        return;
                    case 3:
                        Start(I8080Operation.StoreAbsolute);
                        return;
                    case 4:
                    case 5:
                        _state.Word = GetPair(p, psw: false);
                        Start(I8080Operation.LoadMemory, 7);
                        return;
                    case 6:
                        Start(I8080Operation.LoadPair);
                        return;
                    default:
                        Start(I8080Operation.LoadAbsolute);
                        return;
                }

            case 3:
                StepPair(p, q == 0 ? 1 : -1);
                StartDelay(LongFetch);
                return;
            case 4:
            case 5:
                if (y == MemoryOperand)
                {
                    Start(I8080Operation.StepMemory, 0, z - 4);
                    return;
                }

                Set(y, z == 4 ? Increment(Get(y)) : Decrement(Get(y)));
                FinishShort();
                return;
            case 6:
                Start(y == MemoryOperand ? I8080Operation.StoreImmediate : I8080Operation.LoadImmediate, y);
                return;
            default:
                Accumulator(y);
                Finish();
                return;
        }
    }

    // Opcodes $00-$38 with z = 0: NOP, and on the 8085 RIM, SIM and the undocumented DSUB, ARHL, RDEL, LDHI and
    // LDSI. The 8080's aliases were already made NOP.
    private void DecodeSpecial(int y)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (y)
        {
            case 0:
                Finish();
                return;
            case 1:
                SubtractPair(r.BC);
                StartDelay(6);
                return;
            case 2:
                // ARHL: arithmetic shift right of HL; bit 0 goes to the carry.
                SetCarry((r.L & 1) != 0);
                r.HL = (ushort)((short)r.HL >> 1);
                StartDelay(3);
                return;
            case 3:
                RotateDE();
                StartDelay(6);
                return;
            case 4:
                r.A = ReadInterruptMask();
                Finish();
                return;
            case 5:
                Start(I8080Operation.LoadOffset, 0);
                return;
            case 6:
                SetInterruptMask(r.A);
                Finish();
                return;
            default:
                Start(I8080Operation.LoadOffset, 1);
                return;
        }
    }

    private void DecodeHigh(int y, int z, int p, int q)
    {
        ref I8080Registers r = ref _state.Registers;
        switch (z)
        {
            case 0:
                Start(I8080Operation.Return, 0, y);
                return;
            case 1:
                if (q == 0)
                {
                    Start(I8080Operation.Pop, p);
                    return;
                }

                switch (p)
                {
                    case 0:
                        Start(I8080Operation.Return, 0, Always, step: 1);
                        return;
                    case 1:
                        // SHLX (8085): stores HL at [DE].
                        _state.Word = r.DE;
                        Start(I8080Operation.StorePair, step: 2);
                        return;
                    case 2:
                        r.PC = r.HL;
                        StartDelay(LongFetch);
                        return;
                    default:
                        r.SP = r.HL;
                        StartDelay(LongFetch);
                        return;
                }

            case 2:
                Start(I8080Operation.Jump, 0, y);
                return;
            case 3:
                switch (y)
                {
                    case 0:
                        Start(I8080Operation.Jump, 0, Always);
                        return;
                    case 1:
                        // RSTV (8085): restarts at $40 when V is set.
                        _state.Word = 0x0040;
                        Start(I8080Operation.Restart, 0, VSet);
                        return;
                    case 2:
                        Start(I8080Operation.Output);
                        return;
                    case 3:
                        Start(I8080Operation.Input);
                        return;
                    case 4:
                        Start(I8080Operation.ExchangeStack);
                        return;
                    case 5:
                        (r.DE, r.HL) = (r.HL, r.DE);
                        Finish();
                        return;
                    case 6:
                        r.InterruptEnable = false;
                        Finish();
                        return;
                    default:
                        r.InterruptEnable = true;
                        r.AfterEnable = true;
                        Finish();
                        return;
                }

            case 4:
                Start(I8080Operation.Call, 0, y);
                return;
            case 5:
                if (q == 0)
                {
                    Start(I8080Operation.Push, p);
                    return;
                }

                switch (p)
                {
                    case 0:
                        Start(I8080Operation.Call, 0, Always);
                        return;
                    case 1:
                        Start(I8080Operation.Jump, 0, NotK);
                        return;
                    case 2:
                        // LHLX (8085): loads HL from [DE].
                        _state.Word = r.DE;
                        Start(I8080Operation.LoadPair, step: 2);
                        return;
                    default:
                        Start(I8080Operation.Jump, 0, KSet);
                        return;
                }

            case 6:
                Start(I8080Operation.ArithmeticImmediate, 0, y);
                return;
            default:
                _state.Word = (ushort)(y << 3);
                Start(I8080Operation.Restart, 0, Always);
                return;
        }
    }

    // RIM (8085): SID, the pending RST 7.5 latch and RST 6.5 and 5.5 lines, IE, and the masks. Right after a
    // TRAP it reads IE as the TRAP found it.
    private byte ReadInterruptMask()
    {
        I8080Signals signals = _state.Signals;
        bool enable = _state.AfterTrap ? _state.TrapEnable : _state.Registers.InterruptEnable;
        _state.AfterTrap = false;
        int value = ((signals & I8080Signals.SerialInput) != 0 ? 0x80 : 0)
            | (_state.PendingRestart75 ? 0x40 : 0)
            | ((signals & I8080Signals.Restart65) != 0 ? 0x20 : 0)
            | ((signals & I8080Signals.Restart55) != 0 ? 0x10 : 0)
            | (enable ? 0x08 : 0)
            | (_state.Registers.InterruptMask & 7);

        return (byte)value;
    }

    // SIM (8085): bit 3 enables setting the masks from bits 0-2, bit 4 clears the RST 7.5 latch, and bit 6 enables
    // setting SOD from bit 7.
    private void SetInterruptMask(byte value)
    {
        ref I8080Registers r = ref _state.Registers;
        if ((value & 0x08) != 0) { r.InterruptMask = (byte)(value & 7); }
        if ((value & 0x10) != 0) { _state.PendingRestart75 = false; }
        if ((value & 0x40) != 0) { r.SerialOutput = (value & 0x80) != 0; }
    }

    // MOV r,r and INR/DCR r take 5 states on the 8080 and 4 on the 8085.
    private void FinishShort()
    {
        if (Is8085)
        {
            Finish();
            return;
        }

        StartDelay(1);
    }

    private bool Condition(byte condition)
    {
        byte f = _state.Registers.F;
        return condition switch
        {
            0 => (f & Z) == 0,
            1 => (f & Z) != 0,
            2 => (f & CY) == 0,
            3 => (f & CY) != 0,
            4 => (f & P) == 0,
            5 => (f & P) != 0,
            6 => (f & S) == 0,
            7 => (f & S) != 0,
            Always => true,
            NotK => (f & K) == 0,
            KSet => (f & K) != 0,
            _ => (f & V) != 0
        };
    }
}
