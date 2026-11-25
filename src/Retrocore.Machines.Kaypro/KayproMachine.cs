// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II (1982): a 2.5 MHz Z80 with 64K of RAM, a 2K monitor ROM, an 80 by 24 text screen, a serial
///  keyboard and two single-sided double-density 5¼-inch drives, running CP/M 2.2.
/// </summary>
/// <remarks>
///  <para>
///   Each <see cref="StepCycle"/> is one T-state. The FD1793 raises the NMI while the Z80 is halted and the controller
///   wants a byte or has finished, which is how the ROM moves each byte with <c>HALT</c> then <c>INI</c>.
///  </para>
/// </remarks>
public sealed class KayproMachine : IMachine
{
    /// <summary>
    ///  The drives.
    /// </summary>
    public const int DriveCount = 2;

    private static readonly string[] s_memoryAreas = Enum.GetNames<KayproMemoryArea>();

    private IZ80DaisyDevice? _requester;
    private bool _afterEd;

    /// <summary>
    ///  Creates the machine with its ROMs.
    /// </summary>
    /// <param name="roms">The monitor ROM and character generator.</param>
    public KayproMachine(KayproRoms roms)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Bus = new(roms);
        Processor = new(Bus);
        List<FloppyDrive> drives = [];
        for (int drive = 0; drive < DriveCount; drive++)
        {
            drives.Add(new(Bus.Disks, drive, DriveInfo(drive)));
        }

        Drives = drives;
        Devices = [.. drives];
    }

    private static DeviceInfo DriveInfo(int drive) => new()
    {
        Name = $"Drive {(char)('A' + drive)}",
        Description = "5¼-inch single-sided double-density floppy drive, built in",
        Controller = "FD1793, selected by the system port's bits 0 and 1",
        Formats = ["img", "dsk", "imd", "dmk"],
        SaveFormats = ["img", "imd", "dmk"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
        Tracks = 40,
        Sides = 1
    };

    /// <summary>
    ///  Gets the drives, A and B.
    /// </summary>
    public IReadOnlyList<FloppyDrive> Drives { get; }

    /// <summary>
    ///  Gets the devices that take media.
    /// </summary>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the memory and I/O.
    /// </summary>
    public KayproBus Bus { get; }

    /// <summary>
    ///  Gets the Z80.
    /// </summary>
    public Z80Processor<KayproBus> Processor { get; }

    /// <summary>
    ///  Gets whether a device on the daisy chain asks for an interrupt.
    /// </summary>
    public bool InterruptRequested => Requester() is not null;

    /// <summary>
    ///  Gets whether the NMI is asserted: the Z80 halted while the disk controller asks.
    /// </summary>
    public bool NmiRequested => Processor.IsHalted && Bus.DiskRequest;

    /// <summary>
    ///  Runs one T-state.
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

        if (NmiRequested) { signals |= Z80Signals.NonMaskableInterrupt; }
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

    /// <summary>
    ///  Gets the last T-state.
    /// </summary>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Resets the Z80 and banks the ROM in, as the reset button does.
    /// </summary>
    public void Reset()
    {
        Processor.Reset();
        Bus.Reset();
        _afterEd = false;
    }

    /// <summary>
    ///  Runs T-states.
    /// </summary>
    /// <param name="cycles">The T-states.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <summary>
    ///  Runs to the end of the instruction, or until the halted Z80 waits for an interrupt.
    /// </summary>
    /// <param name="maximumCycles">The most T-states to run.</param>
    /// <returns>What happened.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 64)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        for (int index = 0; index < maximumCycles; index++)
        {
            if (Processor.IsHalted && Processor.IsInstructionBoundary && !InterruptRequested && !Bus.DiskRequest)
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

    string IMachine.Id => "kaypro2";

    ICpuDebugView IMachine.Cpu => Processor;

    IVideoSource IMachine.Video => Bus.Video;

    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
