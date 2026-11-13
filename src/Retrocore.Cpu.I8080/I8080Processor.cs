// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  A caller-clocked, state-exact Intel 8080 or 8085 with a caller-owned memory and I/O bus.
/// </summary>
/// <typeparam name="TBus">The memory and I/O bus.</typeparam>
/// <remarks>
///  <para>
///   Each <see cref="StepCycle"/> is one clock state and makes at most one bus access. Every machine cycle puts its
///   address out on T1, samples READY on T2, where <see cref="I8080Signals.Wait"/> adds wait states, and moves its
///   byte on T3; M1 decodes on T4, and an instruction with the 8080's 5-state or the 8085's 6-state M1 adds idle
///   states after it. An I/O port's number is on both halves of the address bus, as the chips put it.
///  </para>
///  <para>
///   An interrupt acknowledge takes one opcode from <see cref="InterruptData"/>, normally <c>RST</c>; a device that
///   supplies a longer instruction, such as an 8259's <c>CALL</c>, is not modelled, so its operands would come from
///   memory. HOLD is not modelled.
///  </para>
/// </remarks>
public sealed partial class I8080Processor<TBus> where TBus : IProcessorBus, IIoBus
{
    // The activity of a state that READY stretched; LastCycle reports it as no operation, stalled.
    private const BusOperation StalledActivity = (BusOperation)0xFF;

    private TBus _bus;
    private I8080ExecutionState _state;

    /// <summary>
    ///  Constructs a processor in its reset state, at an instruction boundary with PC at zero.
    /// </summary>
    /// <param name="bus">The caller-owned bus. A struct bus is stored by value.</param>
    /// <param name="variant">The CPU: the 8080 or the 8085.</param>
    /// <exception cref="ArgumentOutOfRangeException">The variant is undefined.</exception>
    public I8080Processor(TBus bus, I8080Variant variant = I8080Variant.I8080)
    {
        ArgumentNullException.ThrowIfNull(bus);
        if (variant is not (I8080Variant.I8080 or I8080Variant.I8085))
        {
            throw new ArgumentOutOfRangeException(nameof(variant));
        }

        _bus = bus;
        _state.Variant = variant;
        _state.InterruptData = 0xFF;
        Reset();
        _state.Registers.F = Is8085 ? (byte)0 : I8080Flags.V;
    }

    /// <summary>
    ///  Gets the CPU.
    /// </summary>
    public I8080Variant Variant => _state.Variant;

    /// <summary>
    ///  Gets a reference to the live bus, including mutable struct-bus state.
    /// </summary>
    public ref TBus Bus => ref _bus;

    /// <summary>
    ///  Gets or sets the registers at an instruction boundary.
    /// </summary>
    /// <exception cref="InvalidOperationException">An instruction is in progress.</exception>
    public I8080Registers Registers
    {
        get => _state.Registers;
        set
        {
            if (!IsInstructionBoundary)
            {
                throw new InvalidOperationException("Registers can only be replaced at an instruction boundary.");
            }

            _state.Registers = value;
        }
    }

    /// <summary>
    ///  Gets or sets the input lines, sampled on the next state. The 8080 has only RESET, INT and READY.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">A line the CPU lacks is set.</exception>
    public I8080Signals Signals
    {
        get => _state.Signals;
        set
        {
            const I8080Signals Common = I8080Signals.Reset | I8080Signals.InterruptRequest | I8080Signals.Wait;
            I8080Signals valid = Is8085 ? (I8080Signals)0xFF : Common;
            _state.Signals = (value & ~valid) == 0 ? value : throw new ArgumentOutOfRangeException(nameof(value));
        }
    }

    /// <summary>
    ///  Gets or sets the opcode a device puts on the data bus when it acknowledges an INT or INTR, normally an
    ///  <c>RST</c>. A floating bus reads <c>$FF</c>, which is <c>RST 7</c>.
    /// </summary>
    public byte InterruptData
    {
        get => _state.InterruptData;
        set => _state.InterruptData = value;
    }

