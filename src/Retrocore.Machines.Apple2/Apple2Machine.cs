// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A caller-clocked original or enhanced 128 KiB IIe, independent of UI and debugger protocols.
/// </summary>
public sealed class Apple2Machine : IMachine
{

    private static readonly string[] s_memoryAreas = Enum.GetNames<Apple2MemoryArea>();
    private bool _deviceIrq;

    // Each Disk II card's drives, made the first time the card is listed, kept while it stays in.
    private readonly Dictionary<DiskIIController, Apple2FloppyDrive[]> _slotDrives = [];
    private IDevice[]? _devices;
    private (int Changes, bool Slot6) _devicesKey;

    /// <summary>
    ///  Constructs a machine.
    /// </summary>
    /// <param name="model">The processor and ROM configuration.</param>
    /// <param name="roms">Caller-supplied firmware.</param>
    /// <param name="disk">An optional slot-seven block device.</param>
    public Apple2Machine(Apple2Model model, Apple2Roms roms, IBlockDevice? disk = null)
    {
        if (!Enum.IsDefined(model))
        {
            throw new ArgumentOutOfRangeException(nameof(model));
        }

        Model = model;
        Bus = new Apple2Bus(model, roms, disk);
        Processor = new(Bus, model.Processor());
        Processor.Reset();
        Drives = [new(Bus.DiskII, drive: 1), new(Bus.DiskII, drive: 2)];
        _slotDrives[Bus.DiskII] = [.. Drives];
        BlockStorage = disk is null ? null : new(Bus);
    }

    /// <summary>
    ///  Gets the drives on a slot's Disk II card.
    /// </summary>
    /// <param name="slot">The slot, 1 to 7.</param>
    /// <returns>Drives 1 and 2, or none when the slot has no Disk II card.</returns>
    public IReadOnlyList<Apple2FloppyDrive> DrivesIn(int slot)
    {
        if (Bus.DiskIIIn(slot) is not { } card) { return []; }
        if (!_slotDrives.TryGetValue(card, out Apple2FloppyDrive[]? drives))
        {
            drives = [new(card, drive: 1, slot), new(card, drive: 2, slot)];
            _slotDrives[card] = drives;
        }

        return drives;
    }

    /// <summary>
    ///  Presses CONTROL-RESET: the soft switches and devices reset and the processor takes its reset vector; RAM,
    ///  media and the keyboard are kept, so the firmware can tell a warm reset from a cold one.
    /// </summary>
    public void Reset()
    {
        Bus.ResetDevices();
        Bus.ResetSwitches();
        Processor.Reset();
    }

    /// <summary>
    ///  Gets the Disk II card's drives, which are installed once the card's firmware is.
    /// </summary>
    public IReadOnlyList<Apple2FloppyDrive> Drives { get; }

    /// <summary>
    ///  Gets the slot 7 block device, or null when slot 7 is empty.
    /// </summary>
    public Apple2BlockStorage? BlockStorage { get; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The drives of each slot's Disk II card in slot order, then slot seven's block storage. The list is made again
    ///   only when a card goes in or comes out.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<IDevice> Devices
    {
        get
        {
            (int, bool) key = (Bus.CardChanges, Bus.DiskII.IsInstalled);
            if (_devices is null || key != _devicesKey)
            {
                List<IDevice> devices = [];
                for (int slot = 1; slot <= 7; slot++) { devices.AddRange(DrivesIn(slot)); }
                if (BlockStorage is not null) { devices.Add(BlockStorage); }
                _devices = [.. devices];
                _devicesKey = key;
            }

            return _devices;
        }
    }

    /// <summary>
    ///  Gets the selected machine configuration.
    /// </summary>
    public Apple2Model Model { get; }

    /// <summary>
    ///  Gets the IIe memory and devices.
    /// </summary>
    public Apple2Bus Bus { get; }

    /// <summary>
    ///  Gets the machine-independent CPU.
    /// </summary>
    public Processor<Apple2Bus> Processor { get; }

    /// <summary>
    ///  Gets or sets an external IRQ source ORed with the Mockingboard's interrupt output.
    ///  Use this input rather than changing the CPU IRQ bit while a device owns that bit.
    /// </summary>
    public bool ExternalIrq { get; set; }

    /// <summary>
    ///  Advances the CPU and machine devices by one cycle.
    /// </summary>
    public void StepCycle()
    {
        bool irq = ExternalIrq || Bus.Mockingboard.InterruptRequested;
        if (irq || _deviceIrq)
        {
            Processor.Signals = (Processor.Signals & ~ProcessorSignals.InterruptRequest)
                | (irq ? ProcessorSignals.InterruptRequest : ProcessorSignals.None);
        }

        _deviceIrq = irq;
        Bus.Video.ScanCycle();
        Processor.StepCycle();
        Bus.Tick();
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Executes an exact cycle budget.
    /// </summary>
    /// <param name="cycles">The cycle budget.</param>
    public void Run(ulong cycles)
    {
        for (ulong i = 0; i < cycles; i++) { StepCycle(); }
    }

    /// <summary>
    ///  Completes an instruction within an explicit cycle budget.
    /// </summary>
    /// <param name="maximumCycles">The maximum number of cycles.</param>
    /// <returns>The execution result.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        bool instruction = Processor.CurrentOpCode is not null;
        for (int i = 0; i < maximumCycles; i++)
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
                    Status = ProcessorExecutionStatus.InstructionComplete, Cycles = Processor.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = Processor.CycleCount - start };
    }

    /// <inheritdoc/>
    string IMachine.Id => "apple2";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Bus.Video;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.ReadArea(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.QueueKey(code);
}
