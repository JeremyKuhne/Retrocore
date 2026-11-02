// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.Z80.Z80Flags;

namespace Retrocore.Cpu.Z80;

public sealed partial class Z80Processor<TBus>
{
    // The step at which an instruction's memory operand address is ready.
    private const byte Located = 16;

    // Variant of an unconditional jump, call or return.
    private const byte Always = 8;

    // Runs the current step of the instruction family; each step ends by scheduling a cycle or finishing.
    private void Execute()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (_state.Operation)
        {
            case Z80Operation.Delay:
                Finish();
                return;
            case Z80Operation.LoadImmediate:
                if (Next() == 0)
                {
                    ReadOperand();
                }
                else
                {
                    Set(_state.Register, _state.Value, halves: true);
                    Finish();
                }

                return;
            case Z80Operation.LoadMemory:
                if (!Locate()) { return; }
                if (Next() == Located)
                {
                    Read(_state.Effective);
                }
                else
                {
                    Set(_state.Register, _state.Value, halves: false);
                    Finish();
                }

                return;
            case Z80Operation.StoreMemory:
                if (!Locate()) { return; }
                if (Next() == Located) { Write(_state.Effective, Get(_state.Register, halves: false)); }
                else { Finish(); }
                return;
            case Z80Operation.StoreImmediate:
                StoreImmediate();
                return;
            case Z80Operation.LoadIndirect:
            case Z80Operation.StoreIndirect:
                Indirect();
                return;
            case Z80Operation.LoadAbsolute:
            case Z80Operation.StoreAbsolute:
                Absolute();
                return;
            case Z80Operation.LoadPairImmediate:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        _state.Word = _state.Value;
                        ReadOperand();
                        return;
                    default:
                        SetPair(_state.Register, (ushort)(_state.Word | (_state.Value << 8)), accumulator: false);
                        Finish();
                        return;
                }

            case Z80Operation.LoadPairAbsolute:
            case Z80Operation.StorePairAbsolute:
                PairAbsolute();
                return;
            case Z80Operation.Push:
                switch (Next())
                {
                    case 0:
                        Internal(1);
                        return;
                    case 1:
                        Write(--r.SP, (byte)(GetPair(_state.Register, accumulator: true) >> 8));
                        return;
                    case 2:
                        Write(--r.SP, (byte)GetPair(_state.Register, accumulator: true));
                        return;
                    default:
                        Finish();
                        return;
                }

            case Z80Operation.Pop:
                switch (Next())
                {
                    case 0:
                        Read(r.SP++);
                        return;
                    case 1:
                        _state.Word = _state.Value;
                        Read(r.SP++);
                        return;
                    default:
                        SetPair(_state.Register, (ushort)(_state.Word | (_state.Value << 8)), accumulator: true);
                        Finish();
                        return;
                }

            case Z80Operation.ExchangeStack:
                ExchangeStack();
                return;
            case Z80Operation.ArithmeticImmediate:
                if (Next() == 0)
                {
                    ReadOperand();
                }
                else
                {
                    Arithmetic(_state.Variant, _state.Value);
                    Finish();
                }

                return;
            case Z80Operation.ArithmeticMemory:
                if (!Locate()) { return; }
                if (Next() == Located)
                {
                    Read(_state.Effective);
                }
                else
                {
                    Arithmetic(_state.Variant, _state.Value);
                    Finish();
                }

                return;
            case Z80Operation.StepMemory:
                if (!Locate()) { return; }
                switch (Next())
                {
                    case Located:
                        Read(_state.Effective);
                        return;
                    case Located + 1:
                        _state.Word = _state.Variant == 0 ? Increment(_state.Value) : Decrement(_state.Value);
                        Internal(1);
                        return;
                    case Located + 2:
                        Write(_state.Effective, (byte)_state.Word);
                        return;
                    default:
                        Finish();
                        return;
                }

