// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Cpu.M6502;

/// <summary>
///  A caller-clocked processor with a caller-owned bus. Each cycle performs at most one bus access.
///  Supports NMOS 6502, WDC W65C02S, and Rockwell R65C02 instruction encodings.
/// </summary>
/// <typeparam name="TBus">The memory and device bus implementation.</typeparam>
public sealed partial class Processor<TBus> where TBus : IProcessorBus
{
    // The bus, when it is a class that wants to know its opcode fetches. A field, not a static: class buses share one
    // copy of this generic code, where a static would be looked up on every fetch.
    private readonly IOpcodeFetchBus? _opcodeFetchBus;

    // The variant's opcode table, resolved once rather than on every fetch.
    private readonly OpCode[] _opcodes;
    private TBus _bus;
    private ProcessorExecutionState _state;

    /// <summary>
    ///  Constructs a processor at an instruction boundary. Call <see cref="Reset"/> to read the reset vector.
    /// </summary>
    /// <param name="bus">The caller-owned bus. A struct bus is stored by value.</param>
    /// <param name="variant">The processor variant.</param>
    public Processor(TBus bus, ProcessorVariant variant = ProcessorVariant.Mos6502)
    {
        ArgumentNullException.ThrowIfNull(bus);
        if (variant is < ProcessorVariant.Mos6502 or > ProcessorVariant.Rockwell65C02)
        {
            throw new ArgumentOutOfRangeException(nameof(variant));
        }

        _bus = bus;
        _opcodeFetchBus = typeof(TBus).IsValueType ? null : bus as IOpcodeFetchBus;
        Variant = variant;
        _opcodes = OpcodeTable.Get(variant).ToArray();
        _state.Registers.StackPointer = 0xFD;
        _state.Registers.Status = StatusRegister.Unused | StatusRegister.IRQBDisable;
    }

    /// <summary>
    ///  Gets the emulated CPU variant.
    /// </summary>
    public ProcessorVariant Variant { get; }

    /// <summary>
    ///  Gets a reference to the live bus, including mutable struct-bus state.
    ///  The caller must synchronize access and restore bus state separately from CPU snapshots.
    /// </summary>
    public ref TBus Bus => ref _bus;

    /// <summary>
    ///  Gets this variant's instruction metadata without accessing the bus.
    /// </summary>
    /// <param name="encoding">The opcode byte.</param>
    /// <returns>The decoded instruction and addressing mode.</returns>
    public OpCode GetOpCode(byte encoding) => _opcodes[encoding];

    /// <summary>
    ///  Gets or sets architectural registers at an instruction boundary.
    ///  Restore a snapshot instead when resuming in the middle of a sequence.
    /// </summary>
    /// <exception cref="InvalidOperationException">Execution is not at a running instruction boundary.</exception>
    public ProcessorRegisters Registers
    {
        get => _state.Registers;
        set
        {
            if (!IsInstructionBoundary || _state.Status != ProcessorExecutionStatus.Running)
            {
                throw new InvalidOperationException("Registers can only be replaced at a running instruction boundary.");
            }

            value.Status |= StatusRegister.Unused;
            _state.Registers = value;
            _state.IrqPolled = false;
        }
    }

