// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

public sealed partial class I8080Processor<TBus>
{
    // Runs the current step of the instruction family; each step ends by scheduling a cycle or finishing.
    private void Execute()
    {
        ref I8080Registers r = ref _state.Registers;
        switch (_state.Operation)
        {
            case I8080Operation.Delay:
                Finish();
                return;
            case I8080Operation.Halt:
                _state.Halted = true;
                _state.Status = ProcessorExecutionStatus.Waiting;
                Finish();
                return;
            case I8080Operation.LoadImmediate:
                if (Next() == 0) { ReadOperand(); }
                else
                {
                    Set(_state.Register, _state.Value);
                    Finish();
                }

                return;
            case I8080Operation.StoreImmediate:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        Write(r.HL, _state.Value);
                        return;
                    default:
                        Finish();
                        return;
                }

            case I8080Operation.LoadMemory:
                if (Next() == 0) { Read(_state.Word); }
                else
                {
                    Set(_state.Register, _state.Value);
                    Finish();
                }

                return;
            case I8080Operation.StoreMemory:
                if (Next() == 0) { Write(_state.Word, Get(_state.Register)); }
                else { Finish(); }
                return;
            case I8080Operation.StepMemory:
                switch (Next())
                {
                    case 0:
                        Read(r.HL);
                        return;
                    case 1:
                        Write(r.HL, _state.Selector == 0 ? Increment(_state.Value) : Decrement(_state.Value));
                        return;
                    default:
                        Finish();
                        return;
                }

            case I8080Operation.ArithmeticMemory:
                if (Next() == 0) { Read(r.HL); }
                else
                {
                    Arithmetic(_state.Selector, _state.Value);
                    Finish();
                }

                return;
            case I8080Operation.ArithmeticImmediate:
                if (Next() == 0) { ReadOperand(); }
                else
                {
                    Arithmetic(_state.Selector, _state.Value);
                    Finish();
                }

                return;
            case I8080Operation.LoadPairImmediate:
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
                        SetPair(_state.Register, OperandWord(), psw: false);
                        Finish();
                        return;
                }

