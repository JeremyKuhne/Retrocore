// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.Z80.Z80Flags;

namespace Retrocore.Cpu.Z80;

public sealed partial class Z80Processor<TBus>
{
    private const int MemoryOperand = 6;

    // Starts an operation at its first step, which runs at once to choose its first machine cycle.
    private void Start(Z80Operation operation, int register = 0, int variant = 0)
    {
        _state.Operation = operation;
        _state.Step = 0;
        _state.Register = (byte)register;
        _state.Variant = (byte)variant;
        Execute();
    }

    // An opcode was fetched, unprefixed or after DD or FD. Its group, from the opcode table, picks the work in
    // one jump: y = bits 3-5, z = bits 0-2, p = y / 2, q = y % 2.
    private void Decode(byte opcode)
    {
        ref Z80Registers r = ref _state.Registers;
        _state.Opcode = opcode;
        r.AfterEnable = false;
        r.AfterLoadInterrupt = false;
        int y = (opcode >> 3) & 7;
        int z = opcode & 7;
        int p = y >> 1;
        int q = y & 1;
        switch ((Z80OpcodeGroup)Z80Decoding.Groups[opcode])
        {
            case Z80OpcodeGroup.Bits:
                if (_state.Index != 0)
                {
                    Start(Z80Operation.IndexBits);
                }
                else
                {
                    _state.Operation = Z80Operation.DecodeBits;
                    Fetch();
                }

                return;
            case Z80OpcodeGroup.Extended:
                _state.Index = 0;
                _state.Operation = Z80Operation.DecodeExtended;
                Fetch();
                return;
            case Z80OpcodeGroup.IndexPrefix:
                // A prefix chain keeps only the last; no interrupt is taken within it. Each prefix is an
                // instruction of its own to Q, writing no flags.
                _state.Index = (byte)(opcode == 0xDD ? 1 : 2);
                r.Q = 0;
                _state.FlagsWritten = false;
                _state.Operation = Z80Operation.Decode;
                Fetch();
                return;
            case Z80OpcodeGroup.Nop:
                Finish();
                return;
            case Z80OpcodeGroup.ExchangeAF:
                (r.AF, r.AlternateAF) = (r.AlternateAF, r.AF);
                Finish();
                return;
            case Z80OpcodeGroup.DecrementJump:
                Start(Z80Operation.DecrementJump);
                return;
            case Z80OpcodeGroup.JumpRelative:
                // JR e is condition -1; JR cc,e uses NZ Z NC C.
                Start(Z80Operation.JumpRelative, 0, y == 3 ? 8 : y - 4);
                return;
            case Z80OpcodeGroup.LoadPairImmediate:
                Start(Z80Operation.LoadPairImmediate, p);
                return;
            case Z80OpcodeGroup.AddPair:
                _state.Register = (byte)p;
                AddPair(GetPair(p, accumulator: false));
                StartDelay(7);
                return;
            case Z80OpcodeGroup.StoreIndirect:
                Start(Z80Operation.StoreIndirect, p);
                return;
            case Z80OpcodeGroup.StorePairAbsolute:
                Start(Z80Operation.StorePairAbsolute, 2);
                return;
            case Z80OpcodeGroup.StoreAbsolute:
                Start(Z80Operation.StoreAbsolute);
                return;
            case Z80OpcodeGroup.LoadIndirect:
                Start(Z80Operation.LoadIndirect, p);
                return;
            case Z80OpcodeGroup.LoadPairAbsolute:
                Start(Z80Operation.LoadPairAbsolute, 2);
                return;
            case Z80OpcodeGroup.LoadAbsolute:
                Start(Z80Operation.LoadAbsolute);
                return;
            case Z80OpcodeGroup.StepPair:
                SetPair(p, (ushort)(GetPair(p, accumulator: false) + (q == 0 ? 1 : -1)), accumulator: false);
                StartDelay(2);
                return;
            case Z80OpcodeGroup.StepMemory:
                Start(Z80Operation.StepMemory, 0, z - 4);
                return;
            case Z80OpcodeGroup.StepRegister:
                byte value = Get(y, halves: true);
                Set(y, z == 4 ? Increment(value) : Decrement(value), halves: true);
                Finish();
                return;
            case Z80OpcodeGroup.StoreImmediate:
                Start(Z80Operation.StoreImmediate, y);
                return;
            case Z80OpcodeGroup.LoadImmediate:
                Start(Z80Operation.LoadImmediate, y);
                return;
            case Z80OpcodeGroup.Accumulator:
                Accumulator(y);
                Finish();
                return;
            case Z80OpcodeGroup.Halt:
                _state.Halted = true;
                _state.Status = ProcessorExecutionStatus.Waiting;
                Finish();
                return;
            case Z80OpcodeGroup.LoadMemory:
                Start(Z80Operation.LoadMemory, y);
                return;
            case Z80OpcodeGroup.StoreMemory:
                Start(Z80Operation.StoreMemory, z);
                return;
            case Z80OpcodeGroup.LoadRegister:
                Set(y, Get(z, halves: true), halves: true);
                Finish();
                return;
            case Z80OpcodeGroup.ArithmeticMemory:
                Start(Z80Operation.ArithmeticMemory, 0, y);
                return;
            case Z80OpcodeGroup.ArithmeticRegister:
                Arithmetic(y, Get(z, halves: true));
                Finish();
                return;
            case Z80OpcodeGroup.ReturnConditional:
                Start(Z80Operation.Return, 0, y);
                return;
            case Z80OpcodeGroup.Pop:
                Start(Z80Operation.Pop, p);
                return;
            case Z80OpcodeGroup.Return:
                Start(Z80Operation.Return, 0, 8);
                return;
            case Z80OpcodeGroup.ExchangeAll:
                (r.BC, r.AlternateBC) = (r.AlternateBC, r.BC);
                (r.DE, r.AlternateDE) = (r.AlternateDE, r.DE);
                (r.HL, r.AlternateHL) = (r.AlternateHL, r.HL);
                Finish();
                return;
            case Z80OpcodeGroup.JumpIndex:
                r.PC = Index;
                Finish();
                return;
            case Z80OpcodeGroup.LoadStackIndex:
                r.SP = Index;
                StartDelay(2);
                return;
            case Z80OpcodeGroup.JumpConditional:
                Start(Z80Operation.Jump, 0, y);
                return;
            case Z80OpcodeGroup.Jump:
                Start(Z80Operation.Jump, 0, 8);
                return;
            case Z80OpcodeGroup.OutputImmediate:
                Start(Z80Operation.OutputImmediate);
                return;
            case Z80OpcodeGroup.InputImmediate:
                Start(Z80Operation.InputImmediate);
                return;
            case Z80OpcodeGroup.ExchangeStack:
                Start(Z80Operation.ExchangeStack);
                return;
            case Z80OpcodeGroup.ExchangeDEHL:
                // EX DE,HL ignores a prefix.
                (r.DE, r.HL) = (r.HL, r.DE);
                Finish();
                return;
            case Z80OpcodeGroup.DisableInterrupts:
                r.Iff1 = false;
                r.Iff2 = false;
                Finish();
                return;
            case Z80OpcodeGroup.EnableInterrupts:
                r.Iff1 = true;
                r.Iff2 = true;
                r.AfterEnable = true;
                Finish();
                return;
            case Z80OpcodeGroup.CallConditional:
                Start(Z80Operation.Call, 0, y);
                return;
            case Z80OpcodeGroup.Push:
                Start(Z80Operation.Push, p);
                return;
            case Z80OpcodeGroup.Call:
                Start(Z80Operation.Call, 0, 8);
                return;
            case Z80OpcodeGroup.ArithmeticImmediate:
                Start(Z80Operation.ArithmeticImmediate, 0, y);
                return;
            default:
                _state.Word = (ushort)(y << 3);
                Start(Z80Operation.Restart);
                return;
        }
    }

