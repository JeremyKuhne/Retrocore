// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  A caller-clocked, T-state exact Z80 with a caller-owned memory and I/O bus.
/// </summary>
/// <typeparam name="TBus">The memory and I/O bus.</typeparam>
/// <remarks>
///  <para>
///   Each <see cref="StepCycle"/> is one T-state and makes at most one bus access, at the T-state the Z80
///   makes it: an opcode read on T2 of M1 followed by refresh, memory on T2 of a 3 T-state cycle, I/O on T3
///   of a 4 T-state cycle. WAIT holds an access while it is asserted. The core keeps the undocumented state
///   later instructions observe: MEMPTR (WZ), Q for <c>SCF</c> and <c>CCF</c>, and the X and Y flags.
///  </para>
/// </remarks>
public sealed partial class Z80Processor<TBus> where TBus : IProcessorBus, IIoBus
{
    // The activity of a T-state that WAIT stretched; LastCycle reports it as no operation, stalled.
    private const BusOperation StalledActivity = (BusOperation)0xFF;

    private TBus _bus;
    private Z80ExecutionState _state;

    /// <summary>
    ///  Constructs a processor in its reset state, at an instruction boundary with PC at zero.
    /// </summary>
    /// <param name="bus">The caller-owned bus. A struct bus is stored by value.</param>
    public Z80Processor(TBus bus)
    {
        ArgumentNullException.ThrowIfNull(bus);
        _bus = bus;
        _state.InterruptData = 0xFF;
        ResetRegisters();
    }

    /// <summary>
    ///  Gets a reference to the live bus, including mutable struct-bus state.
    /// </summary>
    public ref TBus Bus => ref _bus;

    /// <summary>
    ///  Gets or sets the registers at an instruction boundary.
    /// </summary>
    /// <exception cref="InvalidOperationException">An instruction is in progress.</exception>
    public Z80Registers Registers
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
    ///  Gets or sets the input lines, sampled on the next T-state.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">An undefined line is set.</exception>
    public Z80Signals Signals
    {
        get => _state.Signals;
        set
        {
            const Z80Signals Interrupts = Z80Signals.InterruptRequest | Z80Signals.NonMaskableInterrupt;
            const Z80Signals Valid = Z80Signals.Reset | Interrupts | Z80Signals.Wait;

            _state.Signals = (value & ~Valid) == 0 ? value : throw new ArgumentOutOfRangeException(nameof(value));
        }
    }

    /// <summary>
    ///  Gets or sets the byte a device puts on the data bus when it acknowledges an interrupt: the opcode in
    ///  mode 0, ignored in mode 1, the vector's low byte in mode 2. A floating bus reads <c>$FF</c>.
    /// </summary>
    public byte InterruptData
    {
        get => _state.InterruptData;
        set => _state.InterruptData = value;
    }

    /// <summary>
    ///  Gets whether no instruction or interrupt sequence is in progress. A halted processor is at one between
    ///  its refresh cycles.
    /// </summary>
    public bool IsInstructionBoundary => _state.Operation == Z80Operation.None && _state.Cycle == Z80MachineCycle.None;

    /// <summary>
    ///  Gets whether <c>HALT</c> holds the processor until an interrupt or reset.
    /// </summary>
    public bool IsHalted => _state.Halted;

    /// <summary>
    ///  Gets the elapsed T-states.
    /// </summary>
    public ulong CycleCount => _state.CycleCount;

    /// <summary>
    ///  Gets the execution status: <see cref="ProcessorExecutionStatus.Waiting"/> while halted.
    /// </summary>
    public ProcessorExecutionStatus Status => _state.Status;

    /// <summary>
    ///  Resets the processor: PC, I, R, the interrupt flip-flops and mode clear, and AF and SP become
    ///  <c>$FFFF</c>, abandoning any instruction in progress.
    /// </summary>
    public void Reset()
    {
        ResetRegisters();
        _state.Cycle = Z80MachineCycle.None;
        _state.Operation = Z80Operation.None;
        _state.Halted = false;
        _state.PendingNmi = false;
        _state.Status = ProcessorExecutionStatus.Running;
    }

    /// <summary>
    ///  Captures the complete processor state without accessing the bus.
    /// </summary>
    /// <returns>The snapshot.</returns>
    public Z80Snapshot CaptureState() => new(_state);

    /// <summary>
    ///  Restores a captured state without accessing the bus.
    /// </summary>
    /// <param name="snapshot">A snapshot from <see cref="CaptureState"/>.</param>
    /// <exception cref="ArgumentException">The snapshot is uninitialized.</exception>
    public void RestoreState(Z80Snapshot snapshot) =>
        _state = snapshot.IsInitialized
            ? snapshot.State
            : throw new ArgumentException("A captured snapshot is required.", nameof(snapshot));

