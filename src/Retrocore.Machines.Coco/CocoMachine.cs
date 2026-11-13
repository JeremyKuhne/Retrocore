// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6809;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Coco;

/// <summary>
///  A TRS-80 Color Computer: an MC6809E stepped one bus cycle at a time with its bus, video and keyboard.
/// </summary>
/// <remarks>
///  <para>
///   Each CPU cycle takes one or two time units, as the SAM's rate and the address decide, and the video and
///   keyboard advance by them. PIA 0's interrupt outputs drive IRQ and PIA 1's drive FIRQ; a disk controller
///   drives NMI and HALT.
///  </para>
/// </remarks>
public sealed class CocoMachine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<CocoMemoryArea>();

    /// <summary>
    ///  Builds a Color Computer and starts its reset sequence.
    /// </summary>
    /// <param name="configuration">The model, RAM and video chip.</param>
    /// <param name="roms">The ROMs, which must suit the model.</param>
    /// <param name="diskController">The disk controller cartridge, or null for none.</param>
    /// <exception cref="ArgumentException">
    ///  The configuration does not fit the model, or the ROMs do not suit it.
    /// </exception>
    public CocoMachine(CocoConfiguration configuration, CocoRoms roms, CocoDiskController? diskController = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        if (roms.IsCoco3 != (configuration.Model == CocoModel.Coco3))
        {
            throw new ArgumentException("The ROMs are not this model's.", nameof(roms));
        }

        Configuration = configuration;
        Bus = new(configuration, roms) { DiskController = diskController };
        Processor = new(Bus);
        Processor.Reset();
        Cassette = new(Bus);
        Devices = diskController is null ? [Cassette] : [Cassette, .. diskController.Drives];
    }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public CocoConfiguration Configuration { get; }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public CocoModel Model => Configuration.Model;

    /// <summary>
    ///  Gets the bus.
    /// </summary>
    public CocoBus Bus { get; }

    /// <summary>
    ///  Gets the CPU.
    /// </summary>
    public M6809Processor<CocoBus> Processor { get; }

    /// <summary>
    ///  Gets the cassette recorder.
    /// </summary>
    public CocoCassetteDrive Cassette { get; }

    /// <summary>
    ///  Gets the devices: the cassette recorder and any disk drives.
    /// </summary>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the CPU's bus activity in the last cycle.
    /// </summary>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Advances one CPU cycle, then the video and keyboard by its time.
    /// </summary>
    public void StepCycle()
    {
        UpdateSignals();
        Processor.StepCycle();
        Bus.Tick(Bus.CycleUnits(Processor.LastCycle));
        Bus.AfterCycle();

        // The lines as the cycle left them, so that the processor's halted state is current between cycles.
        UpdateSignals();
    }

    /// <summary>
    ///  Presses RESET: the SAM, PIAs and CPU restart; RAM is kept, so Color BASIC warm starts.
    /// </summary>
    public void Reset()
    {
        Bus.Reset();
        Processor.Reset();
    }

    /// <summary>
    ///  Runs a number of CPU cycles.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <summary>
    ///  Runs until the current or next instruction completes.
    /// </summary>
    /// <param name="maximumCycles">The most cycles to run.</param>
    /// <returns>The status and cycles run.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        bool started = !Processor.IsInstructionBoundary;
        for (int index = 0; index < maximumCycles; index++)
        {
            StepCycle();
            started |= Processor.FetchedOpcode || !Processor.IsInstructionBoundary;
            if (started && Processor.IsInstructionBoundary)
            {
                return new()
                {
                    Status = Processor.IsWaiting ? ProcessorExecutionStatus.Waiting : ProcessorExecutionStatus.InstructionComplete,
                    Cycles = Processor.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = Processor.CycleCount - start };
    }

    // The bus drives IRQ, FIRQ, NMI and HALT; RESET is the processor's own.
    private void UpdateSignals()
    {
        const M6809Signals Driven = M6809Signals.InterruptRequest
            | M6809Signals.FastInterruptRequest
            | M6809Signals.NonMaskableInterrupt
            | M6809Signals.Halt;

        M6809Signals signals = Processor.Signals & ~Driven;
        if (Bus.InterruptRequested) { signals |= M6809Signals.InterruptRequest; }
        if (Bus.FastInterruptRequested) { signals |= M6809Signals.FastInterruptRequest; }
        if (Bus.DiskController is { } disk)
        {
            if (disk.NonMaskableInterrupt) { signals |= M6809Signals.NonMaskableInterrupt; }
            if (disk.Halt) { signals |= M6809Signals.Halt; }
        }

        Processor.Signals = signals;
    }

    string IMachine.Id => "coco";

    ICpuDebugView IMachine.Cpu => Processor;

    IVideoSource IMachine.Video => Bus.VideoOutput;

    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