    // A CB opcode was fetched: shifts, BIT, RES and SET on a register or [HL].
    private void DecodeBits(byte opcode)
    {
        _state.Opcode = opcode;
        int x = opcode >> 6;
        int y = (opcode >> 3) & 7;
        int z = opcode & 7;
        if (z == MemoryOperand)
        {
            Start(Z80Operation.BitsMemory);
            return;
        }

        byte value = Get(z, halves: false);
        switch (x)
        {
            case 0:
                Set(z, Shift(y, value), halves: false);
                break;
            case 1:
                TestBit(y, value, value);
                break;
            case 2:
                Set(z, (byte)(value & ~(1 << y)), halves: false);
                break;
            default:
                Set(z, (byte)(value | (1 << y)), halves: false);
                break;
        }

        Finish();
    }

    // An ED opcode was fetched; undefined ones act as two-byte NOPs.
    private void DecodeExtended(byte opcode)
    {
        ref Z80Registers r = ref _state.Registers;
        _state.Opcode = opcode;
        int x = opcode >> 6;
        int y = (opcode >> 3) & 7;
        int z = opcode & 7;
        int p = y >> 1;
        int q = y & 1;
        if (x == 2 && z <= 3 && y >= 4)
        {
            Z80Operation block = z switch
            {
                0 => Z80Operation.BlockLoad,
                1 => Z80Operation.BlockCompare,
                2 => Z80Operation.BlockInput,
                _ => Z80Operation.BlockOutput
            };

            // Variant bit 0: decrement; bit 1: repeat.
            Start(block, 0, y - 4);
            return;
        }

        if (x != 1)
        {
            Finish();
            return;
        }

        switch (z)
        {
            case 0:
                Start(Z80Operation.InputPort, y);
                return;
            case 1:
                Start(Z80Operation.OutputPort, y);
                return;
            case 2:
                CarryPair(GetPair(p, accumulator: false), subtract: q == 0);
                StartDelay(7);
                return;
            case 3:
                Start(q == 0 ? Z80Operation.StorePairAbsolute : Z80Operation.LoadPairAbsolute, p);
                return;
            case 4:
                byte a = r.A;
                r.A = 0;
                Arithmetic(2, a);
                Finish();
                return;
            case 5:
                // RETN and RETI both restore IFF1 from IFF2.
                r.Iff1 = r.Iff2;
                Start(Z80Operation.Return, 0, 8);
                return;
            case 6:
                r.InterruptMode = (byte)((y & 3) switch
                {
                    2 => 1,
                    3 => 2,
                    _ => 0
                });

                Finish();
                return;
            default:
                switch (y)
                {
                    case 0:
                        r.I = r.A;
                        StartDelay(1);
                        return;
                    case 1:
                        r.R = r.A;
                        StartDelay(1);
                        return;
                    case 2:
                    case 3:
                        r.A = y == 2 ? r.I : r.R;
                        SetFlags((r.F & C) | SignZero[r.A] | (r.Iff2 ? PV : 0));
                        r.AfterLoadInterrupt = true;
                        StartDelay(1);
                        return;
                    case 4:
                    case 5:
                        Start(Z80Operation.RotateDigit, 0, y - 4);
                        return;
                    default:
                        Finish();
                        return;
                }
        }
    }

    private void StartDelay(byte length)
    {
        _state.Operation = Z80Operation.Delay;
        _state.Step = 0;
        Internal(length);
    }
}