    /// <summary>
    ///  Gets whether no instruction or interrupt sequence is in progress. A halted processor is at one between its
    ///  halt states.
    /// </summary>
    public bool IsInstructionBoundary => _state.Operation == I8080Operation.None && _state.Cycle == I8080MachineCycle.None;

    /// <summary>
    ///  Gets whether <c>HLT</c> holds the processor until an interrupt or reset.
    /// </summary>
    public bool IsHalted => _state.Halted;

    /// <summary>
    ///  Gets the elapsed states.
    /// </summary>
    public ulong CycleCount => _state.CycleCount;

    /// <summary>
    ///  Gets the execution status: <see cref="ProcessorExecutionStatus.Waiting"/> while halted.
    /// </summary>
    public ProcessorExecutionStatus Status => _state.Status;

    private bool Is8085 => _state.Variant == I8080Variant.I8085;

    /// <summary>
    ///  Resets the processor: PC clears, interrupts are disabled, and on the 8085 the RST 5.5, 6.5 and 7.5 masks
    ///  are set, the RST 7.5 latch and SOD clear. Other registers keep their values. Any instruction in progress is
    ///  abandoned.
    /// </summary>
    public void Reset()
    {
        ref I8080Registers r = ref _state.Registers;
        r.PC = 0;
        r.InterruptEnable = false;
        r.AfterEnable = false;
        r.InterruptMask = Is8085 ? (byte)7 : (byte)0;
        r.SerialOutput = false;
        _state.PendingTrap = false;
        _state.PendingRestart75 = false;
        _state.AfterTrap = false;
        _state.Cycle = I8080MachineCycle.None;
        _state.Operation = I8080Operation.None;
        _state.Halted = false;
        _state.Status = ProcessorExecutionStatus.Running;
    }

    /// <summary>
    ///  Captures the complete processor state without accessing the bus.
    /// </summary>
    /// <returns>The snapshot.</returns>
    public I8080Snapshot CaptureState() => new(_state);

    /// <summary>
    ///  Restores a captured state without accessing the bus.
    /// </summary>
    /// <param name="snapshot">A snapshot from <see cref="CaptureState"/> of a processor of the same CPU.</param>
    /// <exception cref="ArgumentException">The snapshot is uninitialized or of the other CPU.</exception>
    public void RestoreState(I8080Snapshot snapshot) =>
        _state = snapshot.IsInitialized && snapshot.State.Variant == _state.Variant
            ? snapshot.State
            : throw new ArgumentException("A snapshot captured from the same CPU is required.", nameof(snapshot));

    /// <summary>
    ///  Gets the bus activity of the last state, built on request so stepping costs nothing for it.
    /// </summary>
    public ProcessorCycle LastCycle
    {
        get
        {
            BusOperation activity = _state.Activity;
            bool stalled = activity == StalledActivity;
            return new()
            {
                Number = _state.CycleCount,
                Operation = stalled ? BusOperation.None : activity,
                Address = _state.Bus,
                Value = activity == BusOperation.None || stalled ? (byte)0 : _state.Data,
                IsOpcodeFetch = FetchedOpcode,
                IsStalled = stalled
            };
        }
    }

    /// <summary>
    ///  Gets whether the last state read an opcode: the T3 of an M1 or of an interrupt acknowledge. Cheaper than
    ///  <see cref="LastCycle"/> for stepping to instructions.
    /// </summary>
    public bool FetchedOpcode =>
        _state.OpcodeTransfer && _state.Activity is BusOperation.Read or BusOperation.InterruptAcknowledge;

    /// <summary>
    ///  Advances one state; <see cref="LastCycle"/> then describes its bus activity.
    /// </summary>
    public void StepCycle()
    {
        if (_state.Signals != _state.PreviousSignals) { SampleSignals(); }
        _state.CycleCount++;
        if (_state.Cycle == I8080MachineCycle.None) { Begin(); }
        Tick();
    }

