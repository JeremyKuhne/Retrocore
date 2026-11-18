// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A caller-clocked Commodore PET 2001, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   A NMOS 6502 at 1 MHz, the two 6520 PIAs and the 6522 VIA. The machine powers on at the start of vertical
///   blanking; <see cref="PetTiming"/> gives the frame.
///  </para>
/// </remarks>
public sealed class PetMachine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<PetMemoryArea>();

    private Cbm4040[] _disks;
    private bool _irq;

    /// <summary>
    ///  Constructs a machine at power-on.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="model">The model.</param>
    /// <param name="ramKilobytes">4, 8, 16 or 32.</param>
    /// <param name="diskRoms">A 4040's or 2040's ROMs, for disk units on the IEEE-488 bus; null for none.</param>
    /// <param name="diskAddresses">The units' device numbers, 8-15; with ROMs and none given, one unit as 8.</param>
    public PetMachine(
        PetRoms roms,
        PetModel model = PetModel.Pet2001Basic2,
        int ramKilobytes = 8,
        Cbm4040Roms? diskRoms = null,
        IReadOnlyList<int>? diskAddresses = null)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Model = model;
        Bus = new(roms, model, ramKilobytes);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        Processor.Reset();

        _disks = [];
        Devices = [Bus.Cassette1, Bus.Cassette2];
        if (diskRoms is null) { return; }
        foreach (int address in diskAddresses ?? [8]) { AddDisk(diskRoms, address); }
    }

    /// <summary>
    ///  Gets the disk units on the IEEE-488 bus, by device number.
    /// </summary>
    public IReadOnlyList<Cbm4040> Disks => _disks;

    /// <summary>
    ///  Connects a 4040 or 2040, as its ROMs say, to the IEEE-488 bus, at power-on, as plugging one in and switching
    ///  it on does.
    /// </summary>
    /// <param name="roms">The drive's ROMs.</param>
    /// <param name="address">Its device number, 8-15.</param>
    /// <returns>The unit.</returns>
    /// <exception cref="ArgumentException">A unit already has the number.</exception>
    public Cbm4040 AddDisk(Cbm4040Roms roms, int address)
    {
        if (_disks.Any(unit => unit.Address == address))
        {
            throw new ArgumentException($"Device {address} is already on the bus.", nameof(address));
        }

        Cbm4040 added = new(roms, Bus.Ieee, address);
        _disks = [.. _disks.Append(added).OrderBy(unit => unit.Address)];
        UpdateDevices();
        return added;
    }

    /// <summary>
    ///  Takes a disk unit off the IEEE-488 bus, with any disks in it.
    /// </summary>
    /// <param name="address">Its device number.</param>
    /// <returns>Whether there was one.</returns>
    public bool RemoveDisk(int address)
    {
        if (_disks.FirstOrDefault(unit => unit.Address == address) is not { } unit) { return false; }
        Bus.Ieee.Detach(unit.Port);
        _disks = [.. _disks.Where(other => other != unit)];
        UpdateDevices();
        return true;
    }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public PetModel Model { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public PetBus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<PetBus> Processor { get; }

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public PetVideo Video => Bus.Video;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public PetKeyboard Keyboard => Bus.Keyboard;

    /// <summary>
    ///  Gets the sound.
    /// </summary>
    public PetAudio Audio => Bus.Audio;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The Datasettes on cassette ports 1 and 2, then each disk unit's drives 0 and 1.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<IDevice> Devices { get; private set; }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Resets the 6502, the PIAs and the VIA, keeping RAM. The PET has no RESET key; this is power cycling without
    ///  losing memory, as a reset button wired to the expansion port does.
    /// </summary>
    public void Reset()
    {
        Bus.ResetDevices();
        Processor.Reset();

        // The reset line pulls IFC, which resets the devices on the bus.
        foreach (Cbm4040 unit in _disks) { unit.Reset(); }
    }

    private void UpdateDevices() =>
        Devices = [Bus.Cassette1, Bus.Cassette2, .. _disks.SelectMany(unit => (IDevice[])[unit.Drive0, unit.Drive1])];

    /// <summary>
    ///  Advances the CPU and the devices one cycle; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        bool irq = Bus.InterruptRequested;
        if (irq != _irq)
        {
            Processor.Signals = irq
                ? Processor.Signals | ProcessorSignals.InterruptRequest
                : Processor.Signals & ~ProcessorSignals.InterruptRequest;

            _irq = irq;
        }

        Processor.StepCycle();
        Bus.Tick();
        foreach (Cbm4040 unit in _disks) { unit.StepCycle(); }
    }

    /// <summary>
    ///  Runs an exact number of cycles.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <summary>
    ///  Runs for a span of emulated time.
    /// </summary>
    /// <param name="duration">The time to run.</param>
    public void Run(TimeSpan duration) => Run((ulong)(duration.Ticks / (TimeSpan.TicksPerSecond / PetTiming.CpuHertz)));

    /// <summary>
    ///  Finishes the current instruction, or runs one, within a cycle limit.
    /// </summary>
    /// <param name="maximumCycles">The most cycles to run.</param>
    /// <returns>Why it stopped and the cycles it ran.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        bool instruction = Processor.CurrentOpCode is not null;
        for (int index = 0; index < maximumCycles; index++)
        {
            StepCycle();
            instruction |= Processor.FetchedOpcode;
            if (Processor.Status != ProcessorExecutionStatus.Running)
            {
                return new() { Status = Processor.Status, Cycles = Processor.CycleCount - start };
            }

            if (instruction && Processor.IsInstructionBoundary)
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
    ///  Reads the screen as text.
    /// </summary>
    /// <returns>25 lines of 40 characters; see <see cref="PetVideo.ReadText"/>.</returns>
    public string[] ReadTextScreen() => Video.ReadText();

    /// <inheritdoc/>
    string IMachine.Id => "pet";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Video;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
