// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  A caller-clocked Apple-1, independent of UI and debugger protocols.
/// </summary>
public sealed class Apple1Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Apple1MemoryArea>();

    /// <summary>
    ///  Constructs a machine and resets it.
    /// </summary>
    /// <param name="configuration">The memory and cards.</param>
    /// <param name="roms">Caller-supplied firmware.</param>
    /// <exception cref="ArgumentException">
    ///  The configuration is invalid, or it has the cassette interface and the ROMs have no PROM for it.
    /// </exception>
    public Apple1Machine(Apple1Configuration configuration, Apple1Roms roms)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        if (configuration.CassetteInterface && roms.Cassette.IsEmpty)
        {
            throw new ArgumentException("The cassette interface needs its PROM.", nameof(roms));
        }

        Configuration = configuration;
        Bus = new(configuration, roms);
        Processor = new(Bus);
        Processor.Reset();
        CassetteDrive = Bus.Cassette is { } cassette ? new(cassette) : null;
        Devices = CassetteDrive is null ? [] : [CassetteDrive];
    }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public Apple1Configuration Configuration { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Apple1Bus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<Apple1Bus> Processor { get; }

    /// <summary>
    ///  Gets the cassette recorder, or null without the cassette interface.
    /// </summary>
    public Apple1CassetteDrive? CassetteDrive { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Gets the terminal.
    /// </summary>
    public Apple1Terminal Terminal => Bus.Terminal;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Apple1Keyboard Keyboard => Bus.Keyboard;

    /// <summary>
    ///  Presses RESET, which resets the 6502 and the PIA; RAM and the screen are kept.
    /// </summary>
    public void Reset()
    {
        Bus.Pia.Reset();
        Bus.Terminal.Reset();
        Processor.Reset();
    }

    /// <summary>
    ///  Presses CLEAR SCREEN.
    /// </summary>
    public void ClearScreen() => Bus.Terminal.ClearScreen();

    /// <summary>
    ///  Advances the CPU and the devices one cycle; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        Processor.StepCycle();
        Bus.Tick();
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Runs an exact number of cycles.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

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

    /// <inheritdoc/>
    string IMachine.Id => "apple1";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Bus.Terminal;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
