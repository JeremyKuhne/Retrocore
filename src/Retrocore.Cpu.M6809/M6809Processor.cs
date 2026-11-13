// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using static Retrocore.Cpu.M6809.M6809ConditionCode;

namespace Retrocore.Cpu.M6809;

/// <summary>
///  A caller-clocked Motorola MC6809 processor with a caller-owned memory bus.
/// </summary>
/// <typeparam name="TBus">The memory bus implementation.</typeparam>
/// <remarks>
///  <para>
///   Each <see cref="StepCycle"/> advances one CPU clock and performs at most one bus read or write, at the
///   cycle the MC6809 performs it. Internal cycles are bus-idle (<see cref="BusOperation.None"/>), holding the
///   last bus address without invoking the bus.
///  </para>
///  <para>
///   The core implements the documented base, page-<c>$10</c> and page-<c>$11</c> instructions, indexed
///   postbytes, hardware and software interrupts, <c>SYNC</c> and <c>CWAI</c>, and allocation-free mid-cycle
///   snapshots.
///  </para>
///  <para>
///   Undefined opcodes, prefixes and postbytes behave as the MC6809 does, as David Banks's
///   <see href="https://github.com/hoglet67/6809Decoder/wiki/Undocumented-6809-Behaviours">Undocumented 6809
///   Behaviours</see> and David Flamand's
///   <see href="https://gitlab.com/dfffffff/6809_undoc/-/blob/main/6809_undocumented_behavior.pdf">Comprehensive
///   Document of 6809 Undocumented and Undefined Behavior</see> describe them, both tested on real chips. The one
///   exception is indexed mode <c>1RRI1010</c>, which runs as <c>,R</c>.
///  </para>
/// </remarks>
public sealed partial class M6809Processor<TBus> where TBus : IProcessorBus
{
    private TBus _bus;
    private M6809ExecutionState _state;

    /// <summary>
    ///  Initializes an MC6809 at an instruction boundary with reset condition-code masks (<c>I</c> and <c>F</c>).
    /// </summary>
    /// <param name="bus">The caller-owned memory bus. A struct bus is stored by value.</param>
    public M6809Processor(TBus bus)
    {
        ArgumentNullException.ThrowIfNull(bus);
        _bus = bus;
        _state.Registers = new() { CC = (byte)(InterruptMask | FastInterruptMask) };
        _state.Status = ProcessorExecutionStatus.Running;
    }

    /// <summary>
    ///  Gets a reference to the live bus, including mutable struct-bus state.
    /// </summary>
    public ref TBus Bus => ref _bus;

    /// <summary>
    ///  Gets or sets the architectural registers at a running instruction boundary.
    /// </summary>
    /// <exception cref="InvalidOperationException">Execution is not at a running instruction boundary.</exception>
    public M6809Registers Registers
    {
        get => _state.Registers;
        set
        {
            if (!IsInstructionBoundary || _state.Status != ProcessorExecutionStatus.Running)
            {
                throw new InvalidOperationException("Registers can only be replaced at a running instruction boundary.");
            }

            _state.Registers = value;
        }
    }

