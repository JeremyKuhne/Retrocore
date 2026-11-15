// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.I8080;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Altair;

/// <summary>
///  A MITS Altair 8800: the 8080 at 2 MHz, RAM, the 88-2SIO serial board with a terminal, and the front panel.
/// </summary>
/// <remarks>
///  <para>
///   The Altair has no ROM: at power-on and RESET the 8080 starts at address 0, in whatever RAM holds, and programs
///   arrive through the front panel, the serial port or a loader. The 88-2SIO's interrupt requests drive the 8080's
///   INT line; with no vectored interrupt board, the acknowledge reads $FF, which is <c>RST 7</c>.
///  </para>
/// </remarks>
public sealed class AltairMachine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<AltairMemoryArea>();

    /// <summary>
    ///  Builds a machine.
    /// </summary>
    /// <param name="configuration">Its boards and switches.</param>
    public AltairMachine(AltairConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        configuration.Validate();
        Configuration = configuration;
        Bus = new(configuration);
        Processor = new(Bus, I8080Variant.I8080);
    }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public AltairConfiguration Configuration { get; }

    /// <summary>
    ///  Gets the bus.
    /// </summary>
    public AltairBus Bus { get; }

    /// <summary>
    ///  Gets the 8080.
    /// </summary>
    public I8080Processor<AltairBus> Processor { get; }

    /// <summary>
    ///  Gets the terminal.
    /// </summary>
    public AltairTerminal Terminal => Bus.Terminal;

    /// <summary>
    ///  Gets the front panel.
    /// </summary>
    public AltairFrontPanel FrontPanel => Bus.FrontPanel;

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => Bus.Cassette is { } cassette ? [cassette] : [];

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  RESET, as the front panel's switch: the 8080 restarts at 0 and the 88-2SIO's ACIAs master reset. RAM keeps its
    ///  contents.
    /// </summary>
    public void Reset()
    {
        Bus.Reset();
        Processor.Reset();
    }

    /// <inheritdoc/>
    public void StepCycle()
    {
        Processor.StepCycle();
        Bus.Tick();
        bool interrupt = Bus.Interrupt;
        if (interrupt != ((Processor.Signals & I8080Signals.InterruptRequest) != 0))
        {
            Processor.Signals = interrupt
                ? Processor.Signals | I8080Signals.InterruptRequest
                : Processor.Signals & ~I8080Signals.InterruptRequest;
        }
    }

    /// <summary>
    ///  Runs a number of CPU cycles.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <inheritdoc/>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        for (int index = 0; index < maximumCycles; index++)
        {
            if (Processor.IsHalted && Processor.IsInstructionBoundary && !Bus.Interrupt)
            {
                return new() { Status = ProcessorExecutionStatus.Waiting, Cycles = Processor.CycleCount - start };
            }

            StepCycle();
            if (Processor.IsInstructionBoundary)
            {
                return new()
                {
                    Status = ProcessorExecutionStatus.InstructionComplete,
                    Cycles = Processor.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = Processor.CycleCount - start };
    }

    string IMachine.Id => "altair";

    ICpuDebugView IMachine.Cpu => Processor;

    IVideoSource IMachine.Video => Bus.Terminal;

    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    void IMachine.QueueKey(byte code) => Bus.Terminal.Type(code);
}