    /// <summary>
    ///  Gets or sets logical CPU input assertions, sampled on the next cycle.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">An undefined input flag is set.</exception>
    public ProcessorSignals Signals
    {
        get => _state.Signals;
        set
        {
            const ProcessorSignals valid = ProcessorSignals.Reset
                | ProcessorSignals.InterruptRequest
                | ProcessorSignals.NonMaskableInterrupt
                | ProcessorSignals.ReadStall
                | ProcessorSignals.SetOverflow;

            if ((value & ~valid) != 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            _state.Signals = value;
        }
    }

    /// <summary>
    ///  Gets whether no instruction, reset, or hardware interrupt is in flight.
    ///  A halted processor can also be at this boundary.
    /// </summary>
    public bool IsInstructionBoundary => _state.Phase == 0 && _state.Sequence == ProcessorSequence.Instruction;

    /// <summary>
    ///  Gets the number of elapsed CPU cycles.
    /// </summary>
    public ulong CycleCount => _state.CycleCount;

    /// <summary>
    ///  Gets the current execution or halt status.
    /// </summary>
    public ProcessorExecutionStatus Status => _state.Status;

    /// <summary>
    ///  Gets the active instruction metadata, or null outside an instruction's microsequence.
    /// </summary>
    public OpCode? CurrentOpCode =>
        _state.Phase != 0 && _state.Sequence == ProcessorSequence.Instruction ? _state.Instruction : null;

    /// <summary>
    ///  Starts a seven-cycle reset sequence, abandoning any in-flight instruction or halted state.
    ///  No bus access occurs until the caller advances the clock.
    /// </summary>
    public void Reset()
    {
        _state.Sequence = ProcessorSequence.Reset;
        _state.Phase = 1;
        _state.Status = ProcessorExecutionStatus.Running;
        _state.PendingNmi = false;
        _state.IrqPending = false;
        _state.IrqPolled = false;
    }

    /// <summary>
    ///  Captures complete CPU state without accessing the bus.
    /// </summary>
    /// <returns>A snapshot that can be restored into the same CPU variant.</returns>
    public ProcessorSnapshot CaptureState() => new(Variant, _state);

    /// <summary>
    ///  Restores complete CPU state without accessing the bus.
    /// </summary>
    /// <param name="snapshot">A snapshot previously captured from this CPU variant.</param>
    /// <exception cref="ArgumentException">The snapshot is uninitialized or belongs to a different variant.</exception>
    public void RestoreState(ProcessorSnapshot snapshot)
    {
        if (!snapshot.IsInitialized || snapshot.Variant != Variant)
        {
            throw new ArgumentException("A valid snapshot from the same CPU variant is required.", nameof(snapshot));
        }

        _state = snapshot.State;
    }

    /// <summary>
    ///  Gets the bus operation and execution metadata of the last cycle.
    /// </summary>
    public ProcessorCycle LastCycle => _state.LastCycle;

    /// <summary>
    ///  Gets whether the last cycle fetched an opcode, not held by RDY.
    /// </summary>
    public bool FetchedOpcode => _state.LastCycle.IsOpcodeFetch && !_state.LastCycle.IsStalled;

    /// <summary>
    ///  Advances exactly one clock cycle; <see cref="LastCycle"/> then describes it. Dummy and held reads
    ///  still invoke the bus. Idle stopped cycles advance the elapsed counter without accessing the bus.
    /// </summary>
    public void StepCycle()
    {
        if (_state.Signals != _state.PreviousSignals) { SampleSignals(); }
        bool mayStall = (_state.PreviousSignals & ProcessorSignals.ReadStall) != 0;
        ProcessorExecutionState before = mayStall ? _state : default;
        _state.CycleCount++;
        _state.LastCycle = new() { Number = _state.CycleCount };
        Advance();

        if (_state.LastCycle.IsStalled)
        {
            ProcessorCycle cycle = _state.LastCycle;
            ProcessorSignals signals = _state.Signals;
            _state = before;
            _state.Signals = signals;
            _state.CycleCount = cycle.Number;
            _state.LastCycle = cycle;
        }
    }

    /// <summary>
    ///  Finishes the current instruction, or starts and finishes one at a boundary, within a cycle limit.
    ///  Halted or waiting processors return immediately rather than looping indefinitely.
    /// </summary>
    /// <param name="maximumCycles">The maximum number of clock cycles to execute.</param>
    /// <returns>The completion reason and number of cycles executed.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The cycle limit is not positive.</exception>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 16)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = CycleCount;
        bool executingInstruction = _state.Phase != 0 && _state.Sequence == ProcessorSequence.Instruction;

        for (int i = 0; i < maximumCycles; i++)
        {
            if (Status != ProcessorExecutionStatus.Running && !CanResume())
            {
                return new() { Status = Status, Cycles = CycleCount - start };
            }

            StepCycle();
            executingInstruction |= FetchedOpcode;
            if (executingInstruction && IsInstructionBoundary)
            {
                return new()
                {
                    Status = Status == ProcessorExecutionStatus.Running
                        ? ProcessorExecutionStatus.InstructionComplete
                        : Status,
                    Cycles = CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = CycleCount - start };
    }

    /// <summary>
    ///  Advances exactly the requested number of clock cycles, including idle or stalled cycles.
    /// </summary>
    /// <param name="cycleBudget">The number of cycles to execute.</param>
    /// <returns>The terminal halt status, or a cycle-budget-exhausted result.</returns>
    public ProcessorExecutionResult Run(ulong cycleBudget)
    {
        for (ulong i = 0; i < cycleBudget; i++)
        {
            StepCycle();
        }

        return new()
        {
            Status = Status == ProcessorExecutionStatus.Running
                ? ProcessorExecutionStatus.CycleBudgetExhausted
                : Status,
            Cycles = cycleBudget
        };
    }

    private void SampleSignals()
    {
        ProcessorSignals asserted = _state.Signals & ~_state.PreviousSignals;
        _state.PendingNmi |= (asserted & ProcessorSignals.NonMaskableInterrupt) != 0;
        if ((asserted & ProcessorSignals.SetOverflow) != 0)
        {
            _state.Registers.Status |= StatusRegister.Overflow;
        }

        if ((asserted & ProcessorSignals.Reset) != 0)
        {
            Reset();
        }

        _state.PreviousSignals = _state.Signals;
    }

    private bool CanResume()
    {
        ProcessorSignals asserted = _state.Signals & ~_state.PreviousSignals;
        return (asserted & ProcessorSignals.Reset) != 0
            || (_state.Status == ProcessorExecutionStatus.Waiting
                && (_state.PendingNmi
                    || (asserted & ProcessorSignals.NonMaskableInterrupt) != 0
                    || (_state.Signals & ProcessorSignals.InterruptRequest) != 0));
    }

    private void Advance()
    {
        if (_state.Status == ProcessorExecutionStatus.Jammed)
        {
            AdvanceJam();
            return;
        }

        if (_state.Status == ProcessorExecutionStatus.Waiting
            && (_state.PendingNmi || (_state.Signals & ProcessorSignals.InterruptRequest) != 0))
        {
            _state.Status = ProcessorExecutionStatus.Running;
            _state.IrqPending = (_state.Signals & ProcessorSignals.InterruptRequest) != 0
                && (_state.Registers.Status & StatusRegister.IRQBDisable) == 0;

            _state.IrqPolled = true;
        }

        if (_state.Status != ProcessorExecutionStatus.Running)
        {
            return;
        }

        if (_state.Sequence == ProcessorSequence.Reset)
        {
            AdvanceReset();
            return;
        }

        if (_state.Sequence == ProcessorSequence.Interrupt)
        {
            AdvanceInterrupt();
            return;
        }

        if (_state.Phase == 0)
        {
            if (_state.PendingNmi
                || (_state.IrqPolled ? _state.IrqPending
                    : ((_state.Signals & ProcessorSignals.InterruptRequest) != 0
                        && (_state.Registers.Status & StatusRegister.IRQBDisable) == 0)))
            {
                _state.InterruptNmi = _state.PendingNmi;
                _state.PendingNmi = false;
                _state.Sequence = ProcessorSequence.Interrupt;
                _state.Phase = 1;
                AdvanceInterrupt();
                return;
            }

            ushort address = _state.Registers.ProgramCounter;
            byte opcode = ReadSync(address, isOpcodeFetch: true);
            if (_state.LastCycle.IsStalled)
            {
                return;
            }

            _state.Instruction = GetOpCode(opcode);
            _state.InterruptMasked = (_state.Registers.Status & StatusRegister.IRQBDisable) != 0;
            _state.Registers.ProgramCounter++;
            _state.Phase = 1;
            if (Variant != ProcessorVariant.Mos6502
                && _state.Instruction.Instruction == Instruction.NOP
                && _state.Instruction.AddressMode == AddressMode.Implied
                && opcode != 0xEA
                && !(Variant == ProcessorVariant.Rockwell65C02 && opcode == 0xCB))
            {
                Complete();
            }

            return;
        }

        AdvanceInstruction();
    }

    private void AdvanceReset()
    {
        switch (_state.Phase++)
        {
            case 1:
            case 2:
                Read(_state.Registers.ProgramCounter);
                break;
            case 3:
            case 4:
            case 5:
                Read(StackAddress);
                _state.Registers.StackPointer--;
                break;
            case 6:
                _state.Data = Read(0xFFFC);
                if ((_state.PreviousSignals & ProcessorSignals.Reset) != 0)
                {
                    _state.Phase = 6;
                }

                break;
            case 7:
                _state.Registers.ProgramCounter = (ushort)(_state.Data | (Read(0xFFFD) << 8));
                _state.Registers.Status |= StatusRegister.IRQBDisable;
                if (Variant != ProcessorVariant.Mos6502)
                {
                    _state.Registers.Status &= ~StatusRegister.DecimalMode;
                }

                Complete();
                break;
        }
    }

    private void AdvanceInterrupt()
    {
        if (_state.Phase == 6 && _state.PendingNmi)
        {
            _state.InterruptNmi = true;
            _state.PendingNmi = false;
        }

        switch (_state.Phase++)
        {
            case 1:
                // The fetch the interrupt replaces with BRK still raises SYNC, though its opcode is discarded.
                ReadSync(_state.Registers.ProgramCounter, isOpcodeFetch: false);
                break;
            case 2:
                Read(_state.Registers.ProgramCounter);
                break;
            case 3:
                Push((byte)(_state.Registers.ProgramCounter >> 8));
                break;
            case 4:
                Push((byte)_state.Registers.ProgramCounter);
                break;
            case 5:
                Push((byte)((_state.Registers.Status | StatusRegister.Unused) & ~StatusRegister.BRKCommand));
                SetInterruptFlags();
                break;
            case 6:
                _state.Data = Read(_state.InterruptNmi ? (ushort)0xFFFA : (ushort)0xFFFE);
                break;
            case 7:
                ushort vector = _state.InterruptNmi ? (ushort)0xFFFB : (ushort)0xFFFF;
                _state.Registers.ProgramCounter = (ushort)(_state.Data | (Read(vector) << 8));
                Complete();
                break;
        }
    }

    private void AdvanceInstruction()
    {
        Instruction instruction = _state.Instruction.Instruction;
        if (_state.Phase >= 240)
        {
            AdvanceData();
            return;
        }

        AddressMode mode = _state.Instruction.AddressMode;
        if (mode == AddressMode.ProgramCounterRelative || mode == AddressMode.ZeroPageRelative)
        {
            AdvanceBranch();
            return;
        }

        if (instruction is not (Instruction.JMP or Instruction.JSR)
            && mode is not (AddressMode.Implied or AddressMode.Accumulator or AddressMode.Stack))
        {
            AdvanceMemory();
            return;
        }

        if (mode == AddressMode.Accumulator && instruction is Instruction.ASL or Instruction.ROL or Instruction.LSR or Instruction.ROR)
        {
            Read(_state.Registers.ProgramCounter);
            _state.Registers.Accumulator = Modify(_state.Registers.Accumulator);
            Complete();
            return;
        }

        switch (instruction)
        {
            case Instruction.JMP:
                AdvanceJump();
                return;
            case Instruction.JSR:
                AdvanceJsr();
                return;
            case Instruction.RTS:
            case Instruction.RTI:
                AdvanceReturn(instruction == Instruction.RTI);
                return;
            case Instruction.BRK:
                AdvanceBrk();
                return;
            case Instruction.PHA:
            case Instruction.PHP:
            case Instruction.PHX:
            case Instruction.PHY:
                if (_state.Phase++ == 1)
                {
                    Read(_state.Registers.ProgramCounter);
                }
                else
                {
                    Push(instruction switch
                    {
                        Instruction.PHA => _state.Registers.Accumulator,
                        Instruction.PHX => _state.Registers.X,
                        Instruction.PHY => _state.Registers.Y,
                        _ => (byte)(_state.Registers.Status | StatusRegister.Unused | StatusRegister.BRKCommand)
                    });

                    Complete();
                }

                return;
            case Instruction.PLA:
            case Instruction.PLP:
            case Instruction.PLX:
            case Instruction.PLY:
                AdvancePull(instruction);
                return;
            case Instruction.WAI:
            case Instruction.STP:
                Read(_state.Registers.ProgramCounter);
                if (_state.Phase++ == 2)
                {
                    Complete();
                    _state.Status = instruction == Instruction.WAI
                        ? ProcessorExecutionStatus.Waiting
                        : ProcessorExecutionStatus.Stopped;
                }

                return;
            case Instruction.JAM:
                Read(_state.Registers.ProgramCounter);
                _state.Phase = 2;
                _state.Status = ProcessorExecutionStatus.Jammed;
                return;
            default:
                Read(_state.Registers.ProgramCounter);
                ExecuteImplied(instruction);
                Complete();
                return;
        }
    }

    private void AdvanceJsr()
    {
        switch (_state.Phase++)
        {
            case 1:
                _state.Data = Read(_state.Registers.ProgramCounter++);
                break;
            case 2:
                Read(StackAddress);
                break;
            case 3:
                Push((byte)(_state.Registers.ProgramCounter >> 8));
                break;
            case 4:
                Push((byte)_state.Registers.ProgramCounter);
                break;
            case 5:
                _state.Registers.ProgramCounter = (ushort)(_state.Data | (Read(_state.Registers.ProgramCounter) << 8));
                Complete();
                break;
        }
    }

    private void AdvanceReturn(bool interrupt)
    {
        switch (_state.Phase++)
        {
            case 1:
                Read(_state.Registers.ProgramCounter);
                break;
            case 2:
                Read(StackAddress);
                _state.Registers.StackPointer++;
                break;
            case 3 when interrupt:
                _state.Registers.Status = (StatusRegister)((Read(StackAddress) & ~0x10) | 0x20);
                _state.Registers.StackPointer++;
                break;
            case 3:
            case 4 when interrupt:
                _state.Data = Read(StackAddress);
                _state.Registers.StackPointer++;
                break;
            case 4:
                _state.Address = (ushort)(_state.Data | (Read(StackAddress) << 8));
                break;
            case 5 when interrupt:
                _state.Registers.ProgramCounter = (ushort)(_state.Data | (Read(StackAddress) << 8));
                Complete();
                break;
            case 5:
                Read(_state.Address);
                _state.Registers.ProgramCounter = (ushort)(_state.Address + 1);
                Complete();
                break;
        }
    }

    private void AdvancePull(Instruction instruction)
    {
        switch (_state.Phase++)
        {
            case 1:
                Read(_state.Registers.ProgramCounter);
                break;
            case 2:
                Read(StackAddress);
                _state.Registers.StackPointer++;
                break;
            case 3:
                byte value = Read(StackAddress);
                if (instruction == Instruction.PLP)
                {
                    _state.Registers.Status = (StatusRegister)((value & ~0x10) | 0x20);
                }
                else
                {
                    if (instruction == Instruction.PLA)
                    {
                        _state.Registers.Accumulator = value;
                    }
                    else if (instruction == Instruction.PLX)
                    {
                        _state.Registers.X = value;
                    }
                    else
                    {
                        _state.Registers.Y = value;
                    }

                    SetNegativeZero(value);
                }

                Complete();
                break;
        }
    }

    private void AdvanceBrk()
    {
        switch (_state.Phase++)
        {
            case 1:
                Read(_state.Registers.ProgramCounter++);
                break;
            case 2:
                Push((byte)(_state.Registers.ProgramCounter >> 8));
                break;
            case 3:
                Push((byte)_state.Registers.ProgramCounter);
                break;
            case 4:
                Push((byte)(_state.Registers.Status | StatusRegister.Unused | StatusRegister.BRKCommand));
                SetInterruptFlags();
                break;
            case 5:
                _state.InterruptNmi = _state.PendingNmi;
                _state.PendingNmi = false;
                _state.Data = Read(_state.InterruptNmi ? (ushort)0xFFFA : (ushort)0xFFFE);
                break;
            case 6:
                _state.Registers.ProgramCounter = (ushort)(_state.Data
                        | (Read(_state.InterruptNmi ? (ushort)0xFFFB : (ushort)0xFFFF) << 8));

                Complete();
                break;
        }
    }

    private void SetInterruptFlags()
    {
        _state.Registers.Status |= StatusRegister.IRQBDisable;
        if (Variant != ProcessorVariant.Mos6502)
        {
            _state.Registers.Status &= ~StatusRegister.DecimalMode;
        }
    }

    private void ExecuteImplied(Instruction instruction)
    {
        switch (instruction)
        {
            case Instruction.NOP: break;
            case Instruction.CLC: _state.Registers.Status &= ~StatusRegister.Carry;
                break;
            case Instruction.SEC: _state.Registers.Status |= StatusRegister.Carry;
                break;
            case Instruction.CLI: _state.Registers.Status &= ~StatusRegister.IRQBDisable;
                break;
            case Instruction.SEI: _state.Registers.Status |= StatusRegister.IRQBDisable;
                break;
            case Instruction.CLV: _state.Registers.Status &= ~StatusRegister.Overflow;
                break;
            case Instruction.CLD: _state.Registers.Status &= ~StatusRegister.DecimalMode;
                break;
            case Instruction.SED: _state.Registers.Status |= StatusRegister.DecimalMode;
                break;
            case Instruction.TAX: _state.Registers.X = _state.Registers.Accumulator;
                SetNegativeZero(_state.Registers.X);
                break;
            case Instruction.TAY: _state.Registers.Y = _state.Registers.Accumulator;
                SetNegativeZero(_state.Registers.Y);
                break;
            case Instruction.TXA: _state.Registers.Accumulator = _state.Registers.X;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.TYA: _state.Registers.Accumulator = _state.Registers.Y;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.TSX: _state.Registers.X = _state.Registers.StackPointer;
                SetNegativeZero(_state.Registers.X);
                break;
            case Instruction.TXS: _state.Registers.StackPointer = _state.Registers.X;
                break;
            case Instruction.DEX: _state.Registers.X--;
                SetNegativeZero(_state.Registers.X);
                break;
            case Instruction.DEY: _state.Registers.Y--;
                SetNegativeZero(_state.Registers.Y);
                break;
            case Instruction.INX: _state.Registers.X++;
                SetNegativeZero(_state.Registers.X);
                break;
            case Instruction.INY: _state.Registers.Y++;
                SetNegativeZero(_state.Registers.Y);
                break;
            case Instruction.INC: _state.Registers.Accumulator++;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            case Instruction.DEC: _state.Registers.Accumulator--;
                SetNegativeZero(_state.Registers.Accumulator);
                break;
            default: throw new InvalidOperationException("The decoded implied instruction has no execution handler.");
        }
    }

    private void SetNegativeZero(byte value)
    {
        _state.Registers.Status &= ~(StatusRegister.Negative | StatusRegister.Zero);
        _state.Registers.Status |= (StatusRegister)(value & 0x80);
        if (value == 0)
        {
            _state.Registers.Status |= StatusRegister.Zero;
        }
    }

    private ushort StackAddress => (ushort)(0x100 | _state.Registers.StackPointer);

    private void Push(byte value)
    {
        Write(StackAddress, value);
        _state.Registers.StackPointer--;
    }

    // A read with SYNC high: the opcode fetch, and the fetch an interrupt discards. Kept apart from Read, which runs
    // every cycle.
    private byte ReadSync(ushort address, bool isOpcodeFetch)
    {
        if (_opcodeFetchBus is not { } fetchBus)
        {
            return Read(address, isOpcodeFetch);
        }

        byte value = fetchBus.ReadOpcode(address);
        _state.LastCycle = new()
        {
            Number = CycleCount,
            Operation = BusOperation.Read,
            Address = address,
            Value = value,
            IsOpcodeFetch = isOpcodeFetch,
            IsStalled = _state.Sequence != ProcessorSequence.Reset
                && (_state.PreviousSignals & ProcessorSignals.ReadStall) != 0
        };

        return value;
    }

    private byte Read(ushort address, bool isOpcodeFetch = false)
    {
        byte value = _bus.Read(address);
        _state.LastCycle = new()
        {
            Number = CycleCount,
            Operation = BusOperation.Read,
            Address = address,
            Value = value,
            IsOpcodeFetch = isOpcodeFetch,
            IsStalled = _state.Sequence != ProcessorSequence.Reset
                && (_state.PreviousSignals & ProcessorSignals.ReadStall) != 0
        };

        return value;
    }

    private void Write(ushort address, byte value)
    {
        _bus.Write(address, value);
        _state.LastCycle = new()
        {
            Number = CycleCount,
            Operation = BusOperation.Write,
            Address = address,
            Value = value,
            IsStalled = Variant != ProcessorVariant.Mos6502
                && (_state.PreviousSignals & ProcessorSignals.ReadStall) != 0
        };
    }

    private void Complete()
    {
        bool masked = _state.Sequence == ProcessorSequence.Instruction
            && _state.Instruction.Instruction is Instruction.CLI or Instruction.SEI or Instruction.PLP
                ? _state.InterruptMasked
                : (_state.Registers.Status & StatusRegister.IRQBDisable) != 0;

        _state.IrqPending = (_state.PreviousSignals & ProcessorSignals.InterruptRequest) != 0 && !masked;
        _state.IrqPolled = true;
        _state.Phase = 0;
        _state.Sequence = ProcessorSequence.Instruction;
    }

    private void AdvanceJam()
    {
        Read(_state.Phase is 3 or 4 ? (ushort)0xFFFE : (ushort)0xFFFF);
        if (_state.Phase < 5)
        {
            _state.Phase++;
        }
    }
}
