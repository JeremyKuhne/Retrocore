// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  A caller-clocked TRS-80 Model I, independent of UI and debugger protocols.
/// </summary>
public sealed class Trs80Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Trs80MemoryArea>();

    // T-states the reset button holds NMI low: long enough for the Z80 to see the edge.
    private const int ResetPressCycles = 4;
    private int _resetHeld;

    /// <summary>
    ///  The Z80's non-maskable interrupt handler, where the reset button sends it.
    /// </summary>
    public const ushort ResetHandler = 0x0066;

    /// <summary>
    ///  Constructs a machine and resets it.
    /// </summary>
    /// <param name="configuration">The ROM, memory and options.</param>
    /// <param name="roms">Caller-supplied BASIC and character generator.</param>
    /// <exception cref="ArgumentException">The configuration is invalid, or BASIC does not match it.</exception>
    public Trs80Machine(Trs80Configuration configuration, Trs80Roms roms)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        int expected = configuration.Rom == Trs80Rom.Level1 ? 0x1000 : 0x3000;
        if (roms.System.Length != expected)
        {
            throw new ArgumentException("BASIC's size does not match the configured ROM.", nameof(roms));
        }

        Configuration = configuration;
        Bus = new(configuration, roms);
        Processor = new(Bus);
        Cassette = new(Bus.Cassette, configuration.Rom == Trs80Rom.Level1 ? 250 : 500);
        List<Trs80FloppyDrive> drives = [];
        for (int drive = 0; Bus.HasDiskController && drive < Trs80DiskController.DriveCount; drive++)
        {
            drives.Add(new(Bus.Disks, drive, configuration.Doubler));
        }

        Drives = drives;

        Devices = [Cassette, .. Drives];
    }

    /// <summary>
    ///  Gets the cassette recorder.
    /// </summary>
    public Trs80CassetteDrive Cassette { get; }

    /// <summary>
    ///  Gets the floppy drives, or none without the disk controller.
    /// </summary>
    public IReadOnlyList<Trs80FloppyDrive> Drives { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public Trs80Configuration Configuration { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Trs80Bus Bus { get; }

    /// <summary>
    ///  Gets the Z80.
    /// </summary>
    public Z80Processor<Trs80Bus> Processor { get; }

    /// <summary>
    ///  Advances the machine one T-state; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        Z80Signals signals = Processor.Signals & ~(Z80Signals.InterruptRequest | Z80Signals.NonMaskableInterrupt);
        if (Bus.InterruptRequested) { signals |= Z80Signals.InterruptRequest; }
        if (_resetHeld > 0)
        {
            _resetHeld--;
            signals |= Z80Signals.NonMaskableInterrupt;
        }

        Processor.Signals = signals;

        Processor.StepCycle();
        Bus.Tick();
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Presses the reset button, which raises the Z80's non-maskable interrupt rather than its RESET line. The
    ///  Level II ROM's handler at <see cref="ResetHandler"/> boots a disk when the Expansion Interface's controller
    ///  answers, and otherwise restarts BASIC, keeping the program in memory.
    /// </summary>
    public void Reset() => _resetHeld = ResetPressCycles;

    /// <summary>
    ///  Runs an exact number of T-states.
    /// </summary>
    /// <param name="cycles">The T-states.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <summary>
    ///  Finishes the current instruction, or runs one, within a T-state limit.
    /// </summary>
    /// <param name="maximumCycles">The most T-states to run.</param>
    /// <returns>Why it stopped and the T-states it ran.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        for (int index = 0; index < maximumCycles; index++)
        {
            if (Processor.IsHalted && Processor.IsInstructionBoundary && !Bus.InterruptRequested)
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

    /// <inheritdoc/>
    string IMachine.Id => "trs80-model1";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Bus.Video;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