    /// <summary>
    ///  Finishes the current instruction, or runs one at a boundary, within a state limit. A halted processor returns
    ///  at once unless an interrupt will end the halt.
    /// </summary>
    /// <param name="maximumCycles">The most states to run.</param>
    /// <returns>Why it stopped and the states it ran.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The limit is not positive.</exception>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = _state.CycleCount;
        for (int index = 0; index < maximumCycles; index++)
        {
            if (_state.Halted && IsInstructionBoundary && !InterruptReady())
            {
                return new() { Status = ProcessorExecutionStatus.Waiting, Cycles = _state.CycleCount - start };
            }

            StepCycle();
            if (IsInstructionBoundary)
            {
                return new()
                {
                    Status = ProcessorExecutionStatus.InstructionComplete,
                    Cycles = _state.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = _state.CycleCount - start };
    }

    /// <summary>
    ///  Runs exactly the requested states, including halted ones.
    /// </summary>
    /// <param name="cycleBudget">The states to run.</param>
    /// <returns>The status and the states run.</returns>
    public ProcessorExecutionResult Run(ulong cycleBudget)
    {
        for (ulong index = 0; index < cycleBudget; index++) { StepCycle(); }
        return new()
        {
            Status = _state.Halted ? ProcessorExecutionStatus.Waiting : ProcessorExecutionStatus.CycleBudgetExhausted,
            Cycles = cycleBudget
        };
    }

    private void SampleSignals()
    {
        I8080Signals asserted = _state.Signals & ~_state.PreviousSignals;
        _state.PreviousSignals = _state.Signals;
        _state.PendingTrap |= (asserted & I8080Signals.Trap) != 0;
        _state.PendingRestart75 |= (asserted & I8080Signals.Restart75) != 0;
        if ((asserted & I8080Signals.Reset) != 0) { Reset(); }
    }

    // TRAP is taken at any boundary; the others need interrupts enabled, and not right after EI. The 8085's
    // RST 7.5, 6.5 and 5.5 also need their mask bits clear.
    private bool InterruptReady()
    {
        if (_state.PendingTrap) { return true; }
        ref I8080Registers r = ref _state.Registers;
        if (!r.InterruptEnable || r.AfterEnable) { return false; }
        if ((_state.Signals & I8080Signals.InterruptRequest) != 0) { return true; }
        return Is8085 && PendingVector() != 0;
    }

    // The highest-priority unmasked RST 7.5, 6.5 or 5.5 vector, or 0.
    private ushort PendingVector()
    {
        byte mask = _state.Registers.InterruptMask;
        if (_state.PendingRestart75 && (mask & 4) == 0) { return 0x003C; }
        if ((_state.Signals & I8080Signals.Restart65) != 0 && (mask & 2) == 0) { return 0x0034; }
        if ((_state.Signals & I8080Signals.Restart55) != 0 && (mask & 1) == 0) { return 0x002C; }
        return 0;
    }

    // Chooses the next machine cycle at a boundary: an interrupt, a halt state, or a fetch.
    private void Begin()
    {
        if (InterruptReady())
        {
            AcceptInterrupt();
            return;
        }

        _state.T = 0;
        if (_state.Halted)
        {
            _state.Status = ProcessorExecutionStatus.Waiting;
            _state.Cycle = I8080MachineCycle.Internal;
            _state.Length = 1;
            return;
        }

        _state.Status = ProcessorExecutionStatus.Running;
        _state.Cycle = I8080MachineCycle.Fetch;
        _state.Operation = I8080Operation.Decode;
        _state.Step = 0;
    }

    private void AcceptInterrupt()
    {
        ref I8080Registers r = ref _state.Registers;
        _state.Halted = false;
        _state.Status = ProcessorExecutionStatus.Running;
        _state.T = 0;
        if (_state.PendingTrap)
        {
            _state.PendingTrap = false;
            _state.TrapEnable = r.InterruptEnable;
            _state.AfterTrap = true;
            r.InterruptEnable = false;
            StartVectored(0x0024);
            return;
        }

        // TRAP, then RST 7.5, 6.5 and 5.5, then INTR.
        r.InterruptEnable = false;
        ushort vector = Is8085 ? PendingVector() : (ushort)0;
        if (vector != 0)
        {
            if (vector == 0x003C) { _state.PendingRestart75 = false; }
            StartVectored(vector);
            return;
        }

        // INT or INTR: the device's opcode runs, normally an RST.
        _state.Cycle = I8080MachineCycle.Acknowledge;
        _state.Operation = I8080Operation.Decode;
        _state.Step = 0;
    }

    // The 8085's internal restarts: 6 bus-idle states in place of M1, then the restart's two pushes.
    private void StartVectored(ushort vector)
    {
        _state.Word = vector;
        _state.Selector = Always;
        _state.Operation = I8080Operation.Restart;
        _state.Step = 1;
        Internal(6);
    }

    // Runs the current state of the machine cycle; a cycle's last state continues the instruction.
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void Tick()
    {
        if (_state.Cycle == I8080MachineCycle.Internal)
        {
            _state.Activity = BusOperation.None;
            if (++_state.T >= _state.Length) { EndCycle(); }
            return;
        }

        bool fetch = _state.Cycle is I8080MachineCycle.Fetch or I8080MachineCycle.Acknowledge;
        switch (_state.T)
        {
            case 0:
                _state.Bus = fetch ? _state.Registers.PC : _state.Address;
                _state.Activity = BusOperation.None;
                _state.T++;
                return;
            case 1:
                if ((_state.Signals & I8080Signals.Wait) != 0)
                {
                    _state.Activity = StalledActivity;
                    return;
                }

                _state.Activity = BusOperation.None;
                _state.T++;
                return;
            case 2:
                Transfer();
                if (fetch)
                {
                    _state.T++;
                    return;
                }

                EndCycle();
                return;
            default:
                // T4 of M1 decodes.
                _state.Activity = BusOperation.None;
                EndCycle();
                return;
        }
    }

    // T3: the cycle moves its byte.
    private void Transfer()
    {
        _state.OpcodeTransfer = false;
        switch (_state.Cycle)
        {
            case I8080MachineCycle.Fetch:
                _state.Value = _bus.Read(_state.Bus);
                _state.Registers.PC++;
                _state.Activity = BusOperation.Read;
                _state.OpcodeTransfer = true;
                break;
            case I8080MachineCycle.Acknowledge:
                _state.Value = _state.InterruptData;
                _state.Activity = BusOperation.InterruptAcknowledge;
                _state.OpcodeTransfer = true;
                break;
            case I8080MachineCycle.Read:
                _state.Value = _bus.Read(_state.Bus);
                _state.Activity = BusOperation.Read;
                break;
            case I8080MachineCycle.Write:
                _bus.Write(_state.Bus, _state.Value);
                _state.Activity = BusOperation.Write;
                break;
            case I8080MachineCycle.InputRead:
                _state.Value = _bus.In(_state.Bus);
                _state.Activity = BusOperation.IoRead;
                break;
            default:
                _bus.Out(_state.Bus, _state.Value);
                _state.Activity = BusOperation.IoWrite;
                break;
        }

        _state.Data = _state.Value;
    }

    // The machine cycle's last state: the instruction takes its result and chooses what follows.
    private void EndCycle()
    {
        _state.Cycle = I8080MachineCycle.None;
        _state.T = 0;
        switch (_state.Operation)
        {
            case I8080Operation.None:
                return;
            case I8080Operation.Decode:
                Decode(_state.Value);
                return;
            default:
                Execute();
                return;
        }
    }
}
