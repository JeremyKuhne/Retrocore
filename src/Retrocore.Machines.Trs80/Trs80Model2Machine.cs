// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80.Chips;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  A caller-clocked TRS-80 Model II, 12 or 16 (its Z80 side), independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   The Z80 runs at 4 MHz. Its peripherals interrupt in mode 2 through the daisy chain: the device that requests
///   puts its vector on the bus when the Z80 acknowledges, and holds off the devices after it until the routine
///   returns with <c>RETI</c>, which the machine sees in the opcodes the Z80 fetches.
///  </para>
/// </remarks>
public sealed class Trs80Model2Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Trs80Model2MemoryArea>();

    private IZ80DaisyDevice? _requester;
    private bool _afterEd;

    /// <summary>
    ///  Constructs a machine and resets it.
    /// </summary>
    /// <param name="configuration">The machine and its options.</param>
    /// <param name="roms">The caller-supplied boot ROM and character generator.</param>
    /// <exception cref="ArgumentException">The configuration is invalid.</exception>
    public Trs80Model2Machine(Trs80Model2Configuration configuration, Trs80Model2Roms roms)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        Configuration = configuration;
        Bus = new(configuration, roms);
        Processor = new(Bus);
        List<Trs80FloppyDrive> drives = [];
        for (int drive = 0; drive < Trs80DiskController.DriveCount; drive++)
        {
            drives.Add(new(Bus.Disks, drive, DriveInfo(drive, configuration.Variant)));
        }

        Drives = drives;
        Devices = [.. drives];
    }

    private static DeviceInfo DriveInfo(int drive, Trs80Model2Variant variant) => new()
    {
        Name = $"Drive {drive}",
        Description = variant == Trs80Model2Variant.Model2 && drive == 0
            ? "8-inch floppy drive, built in"
            : "8-inch floppy drive",
        Controller = "FD1791 with the Z80 DMA, selected at port $EF",
        Formats = ["imd", "dmk", "jv3", "dsk"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect,
        Tracks = 77,
        Sides = 2
    };

    /// <summary>
    ///  Gets the floppy drives.
    /// </summary>
    public IReadOnlyList<Trs80FloppyDrive> Drives { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public Trs80Model2Configuration Configuration { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Trs80Model2Bus Bus { get; }

    /// <summary>
    ///  Gets the Z80.
    /// </summary>
    public Z80Processor<Trs80Model2Bus> Processor { get; }

    /// <summary>
    ///  Gets whether a device on the daisy chain requests an interrupt.
    /// </summary>
    public bool InterruptRequested => Requester() is not null;

    /// <summary>
    ///  Advances the machine one T-state; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        Z80Signals signals = Processor.Signals & ~(Z80Signals.InterruptRequest | Z80Signals.NonMaskableInterrupt);
        _requester = Requester();
        if (_requester?.PendingVector is { } vector)
        {
            signals |= Z80Signals.InterruptRequest;
            Processor.InterruptData = vector;
        }

        if (Bus.NmiRequested) { signals |= Z80Signals.NonMaskableInterrupt; }
        Processor.Signals = signals;
        Processor.StepCycle();

        ProcessorCycle cycle = Processor.LastCycle;
        if (cycle.Operation == BusOperation.InterruptAcknowledge)
        {
            _requester?.Acknowledge();
        }
        else if (cycle.IsOpcodeFetch && cycle.Operation == BusOperation.Read)
        {
            // RETI is ED 4D; the devices watch for it to end the service of the highest-priority interrupt.
            if (_afterEd && cycle.Value == 0x4D) { ReturnFromInterrupt(); }
            _afterEd = cycle.Value == 0xED;
        }

        Bus.Tick();
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Presses the reset switch, which resets the Z80 and switches the boot ROM in.
    /// </summary>
    public void Reset()
    {
        Processor.Reset();
        Bus.Reset();
        _afterEd = false;
    }

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
            if (Processor.IsHalted && Processor.IsInstructionBoundary && !InterruptRequested && !Bus.NmiRequested)
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

    // The first device on the chain that requests, unless one before it is being serviced.
    private IZ80DaisyDevice? Requester()
    {
        foreach (IZ80DaisyDevice device in Bus.DaisyChain)
        {
            if (device.PendingVector is not null) { return device; }
            if (device.InService) { return null; }
        }

        return null;
    }

    private void ReturnFromInterrupt()
    {
        foreach (IZ80DaisyDevice device in Bus.DaisyChain)
        {
            if (device.InService)
            {
                device.ReturnFromInterrupt();
                return;
            }
        }
    }

    /// <inheritdoc/>
    string IMachine.Id => "trs80-model2";

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