    /// <summary>
    ///  Gets or sets asserted input lines, sampled on the next cycle.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">An undefined signal bit is set.</exception>
    public M6809Signals Signals
    {
        get => _state.Signals;
        set
        {
            const M6809Signals Valid = M6809Signals.Reset
                | M6809Signals.InterruptRequest
                | M6809Signals.FastInterruptRequest
                | M6809Signals.NonMaskableInterrupt
                | M6809Signals.Halt;

            if ((value & ~Valid) != 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            _state.Signals = value;
        }
    }

    /// <summary>
    ///  Gets whether no instruction, reset or interrupt sequence is in progress.
    /// </summary>
    public bool IsInstructionBoundary =>
        _state.Sequence == M6809Sequence.Instruction && _state.Operation == M6809Operation.None;

    /// <summary>
    ///  Gets whether HALT holds the processor between instructions: it was asserted as the last cycle began and
    ///  still is, so the next cycle leaves the bus idle.
    /// </summary>
    public bool IsHalted =>
        IsInstructionBoundary && _state.HaltSampled && (_state.Signals & M6809Signals.Halt) != 0;

    /// <summary>
    ///  Gets whether the processor is waiting in <c>SYNC</c> or <c>CWAI</c>.
    /// </summary>
    public bool IsWaiting => _state.Wait != M6809WaitState.None;

    /// <summary>
    ///  Gets the elapsed CPU clock count.
    /// </summary>
    public ulong CycleCount => _state.CycleCount;

    /// <summary>
    ///  Gets the execution status.
    /// </summary>
    public ProcessorExecutionStatus Status => _state.Status;

    /// <summary>
    ///  Gets the bus activity of the most recently completed clock, built on request.
    /// </summary>
    public ProcessorCycle LastCycle => new()
    {
        Number = _state.CycleCount,
        Operation = _state.Activity,
        Address = _state.Bus,
        Value = _state.Activity == BusOperation.None ? (byte)0 : _state.Value,
        IsOpcodeFetch = _state.OpcodeFetch
    };

    /// <summary>
    ///  Gets whether the most recent cycle fetched the first opcode byte of an instruction.
    /// </summary>
    public bool FetchedOpcode => _state.OpcodeFetch;

    /// <summary>
    ///  Starts a seven-cycle reset sequence and abandons any in-flight instruction or wait state.
    /// </summary>
    public void Reset()
    {
        _state.Sequence = M6809Sequence.Reset;
        _state.Operation = M6809Operation.None;
        _state.AddressPhase = M6809AddressPhase.Ready;
        _state.Step = 0;
        _state.Wait = M6809WaitState.None;
        _state.PendingNmi = false;
        _state.Registers.NmiArmed = false;
        _state.Status = ProcessorExecutionStatus.Running;
    }

    /// <summary>
    ///  Captures the complete processor state without accessing the bus or allocating.
    /// </summary>
    /// <returns>A snapshot that can be restored into this processor.</returns>
    public M6809Snapshot CaptureState() => new(_state);

    /// <summary>
    ///  Restores a captured state without accessing the bus or allocating.
    /// </summary>
    /// <param name="snapshot">A snapshot returned by <see cref="CaptureState"/>.</param>
    /// <exception cref="ArgumentException">The snapshot is uninitialized.</exception>
    public void RestoreState(M6809Snapshot snapshot)
    {
        if (!snapshot.IsInitialized)
        {
            throw new ArgumentException("A captured snapshot is required.", nameof(snapshot));
        }

        _state = snapshot.State;
    }

    /// <summary>
    ///  Advances one CPU clock cycle; <see cref="LastCycle"/> then describes its bus activity.
    /// </summary>
    public void StepCycle()
    {
        if (_state.Signals != _state.PreviousSignals)
        {
            SampleSignals();
        }

        bool haltSampled = _state.HaltSampled;
        bool halt = (_state.Signals & M6809Signals.Halt) != 0;
        _state.HaltSampled = halt;
        _state.CycleCount++;
        _state.Activity = BusOperation.None;
        _state.OpcodeFetch = false;

        if (_state.Sequence == M6809Sequence.Reset)
        {
            AdvanceReset();
            return;
        }

        if (_state.Sequence == M6809Sequence.Interrupt)
        {
            AdvanceInterrupt();
            return;
        }

        if (_state.Operation != M6809Operation.None)
        {
            AdvanceOperation();
            return;
        }

        // HALT takes effect between instructions when it was asserted before the last one's final cycle, so a HALT
        // raised by that cycle's own access stops the processor an instruction later. The halted cycles leave the
        // bus idle.
        if (halt && haltSampled)
        {
            return;
        }

        if (_state.Wait != M6809WaitState.None)
        {
            if (!WaitCanResume())
            {
                _state.Status = ProcessorExecutionStatus.Waiting;
                return;
            }

            bool prestacked = _state.Wait == M6809WaitState.Cwai;
            _state.Wait = M6809WaitState.None;
            _state.Status = ProcessorExecutionStatus.Running;
            if (StartPendingInterrupt(prestacked))
            {
                return;
            }

            // A masked interrupt wakes SYNC; one internal cycle re-enables the bus before the next fetch.
            return;
        }

        if (StartPendingInterrupt(prestacked: false))
        {
            return;
        }

        // An unprefixed store immediate's flags depend on the instruction before it.
        _state.PreviousFlagGroup = _state.FlagGroup;
        _state.PreviousFlagGroupValue = _state.FlagGroupValue;
        _state.FlagGroup = M6809FlagGroup.Default;
        _state.Step = 0;
        DecodePage0(ReadOperand(opcode: true));
    }

    /// <summary>
    ///  Finishes the current instruction or sequence, or runs one from a boundary, within a clock budget.
    /// </summary>
    /// <param name="maximumCycles">The maximum number of clocks to execute.</param>
    /// <returns>The completion reason and clocks run.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The limit is not positive.</exception>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = _state.CycleCount;
        bool started = !IsInstructionBoundary;
        for (int index = 0; index < maximumCycles; index++)
        {
            if (IsWaiting && IsInstructionBoundary && !CanResumeFromSignals())
            {
                return new() { Status = ProcessorExecutionStatus.Waiting, Cycles = _state.CycleCount - start };
            }

            StepCycle();
            started |= FetchedOpcode || !IsInstructionBoundary;
            if (started && IsInstructionBoundary)
            {
                return new()
                {
                    Status = _state.Status == ProcessorExecutionStatus.Running
                        ? ProcessorExecutionStatus.InstructionComplete
                        : _state.Status,
                    Cycles = _state.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = _state.CycleCount - start };
    }

    /// <summary>
    ///  Runs exactly the requested number of CPU clocks, including waiting ones.
    /// </summary>
    /// <param name="cycleBudget">The number of clocks.</param>
    /// <returns>The status and clocks run.</returns>
    public ProcessorExecutionResult Run(ulong cycleBudget)
    {
        for (ulong index = 0; index < cycleBudget; index++)
        {
            StepCycle();
        }

        return new()
        {
            Status = IsWaiting ? ProcessorExecutionStatus.Waiting : ProcessorExecutionStatus.CycleBudgetExhausted,
            Cycles = cycleBudget
        };
    }

    private void SampleSignals()
    {
        M6809Signals rising = _state.Signals & ~_state.PreviousSignals;
        if (_state.Registers.NmiArmed && (rising & M6809Signals.NonMaskableInterrupt) != 0)
        {
            _state.PendingNmi = true;
        }

        if ((rising & M6809Signals.Reset) != 0 || ((_state.Signals & M6809Signals.Reset) != 0 && _state.Sequence != M6809Sequence.Reset))
        {
            Reset();
        }

        _state.PreviousSignals = _state.Signals;
    }

    private bool UnmaskedInterruptReady(bool pendingNmi) =>
        pendingNmi
            || ((_state.Signals & M6809Signals.FastInterruptRequest) != 0 && (_state.Registers.CC & (byte)FastInterruptMask) == 0)
            || ((_state.Signals & M6809Signals.InterruptRequest) != 0 && (_state.Registers.CC & (byte)InterruptMask) == 0);

    private bool WaitCanResume() =>
        _state.Wait == M6809WaitState.Sync
            ? _state.PendingNmi || (_state.Signals & (M6809Signals.InterruptRequest | M6809Signals.FastInterruptRequest)) != 0
            : UnmaskedInterruptReady(_state.PendingNmi);

    private bool CanResumeFromSignals()
    {
        if ((_state.Signals & M6809Signals.Reset) != 0)
        {
            return true;
        }

        M6809Signals rising = _state.Signals & ~_state.PreviousSignals;
        bool pendingNmi = _state.PendingNmi || (_state.Registers.NmiArmed && (rising & M6809Signals.NonMaskableInterrupt) != 0);
        return _state.Wait == M6809WaitState.Sync
            ? pendingNmi || (_state.Signals & (M6809Signals.InterruptRequest | M6809Signals.FastInterruptRequest)) != 0
            : UnmaskedInterruptReady(pendingNmi);
    }

    private bool StartPendingInterrupt(bool prestacked)
    {
        ref M6809Registers r = ref _state.Registers;
        bool nmi = _state.PendingNmi;
        bool firq = !nmi && (_state.Signals & M6809Signals.FastInterruptRequest) != 0 && (r.CC & (byte)FastInterruptMask) == 0;
        bool irq = !nmi && !firq && (_state.Signals & M6809Signals.InterruptRequest) != 0 && (r.CC & (byte)InterruptMask) == 0;
        if (!nmi && !firq && !irq)
        {
            return false;
        }

        _state.Sequence = M6809Sequence.Interrupt;
        _state.Operation = M6809Operation.None;
        _state.AddressPhase = M6809AddressPhase.Ready;
        _state.Step = 0;
        _state.Effective = nmi ? (ushort)0xFFFC : firq ? (ushort)0xFFF6 : (ushort)0xFFF8;
        _state.Postbyte = nmi ? (byte)1 : firq ? (byte)2 : (byte)3;
        _state.InterruptPrestacked = prestacked;
        if (nmi)
        {
            _state.PendingNmi = false;
        }

        AdvanceInterrupt();
        return true;
    }

    private void Complete()
    {
        _state.Sequence = M6809Sequence.Instruction;
        _state.Operation = M6809Operation.None;
        _state.AddressPhase = M6809AddressPhase.Ready;
        _state.Step = 0;
        _state.Status = _state.Wait == M6809WaitState.None
            ? ProcessorExecutionStatus.Running
            : ProcessorExecutionStatus.Waiting;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private byte ReadOperand(bool opcode)
    {
        ushort address = _state.Registers.PC++;
        byte value = _bus.Read(address);
        _state.Bus = address;
        _state.Value = value;
        _state.Activity = BusOperation.Read;
        _state.OpcodeFetch = opcode;
        return value;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private byte BusRead(ushort address)
    {
        byte value = _bus.Read(address);
        _state.Bus = address;
        _state.Value = value;
        _state.Activity = BusOperation.Read;
        return value;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void BusWrite(ushort address, byte value)
    {
        _bus.Write(address, value);
        _state.Bus = address;
        _state.Value = value;
        _state.Activity = BusOperation.Write;
    }
}