            case I8080Operation.LoadAbsolute:
            case I8080Operation.StoreAbsolute:
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
                        _state.Word = OperandWord();
                        if (_state.Operation == I8080Operation.LoadAbsolute) { Read(_state.Word); }
                        else { Write(_state.Word, r.A); }
                        return;
                    default:
                        if (_state.Operation == I8080Operation.LoadAbsolute) { r.A = _state.Value; }
                        Finish();
                        return;
                }

            case I8080Operation.LoadPair:
                // LHLD reads its address first; LHLX starts at step 2 with DE.
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
                        if (WordFromOperands()) { _state.Word = OperandWord(); }
                        Read(_state.Word);
                        return;
                    case 3:
                        r.L = _state.Value;
                        Read((ushort)(_state.Word + 1));
                        return;
                    default:
                        r.H = _state.Value;
                        Finish();
                        return;
                }

            case I8080Operation.StorePair:
                // SHLD writes to its operand address; SHLX starts at step 2 with DE.
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
                        if (WordFromOperands()) { _state.Word = OperandWord(); }
                        Write(_state.Word, r.L);
                        return;
                    case 3:
                        Write((ushort)(_state.Word + 1), r.H);
                        return;
                    default:
                        Finish();
                        return;
                }

            case I8080Operation.Jump:
                // The 8085 skips the high byte of a jump not taken.
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        _state.Word = _state.Value;
                        if (Is8085 && !Condition(_state.Selector))
                        {
                            r.PC++;
                            Finish();
                            return;
                        }

                        ReadOperand();
                        return;
                    default:
                        if (Condition(_state.Selector)) { r.PC = OperandWord(); }
                        Finish();
                        return;
                }

            case I8080Operation.Call:
                // The 8085 skips the high byte of a call not taken.
                switch (Next())
                {
                    case 0:
                        Internal(LongFetch);
                        return;
                    case 1:
                        ReadOperand();
                        return;
                    case 2:
                        _state.Word = _state.Value;
                        if (Is8085 && !Condition(_state.Selector))
                        {
                            r.PC++;
                            Finish();
                            return;
                        }

                        ReadOperand();
                        return;
                    case 3:
                        _state.Word = OperandWord();
                        if (!Condition(_state.Selector))
                        {
                            Finish();
                            return;
                        }

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

            case I8080Operation.Return:
                // A conditional return has the long M1; RET starts at step 1.
                switch (Next())
                {
                    case 0:
                        Internal(LongFetch);
                        return;
                    case 1:
                        if (!Condition(_state.Selector))
                        {
                            Finish();
                            return;
                        }

                        Read(r.SP++);
                        return;
                    case 2:
                        _state.Word = _state.Value;
                        Read(r.SP++);
                        return;
                    default:
                        r.PC = OperandWord();
                        Finish();
                        return;
                }

            case I8080Operation.Restart:
                switch (Next())
                {
                    case 0:
                        Internal(LongFetch);
                        return;
                    case 1:
                        if (!Condition(_state.Selector))
                        {
                            Finish();
                            return;
                        }

                        Write(--r.SP, (byte)(r.PC >> 8));
                        return;
                    case 2:
                        Write(--r.SP, (byte)r.PC);
                        return;
                    default:
                        r.PC = _state.Word;
                        Finish();
                        return;
                }

            case I8080Operation.Push:
                switch (Next())
                {
                    case 0:
                        Internal(LongFetch);
                        return;
                    case 1:
                        Write(--r.SP, (byte)(GetPair(_state.Register, psw: true) >> 8));
                        return;
                    case 2:
                        Write(--r.SP, (byte)GetPair(_state.Register, psw: true));
                        return;
                    default:
                        Finish();
                        return;
                }

            case I8080Operation.Pop:
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
                        SetPair(_state.Register, OperandWord(), psw: true);
                        Finish();
                        return;
                }

            case I8080Operation.ExchangeStack:
                // XTHL: 18 states on the 8080, whose last write cycle is 5 states long, and 16 on the 8085.
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
                        _state.Word = OperandWord();
                        Write((ushort)(r.SP + 1), r.H);
                        return;
                    case 3:
                        Write(r.SP, r.L);
                        return;
                    case 4:
                        r.HL = _state.Word;
                        if (Is8085) { Finish(); }
                        else { Internal(2); }
                        return;
                    default:
                        Finish();
                        return;
                }

            case I8080Operation.Input:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        Input((ushort)((_state.Value << 8) | _state.Value));
                        return;
                    default:
                        r.A = _state.Value;
                        Finish();
                        return;
                }

            case I8080Operation.Output:
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        Output((ushort)((_state.Value << 8) | _state.Value), r.A);
                        return;
                    default:
                        Finish();
                        return;
                }

            default:
                // LDHI and LDSI (8085): DE = HL or SP plus an unsigned byte, then a bus-idle cycle.
                switch (Next())
                {
                    case 0:
                        ReadOperand();
                        return;
                    case 1:
                        r.DE = (ushort)((_state.Register == 0 ? r.HL : r.SP) + _state.Value);
                        Internal(3);
                        return;
                    default:
                        Finish();
                        return;
                }
        }
    }

    // Returns the current step and advances to the next.
    private byte Next() => _state.Step++;

    // The word whose low byte an earlier step kept and whose high byte the last read returned.
    private ushort OperandWord() => (ushort)(_state.Word | (_state.Value << 8));

    // LHLD and SHLD read their address; LHLX and SHLX, by their opcodes, use DE.
    private bool WordFromOperands() => _state.Opcode is 0x22 or 0x2A;

    // Schedules the next machine cycle of the instruction.
    private void Read(ushort address)
    {
        _state.Cycle = I8080MachineCycle.Read;
        _state.Address = address;
    }

    private void Write(ushort address, byte value)
    {
        _state.Cycle = I8080MachineCycle.Write;
        _state.Address = address;
        _state.Value = value;
    }

    private void Input(ushort port)
    {
        _state.Cycle = I8080MachineCycle.InputRead;
        _state.Address = port;
    }

    private void Output(ushort port, byte value)
    {
        _state.Cycle = I8080MachineCycle.OutputWrite;
        _state.Address = port;
        _state.Value = value;
    }

    private void Internal(byte length)
    {
        _state.Cycle = I8080MachineCycle.Internal;
        _state.Length = length;
        _state.T = 0;
    }

    // Reads the byte at PC and advances PC, as operand reads do.
    private void ReadOperand() => Read(_state.Registers.PC++);

    private void Finish()
    {
        _state.Operation = I8080Operation.None;
        _state.Step = 0;
    }
}