            case Z80Operation.BitsMemory:
                BitsMemory();
                return;
            case Z80Operation.IndexBits:
                IndexBits();
                return;
            case Z80Operation.Jump:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        _state.Word = _state.Value;
                        ReadOperand();
                        return;
                    default:
                        r.WZ = (ushort)(_state.Word | (_state.Value << 8));
                        if (_state.Variant == Always || Condition(_state.Variant)) { r.PC = r.WZ; }
                        Finish();
                        return;
                }

            case Z80Operation.JumpRelative:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        if (_state.Variant == Always || Condition(_state.Variant)) { Branch(); }
                        else { Finish(); }
                        return;
                    default:
                        Finish();
                        return;
                }

            case Z80Operation.DecrementJump:
                switch (Next())
                {
                    case 0:
                        Internal(1);
                        return;
                    case 1:
                        ReadOperand();
                        return;
                    case 2:
                        if (--r.B != 0) { Branch(); }
                        else { Finish(); }
                        return;
                    default:
                        Finish();
                        return;
                }

            case Z80Operation.Call:
                Call();
                return;
            case Z80Operation.Return:
                Return();
                return;
            case Z80Operation.Restart:
                switch (Next())
                {
                    case 0:
                        Internal(1);
                        return;
                    case 1:
                        Write(--r.SP, (byte)(r.PC >> 8));
                        return;
                    case 2:
                        Write(--r.SP, (byte)r.PC);
                        return;
                    default:
                        r.PC = _state.Word;
                        r.WZ = r.PC;
                        Finish();
                        return;
                }

            case Z80Operation.InputImmediate:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        ushort port = (ushort)((r.A << 8) | _state.Value);
                        r.WZ = (ushort)(port + 1);
                        Input(port);
                        return;
                    default:
                        r.A = _state.Value;
                        Finish();
                        return;
                }

            case Z80Operation.OutputImmediate:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        r.WZ = (ushort)((r.A << 8) | ((_state.Value + 1) & 0xFF));
                        Output((ushort)((r.A << 8) | _state.Value), r.A);
                        return;
                    default:
                        Finish();
                        return;
                }

            case Z80Operation.InputPort:
                if (Next() == 0)
                {
                    r.WZ = (ushort)(r.BC + 1);
                    Input(r.BC);
                    return;
                }

                // IN [C] sets only the flags.
                SetFlags((r.F & C) | SignZeroParity[_state.Value]);
                if (_state.Register != MemoryOperand) { Set(_state.Register, _state.Value, halves: false); }
                Finish();
                return;
            case Z80Operation.OutputPort:
                if (Next() == 0)
                {
                    r.WZ = (ushort)(r.BC + 1);
                    Output(r.BC, _state.Register == MemoryOperand ? (byte)0 : Get(_state.Register, halves: false));
                }
                else
                {
                    Finish();
                }

                return;
            case Z80Operation.BlockLoad:
                BlockLoad();
                return;
            case Z80Operation.BlockCompare:
                BlockCompare();
                return;
            case Z80Operation.BlockInput:
            case Z80Operation.BlockOutput:
                BlockTransfer();
                return;
            case Z80Operation.RotateDigit:
                RotateDigit();
                return;
            case Z80Operation.NonMaskable:
                switch (Next())
                {
                    case 0:
                        Write(--r.SP, (byte)(r.PC >> 8));
                        return;
                    case 1:
                        Write(--r.SP, (byte)r.PC);
                        return;
                    default:
                        r.PC = 0x0066;
                        r.WZ = r.PC;
                        Finish();
                        return;
                }

            default:
                Interrupt();
                return;
        }
    }

    // Returns the current step and advances to the next.
    private byte Next() => _state.Step++;

    // Steps 0 and 1 find a memory operand: [HL] at once, or [IX+d] after reading d and 5 internal T-states.
    private bool Locate()
    {
        switch (_state.Step)
        {
            case 0:
                if (_state.Index == 0)
                {
                    _state.Effective = _state.Registers.HL;
                    _state.Step = Located;
                    return true;
                }

                _state.Step = 1;
                ReadOperand();
                return false;
            case 1:
                _state.Effective = (ushort)(Index + (sbyte)_state.Value);
                _state.Registers.WZ = _state.Effective;
                _state.Step = Located;
                Internal(5);
                return false;
            default:
                return true;
        }
    }

    private void Branch()
    {
        ref Z80Registers r = ref _state.Registers;
        r.PC = (ushort)(r.PC + (sbyte)_state.Value);
        r.WZ = r.PC;
        Internal(5);
    }

    private void StoreImmediate()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                ReadOperand();
                return;
            case 1:
                if (_state.Index == 0)
                {
                    _state.Step = 4;
                    Write(r.HL, _state.Value);
                    return;
                }

                // LD [IX+d],n reads d, then n, then waits 2 T-states.
                _state.Effective = (ushort)(Index + (sbyte)_state.Value);
                r.WZ = _state.Effective;
                ReadOperand();
                return;
            case 2:
                _state.Word = _state.Value;
                Internal(2);
                return;
            case 3:
                Write(_state.Effective, (byte)_state.Word);
                return;
            default:
                Finish();
                return;
        }
    }

    // LD A,[BC] / LD A,[DE] and the stores: WZ is the address plus one, with A as its high byte for a store.
    private void Indirect()
    {
        ref Z80Registers r = ref _state.Registers;
        ushort address = _state.Register == 0 ? r.BC : r.DE;
        if (Next() != 0)
        {
            if (_state.Operation == Z80Operation.LoadIndirect) { r.A = _state.Value; }
            Finish();
            return;
        }

        if (_state.Operation == Z80Operation.LoadIndirect)
        {
            r.WZ = (ushort)(address + 1);
            Read(address);
        }
        else
        {
            r.WZ = (ushort)((r.A << 8) | ((address + 1) & 0xFF));
            Write(address, r.A);
        }
    }

    private void Absolute()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                ReadOperand();
                return;
            case 1:
                _state.Word = _state.Value;
                ReadOperand();
                return;
            case 2:
                _state.Word |= (ushort)(_state.Value << 8);
                if (_state.Operation == Z80Operation.LoadAbsolute)
                {
                    r.WZ = (ushort)(_state.Word + 1);
                    Read(_state.Word);
                }
                else
                {
                    r.WZ = (ushort)((r.A << 8) | ((_state.Word + 1) & 0xFF));
                    Write(_state.Word, r.A);
                }

                return;
            default:
                if (_state.Operation == Z80Operation.LoadAbsolute) { r.A = _state.Value; }
                Finish();
                return;
        }
    }

    private void PairAbsolute()
    {
        ref Z80Registers r = ref _state.Registers;
        bool load = _state.Operation == Z80Operation.LoadPairAbsolute;
        switch (Next())
        {
            case 0:
                ReadOperand();
                return;
            case 1:
                _state.Word = _state.Value;
                ReadOperand();
                return;
            case 2:
                _state.Word |= (ushort)(_state.Value << 8);
                r.WZ = (ushort)(_state.Word + 1);
                if (load) { Read(_state.Word); }
                else { Write(_state.Word, (byte)GetPair(_state.Register, accumulator: false)); }
                return;
            case 3:
                _state.Effective = _state.Value;
                if (load) { Read(r.WZ); }
                else { Write(r.WZ, (byte)(GetPair(_state.Register, accumulator: false) >> 8)); }
                return;
            default:
                if (load)
                {
                    SetPair(_state.Register, (ushort)(_state.Effective | (_state.Value << 8)), accumulator: false);
                }

                Finish();
                return;
        }
    }

    private void ExchangeStack()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                Read(r.SP);
                return;
            case 1:
                _state.Word = _state.Value;
                Read((ushort)(r.SP + 1));
                return;
            case 2:
                _state.Word |= (ushort)(_state.Value << 8);
                Internal(1);
                return;
            case 3:
                Write((ushort)(r.SP + 1), (byte)(Index >> 8));
                return;
            case 4:
                Write(r.SP, (byte)Index);
                return;
            case 5:
                Index = _state.Word;
                r.WZ = _state.Word;
                Internal(2);
                return;
            default:
                Finish();
                return;
        }
    }

    // A CB operation on [HL]: BIT takes X and Y from WZ's high byte.
    private void BitsMemory()
    {
        ref Z80Registers r = ref _state.Registers;
        int x = _state.Opcode >> 6;
        int y = (_state.Opcode >> 3) & 7;
        switch (Next())
        {
            case 0:
                Read(r.HL);
                return;
            case 1:
                Internal(1);
                return;
            case 2:
                if (x == 1)
                {
                    TestBit(y, _state.Value, r.WZ >> 8);
                    Finish();
                    return;
                }

                Write(r.HL, BitResult(x, y, _state.Value));
                return;
            default:
                Finish();
                return;
        }
    }

    // DD CB d op: d and the opcode are plain reads; a register copy gets the result too.
    private void IndexBits()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                ReadOperand();
                return;
            case 1:
                _state.Effective = (ushort)(Index + (sbyte)_state.Value);
                r.WZ = _state.Effective;
                ReadOperand();
                return;
            case 2:
                _state.Opcode = _state.Value;
                Internal(2);
                return;
            case 3:
                Read(_state.Effective);
                return;
            case 4:
                Internal(1);
                return;
            case 5:
                int x = _state.Opcode >> 6;
                int y = (_state.Opcode >> 3) & 7;
                int z = _state.Opcode & 7;
                if (x == 1)
                {
                    TestBit(y, _state.Value, _state.Effective >> 8);
                    Finish();
                    return;
                }

                byte result = BitResult(x, y, _state.Value);
                if (z != MemoryOperand) { Set(z, result, halves: false); }
                Write(_state.Effective, result);
                return;
            default:
                Finish();
                return;
        }
    }

    private byte BitResult(int x, int y, byte value) => x switch
    {
        0 => Shift(y, value),
        2 => (byte)(value & ~(1 << y)),
        _ => (byte)(value | (1 << y))
    };

    private void Call()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                ReadOperand();
                return;
            case 1:
                _state.Word = _state.Value;
                ReadOperand();
                return;
            case 2:
                _state.Word |= (ushort)(_state.Value << 8);
                r.WZ = _state.Word;
                if (_state.Variant == Always || Condition(_state.Variant)) { Internal(1); }
                else { Finish(); }
                return;
            case 3:
                Write(--r.SP, (byte)(r.PC >> 8));
                return;
            case 4:
                Write(--r.SP, (byte)r.PC);
                return;
            default:
                r.PC = _state.Word;
                Finish();
                return;
        }
    }

    // RET reads at once; RET cc spends a T-state on the condition first.
    private void Return()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                if (_state.Variant == Always)
                {
                    _state.Step = 2;
                    Read(r.SP++);
                }
                else
                {
                    Internal(1);
                }

                return;
            case 1:
                if (Condition(_state.Variant)) { Read(r.SP++); }
                else { Finish(); }
                return;
            case 2:
                _state.Word = _state.Value;
                Read(r.SP++);
                return;
            default:
                r.PC = (ushort)(_state.Word | (_state.Value << 8));
                r.WZ = r.PC;
                Finish();
                return;
        }
    }

    // Variant bit 0: decrement; bit 1: repeat.
    private void BlockLoad()
    {
        ref Z80Registers r = ref _state.Registers;
        int delta = (_state.Variant & 1) == 0 ? 1 : -1;
        switch (Next())
        {
            case 0:
                Read(r.HL);
                return;
            case 1:
                Write(r.DE, _state.Value);
                return;
            case 2:
                int sum = r.A + _state.Value;
                r.HL = (ushort)(r.HL + delta);
                r.DE = (ushort)(r.DE + delta);
                r.BC--;
                SetFlags((r.F & (S | Z | C)) | (r.BC != 0 ? PV : 0) | (sum & X) | ((sum << 4) & Y));
                Internal(2);
                return;
            case 3:
                if ((_state.Variant & 2) != 0 && r.BC != 0) { Repeat(); }
                else { Finish(); }
                return;
            default:
                Finish();
                return;
        }
    }

    private void BlockCompare()
    {
        ref Z80Registers r = ref _state.Registers;
        int delta = (_state.Variant & 1) == 0 ? 1 : -1;
        switch (Next())
        {
            case 0:
                Read(r.HL);
                return;
            case 1:
                int value = _state.Value;
                int result = r.A - value;
                r.HL = (ushort)(r.HL + delta);
                r.WZ = (ushort)(r.WZ + delta);
                r.BC--;
                int half = (r.A ^ value ^ result) & H;
                int adjusted = result - (half != 0 ? 1 : 0);
                int xy = (adjusted & X) | ((adjusted << 4) & Y);
                SetFlags((r.F & C) | N | (SignZero[result & 0xFF] & ~XY) | half | xy | (r.BC != 0 ? PV : 0));

                Internal(5);
                return;
            case 2:
                if ((_state.Variant & 2) != 0 && r.BC != 0 && (r.F & Z) == 0) { Repeat(); }
                else { Finish(); }
                return;
            default:
                Finish();
                return;
        }
    }

    // INI/IND and OUTI/OUTD: B counts down; the flags come from B, the byte and C or L.
    private void BlockTransfer()
    {
        ref Z80Registers r = ref _state.Registers;
        bool input = _state.Operation == Z80Operation.BlockInput;
        int delta = (_state.Variant & 1) == 0 ? 1 : -1;
        switch (Next())
        {
            case 0:
                Internal(1);
                return;
            case 1:
                if (input)
                {
                    r.WZ = (ushort)(r.BC + delta);
                    Input(r.BC);
                }
                else
                {
                    Read(r.HL);
                }

                return;
            case 2:
                r.B--;
                if (input)
                {
                    Write(r.HL, _state.Value);
                }
                else
                {
                    r.WZ = (ushort)(r.BC + delta);
                    Output(r.BC, _state.Value);
                }

                return;
            case 3:
                int value = _state.Value;
                r.HL = (ushort)(r.HL + delta);
                int sum = value + (input ? (byte)(r.C + delta) : r.L);
                int parity = SignZeroParity[(sum & 7) ^ r.B] & PV;
                int flags = SignZero[r.B] | ((value & 0x80) != 0 ? N : 0) | (sum > 0xFF ? H | C : 0) | parity;

                SetFlags(flags);
                if ((_state.Variant & 2) != 0 && r.B != 0)
                {
                    RepeatTransfer(value);
                }
                else
                {
                    Finish();
                }

                return;
            default:
                Finish();
                return;
        }
    }

    // A repeating block instruction runs again: PC steps back, and X and Y show PC's high byte.
    private void Repeat()
    {
        ref Z80Registers r = ref _state.Registers;
        r.PC -= 2;
        r.WZ = (ushort)(r.PC + 1);
        SetFlags((r.F & ~XY) | ((r.PC >> 8) & XY));
        Internal(5);
    }

    // INIR, INDR, OTIR and OTDR also change H and PV when they repeat, from B and the byte moved.
    private void RepeatTransfer(int value)
    {
        ref Z80Registers r = ref _state.Registers;
        r.PC -= 2;
        r.WZ = (ushort)(r.PC + 1);
        int f = (r.F & ~XY) | ((r.PC >> 8) & XY);
        if ((f & C) != 0)
        {
            f &= ~H;
            if ((value & 0x80) != 0)
            {
                f ^= (SignZeroParity[(r.B - 1) & 7] ^ PV) & PV;
                if ((r.B & 0x0F) == 0x00) { f |= H; }
            }
            else
            {
                f ^= (SignZeroParity[(r.B + 1) & 7] ^ PV) & PV;
                if ((r.B & 0x0F) == 0x0F) { f |= H; }
            }
        }
        else
        {
            f ^= (SignZeroParity[r.B & 7] ^ PV) & PV;
        }

        SetFlags(f);
        Internal(5);
    }

    // Variant 0: RRD; 1: RLD.
    private void RotateDigit()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                r.WZ = (ushort)(r.HL + 1);
                Read(r.HL);
                return;
            case 1:
                Internal(4);
                return;
            case 2:
                int value = _state.Value;
                byte memory;
                if (_state.Variant == 0)
                {
                    memory = (byte)((value >> 4) | (r.A << 4));
                    r.A = (byte)((r.A & 0xF0) | (value & 0x0F));
                }
                else
                {
                    memory = (byte)((value << 4) | (r.A & 0x0F));
                    r.A = (byte)((r.A & 0xF0) | (value >> 4));
                }

                SetFlags((r.F & C) | SignZeroParity[r.A]);
                Write(r.HL, memory);
                return;
            default:
                Finish();
                return;
        }
    }

    // Mode 1 restarts at $38; mode 2 jumps through the vector at I and the byte the device supplied.
    private void Interrupt()
    {
        ref Z80Registers r = ref _state.Registers;
        switch (Next())
        {
            case 0:
                _state.Effective = _state.Value;
                Internal(1);
                return;
            case 1:
                Write(--r.SP, (byte)(r.PC >> 8));
                return;
            case 2:
                Write(--r.SP, (byte)r.PC);
                return;
            case 3:
                if (r.InterruptMode == 1)
                {
                    r.PC = 0x0038;
                    r.WZ = r.PC;
                    Finish();
                    return;
                }

                _state.Word = (ushort)((r.I << 8) | _state.Effective);
                Read(_state.Word);
                return;
            case 4:
                _state.Effective = _state.Value;
                Read((ushort)(_state.Word + 1));
                return;
            default:
                r.PC = (ushort)(_state.Effective | (_state.Value << 8));
                r.WZ = r.PC;
                Finish();
                return;
        }
    }
}