    /// <summary>
    ///  Gets the bus activity of the last T-state, built on request so stepping costs nothing for it.
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
                Value = activity is BusOperation.None or BusOperation.Refresh || stalled ? (byte)0 : _state.Value,
                IsOpcodeFetch = FetchedOpcode,
                IsStalled = stalled
            };
        }
    }

    /// <summary>
    ///  Gets whether the last T-state read an opcode: an M1 read, or the acknowledge that takes an interrupt
    ///  opcode, not stretched by WAIT. Cheaper than <see cref="LastCycle"/> for stepping to instructions.
    /// </summary>
    public bool FetchedOpcode =>
        _state.Activity == BusOperation.InterruptAcknowledge
            || (_state.Activity == BusOperation.Read && _state.Cycle is Z80MachineCycle.Fetch
                or Z80MachineCycle.HaltFetch
                or Z80MachineCycle.NonMaskableFetch);

    /// <summary>
    ///  Advances one T-state; <see cref="LastCycle"/> then describes its bus activity.
    /// </summary>
    public void StepCycle()
    {
        if (_state.Signals != _state.PreviousSignals) { SampleSignals(); }
        _state.CycleCount++;
        if (_state.Cycle == Z80MachineCycle.None) { Begin(); }
        Tick();
    }

    /// <summary>
    ///  Finishes the current instruction, or runs one at a boundary, within a T-state limit. A halted processor
    ///  returns at once unless an interrupt will end the halt.
    /// </summary>
    /// <param name="maximumCycles">The most T-states to run.</param>
    /// <returns>Why it stopped and the T-states it ran.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The limit is not positive.</exception>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = _state.CycleCount;
        for (int index = 0; index < maximumCycles; index++)
        {
            // An NMI or RESET edge while halted must latch before deciding whether the CPU still waits.
            if (_state.Halted && _state.Signals != _state.PreviousSignals) { SampleSignals(); }
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
    ///  Runs exactly the requested T-states, including halted ones.
    /// </summary>
    /// <param name="cycleBudget">The T-states to run.</param>
    /// <returns>The status and the T-states run.</returns>
    public ProcessorExecutionResult Run(ulong cycleBudget)
    {
        for (ulong index = 0; index < cycleBudget; index++) { StepCycle(); }
        return new()
        {
            Status = _state.Halted ? ProcessorExecutionStatus.Waiting : ProcessorExecutionStatus.CycleBudgetExhausted,
            Cycles = cycleBudget
        };
    }

    private void ResetRegisters()
    {
        _state.Registers = new()
        {
            AF = 0xFFFF,
            SP = 0xFFFF,
            Iff1 = false,
            Iff2 = false
        };
    }

    private void SampleSignals()
    {
        Z80Signals asserted = _state.Signals & ~_state.PreviousSignals;
        _state.PendingNmi |= (asserted & Z80Signals.NonMaskableInterrupt) != 0;
        _state.PreviousSignals = _state.Signals;
        if ((asserted & Z80Signals.Reset) != 0) { Reset(); }
    }

    // A maskable interrupt is taken when INT is low, IFF1 is set and the last instruction was not EI.
    private bool InterruptReady() =>
        _state.PendingNmi
            || ((_state.Signals & Z80Signals.InterruptRequest) != 0 && _state.Registers.Iff1 && !_state.Registers.AfterEnable);

    // Chooses the next machine cycle: the instruction's next one, or at a boundary an interrupt or a fetch.
    private void Begin()
    {
        if (_state.Operation != Z80Operation.None) { return; }
        if (InterruptReady())
        {
            AcceptInterrupt();
            return;
        }

        _state.Status = _state.Halted ? ProcessorExecutionStatus.Waiting : ProcessorExecutionStatus.Running;
        _state.Cycle = _state.Halted ? Z80MachineCycle.HaltFetch : Z80MachineCycle.Fetch;
        _state.T = 0;
        if (!_state.Halted)
        {
            _state.Operation = Z80Operation.Decode;
            _state.Step = 0;
            _state.Index = 0;
            _state.FlagsWritten = false;
        }
    }

    private void AcceptInterrupt()
    {
        ref Z80Registers registers = ref _state.Registers;
        _state.Halted = false;
        _state.Status = ProcessorExecutionStatus.Running;
        _state.FlagsWritten = false;
        _state.Index = 0;
        _state.Step = 0;

        // An interrupt right after LD A,I or LD A,R clears the parity flag they copied from IFF2.
        if (registers.AfterLoadInterrupt)
        {
            registers.F &= unchecked((byte)~Z80Flags.PV);
            _state.FlagsWritten = true;
        }

        registers.AfterLoadInterrupt = false;
        registers.AfterEnable = false;
        _state.T = 0;
        if (_state.PendingNmi)
        {
            _state.PendingNmi = false;
            registers.Iff1 = false;
            _state.Operation = Z80Operation.NonMaskable;
            _state.Cycle = Z80MachineCycle.NonMaskableFetch;
            return;
        }

        registers.Iff1 = false;
        registers.Iff2 = false;
        _state.Cycle = Z80MachineCycle.Acknowledge;

        // Mode 0 executes the byte on the bus as an opcode, normally an RST.
        _state.Operation = registers.InterruptMode == 0 ? Z80Operation.Decode : Z80Operation.Interrupt;
    }

    // Runs the current T-state of the machine cycle, then continues the instruction when the cycle ends. One
    // jump on the cycle kind and T-state chooses the work; each case is what that T-state does.
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void Tick()
    {
        const int Fetch = (int)Z80MachineCycle.Fetch << 3;
        const int HaltFetch = (int)Z80MachineCycle.HaltFetch << 3;
        const int NonMaskableFetch = (int)Z80MachineCycle.NonMaskableFetch << 3;
        const int Acknowledge = (int)Z80MachineCycle.Acknowledge << 3;
        const int Read = (int)Z80MachineCycle.Read << 3;
        const int Write = (int)Z80MachineCycle.Write << 3;
        const int InputRead = (int)Z80MachineCycle.InputRead << 3;
        const int OutputWrite = (int)Z80MachineCycle.OutputWrite << 3;

        switch (((int)_state.Cycle << 3) | _state.T)
        {
            case Fetch:
            case HaltFetch:
            case NonMaskableFetch:
            case Acknowledge:
                _state.Bus = _state.Registers.PC;
                _state.Activity = BusOperation.None;
                _state.T++;
                return;
            case Read:
            case Write:
            case InputRead:
            case OutputWrite:
                _state.Bus = _state.Address;
                _state.Activity = BusOperation.None;
                _state.T++;
                return;
            case Fetch + 1:
                if (Stalled()) { return; }
                _state.Value = _bus.Read(_state.Bus);
                _state.Registers.PC++;
                _state.Activity = BusOperation.Read;
                _state.T++;
                return;
            case HaltFetch + 1:
            case NonMaskableFetch + 1:
            case Read + 1:
                if (Stalled()) { return; }
                _state.Value = _bus.Read(_state.Bus);
                _state.Activity = BusOperation.Read;
                _state.T++;
                return;
            case Write + 1:
                if (Stalled()) { return; }
                _bus.Write(_state.Bus, _state.Value);
                _state.Activity = BusOperation.Write;
                _state.T++;
                return;
            case InputRead + 2:
                if (Stalled()) { return; }
                _state.Value = _bus.In(_state.Bus);
                _state.Activity = BusOperation.IoRead;
                _state.T++;
                return;
            case OutputWrite + 2:
                if (Stalled()) { return; }
                _bus.Out(_state.Bus, _state.Value);
                _state.Activity = BusOperation.IoWrite;
                _state.T++;
                return;
            case Acknowledge + 3:
                if (Stalled()) { return; }
                _state.Value = _state.InterruptData;
                _state.Activity = BusOperation.InterruptAcknowledge;
                _state.T++;
                return;
            case Fetch + 2:
            case HaltFetch + 2:
            case NonMaskableFetch + 2:
            case Acknowledge + 4:
                Refresh();
                _state.T++;
                return;
            case NonMaskableFetch + 3:
            case Acknowledge + 1:
            case Acknowledge + 2:
            case InputRead + 1:
            case OutputWrite + 1:
                _state.Activity = BusOperation.None;
                _state.T++;
                return;
            case HaltFetch + 3:
                _state.Activity = BusOperation.None;
                _state.Cycle = Z80MachineCycle.None;
                _state.T = 0;
                return;
            case Fetch + 3:
            case NonMaskableFetch + 4:
            case Acknowledge + 5:
            case Read + 2:
            case Write + 2:
            case InputRead + 3:
            case OutputWrite + 3:
                EndCycle();
                return;
            default:
                // An internal cycle holds the bus for its length; one of none still takes a T-state.
                _state.Activity = BusOperation.None;
                if (_state.T + 1 < _state.Length)
                {
                    _state.T++;
                    return;
                }

                EndCycle();
                return;
        }
    }

    // A wait state repeats the access T-state without advancing it.
    private bool Stalled()
    {
        if ((_state.Signals & Z80Signals.Wait) == 0) { return false; }
        _state.Activity = StalledActivity;
        return true;
    }

    // The machine cycle's last T-state: the instruction takes its result and chooses what follows.
    private void EndCycle()
    {
        _state.Activity = BusOperation.None;
        _state.Cycle = Z80MachineCycle.None;
        _state.T = 0;
        Continue();
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void Refresh()
    {
        ref Z80Registers registers = ref _state.Registers;
        _state.Bus = (ushort)((registers.I << 8) | registers.R);
        registers.R = (byte)((registers.R & 0x80) | ((registers.R + 1) & 0x7F));
        _state.Activity = BusOperation.Refresh;
    }
}
