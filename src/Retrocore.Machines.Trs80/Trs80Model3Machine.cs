// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  A caller-clocked TRS-80 Model III, 4 or 4P, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   Each <see cref="StepCycle"/> is one Z80 T-state. The devices run at the Model III's 2.03 MHz, so a Model 4
///   at 4 MHz advances them every other T-state.
///  </para>
/// </remarks>
public sealed class Trs80Model3Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Trs80Model3MemoryArea>();

    // T-states the reset button holds NMI low: long enough for the Z80 to see the edge.
    private const int ResetPressCycles = 4;
    private int _resetHeld;
    private bool _halfCycle;

    /// <summary>
    ///  The Z80's non-maskable interrupt handler, where the reset button and disk interrupts send it.
    /// </summary>
    public const ushort NmiHandler = 0x0066;

    /// <summary>
    ///  Constructs a machine and resets it.
    /// </summary>
    /// <param name="configuration">The machine and its options.</param>
    /// <param name="roms">The caller-supplied ROM and character generator.</param>
    /// <exception cref="ArgumentException">The configuration is invalid, or the ROM does not match it.</exception>
    public Trs80Model3Machine(Trs80Model3Configuration configuration, Trs80Model3Roms roms)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        int expected = configuration.Variant == Trs80Model3Variant.Model4P ? Trs80Model3Roms.BootSize : Trs80Model3Roms.SystemSize;
        if (roms.System.Length != expected)
        {
            throw new ArgumentException(
                configuration.Variant == Trs80Model3Variant.Model4P
                    ? "A Model 4P's boot ROM is 4K."
                    : "The Model III ROM is 14K.",
                nameof(roms));
        }

        Configuration = configuration;
        Bus = new(configuration, roms);
        Processor = new(Bus);
        List<IDevice> devices = [];
        if (configuration.Variant != Trs80Model3Variant.Model4P)
        {
            Cassette = new(Bus.Cassette, 500, "$EC");
            devices.Add(Cassette);
        }

        List<Trs80FloppyDrive> drives = [];
        for (int drive = 0; Bus.HasDiskController && drive < Trs80DiskController.DriveCount; drive++)
        {
            drives.Add(new(Bus.Disks, drive, DriveInfo(drive)));
        }

        Drives = drives;
        devices.AddRange(drives);
        Devices = devices;
    }

    private static DeviceInfo DriveInfo(int drive) => new()
    {
        Name = $"Drive {drive}",
        Description = "5¼-inch floppy drive",
        Controller = "FD1793, selected at port $F4",
        Formats = ["dsk", "jv1", "jv3", "dmk", "imd"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect,
        Tracks = 40,
        Sides = 2
    };

    /// <summary>
    ///  Gets the cassette recorder, or null on a Model 4P, which has none.
    /// </summary>
    public Trs80CassetteDrive? Cassette { get; }

    /// <summary>
    ///  Gets the floppy drives, or none without the disk controller.
    /// </summary>
    public IReadOnlyList<Trs80FloppyDrive> Drives { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public Trs80Model3Configuration Configuration { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Trs80Model3Bus Bus { get; }

    /// <summary>
    ///  Gets the Z80.
    /// </summary>
    public Z80Processor<Trs80Model3Bus> Processor { get; }

    /// <summary>
    ///  Gets the Z80's clock now: the Model III's 2.03 MHz, or 4.06 MHz when a Model 4 selects it.
    /// </summary>
    public int ClockHertz => Bus.Fast ? Trs80Model3Timing.FastClockHertz : Trs80Model3Timing.ClockHertz;

    /// <summary>
    ///  Advances the machine one T-state; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        Z80Signals signals = Processor.Signals
            & ~(Z80Signals.InterruptRequest | Z80Signals.NonMaskableInterrupt | Z80Signals.Wait);

        if (Bus.InterruptRequested) { signals |= Z80Signals.InterruptRequest; }
        if (Bus.WaitRequested) { signals |= Z80Signals.Wait; }
        if (_resetHeld > 0)
        {
            _resetHeld--;
            signals |= Z80Signals.NonMaskableInterrupt;
        }
        else if (Bus.NmiRequested)
        {
            signals |= Z80Signals.NonMaskableInterrupt;
        }

        Processor.Signals = signals;
        Processor.StepCycle();

        // At 4 MHz the devices, which count 2 MHz T-states, advance every other T-state.
        if (Bus.Fast && (_halfCycle = !_halfCycle)) { return; }
        Bus.Tick();
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Presses the reset button, which raises the Z80's non-maskable interrupt with port <c>$E4</c> bit 5 showing
    ///  why, so the ROM restarts.
    /// </summary>
    public void Reset()
    {
        // The NMI line goes low only if it was high; a held disk NMI already masks the edge, as on the machine.
        Bus.PressReset();
        _resetHeld = ResetPressCycles;
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
            if (Processor.IsHalted && Processor.IsInstructionBoundary && !Bus.InterruptRequested && !Bus.NmiRequested)
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

    /// <summary>
    ///  Gets the machine's launch identifier.
    /// </summary>
    public string Id => Configuration.Variant switch
    {
        Trs80Model3Variant.Model3 => "trs80-model3",
        _ => "trs80-model4"
    };

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
