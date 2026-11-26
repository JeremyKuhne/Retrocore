// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.I8080;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  A TRS-80 Model 100 or Tandy 102: the OKI 80C85 at 2.4576 MHz, 32 KB of ROM and an option ROM socket, 8 to 32 KB
///  of RAM, the 81C55, the 240x64 LCD, the keyboard and the uPD1990AC clock.
/// </summary>
/// <remarks>
///  <para>
///   The clock's TP output, which the ROM sets to 256 Hz, drives RST 7.5; the ROM's handler scans the keyboard,
///   blinks the cursor and counts down to the automatic power-off. TRAP (power failing), RST 6.5 (the UART) and
///   RST 5.5 (the bar-code wand) are not driven yet, and SID, the cassette's input, reads high, as MAME's does with no
///   tape. The battery never runs low.
///  </para>
///  <para>
///   Software turns the power off with port B bit 4: the CPU stops, RAM and the clock keep going, and
///   <see cref="PowerOn"/>, the power switch, restarts the CPU at 0 with the devices reset, where the ROM finds RAM
///   still valid and carries on where it was.
///  </para>
/// </remarks>
public sealed class Trs80Model100Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Trs80Model100MemoryArea>();

    /// <summary>
    ///  Builds a machine, powered on.
    /// </summary>
    /// <param name="configuration">Its RAM and clock.</param>
    /// <param name="roms">Its ROMs.</param>
    /// <param name="variant">
    ///  The model, or null to tell it from the main ROM (a Model 100 when it is not known).
    /// </param>
    public Trs80Model100Machine(Trs80Model100Configuration configuration, Trs80Model100Roms roms, Trs80Model100Variant? variant = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(roms);
        configuration.Validate();
        Configuration = configuration;
        Roms = roms;
        Variant = variant ?? Trs80Model100Roms.Identify(roms.Main) ?? Trs80Model100Variant.Model100;
        Bus = new(configuration, roms) { PowerOff = TurnOff };
        Processor = new(Bus, I8080Variant.I8085);
        Processor.Signals = I8080Signals.SerialInput;
    }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public Trs80Model100Configuration Configuration { get; }

    /// <summary>
    ///  Gets the ROMs.
    /// </summary>
    public Trs80Model100Roms Roms { get; }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public Trs80Model100Variant Variant { get; }

    /// <summary>
    ///  Gets the bus.
    /// </summary>
    public Trs80Model100Bus Bus { get; }

    /// <summary>
    ///  Gets the 80C85.
    /// </summary>
    public I8080Processor<Trs80Model100Bus> Processor { get; }

    /// <summary>
    ///  Gets the LCD.
    /// </summary>
    public Trs80Model100Lcd Lcd => Bus.Lcd;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Trs80Model100Keyboard Keyboard => Bus.Keyboard;

    /// <summary>
    ///  Gets whether software has turned the power off.
    /// </summary>
    public bool IsPoweredOff { get; private set; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices { get; } = [];

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Turns the power on, as the power switch does: the CPU restarts at 0 and the devices reset; RAM keeps its
    ///  contents.
    /// </summary>
    public void PowerOn()
    {
        IsPoweredOff = false;
        Bus.Lcd.Blank = false;
        Bus.Reset();
        Processor.Reset();
    }

    /// <summary>
    ///  Resets the CPU and devices, as the RESET button on the back does; the same as <see cref="PowerOn"/>.
    /// </summary>
    public void Reset() => PowerOn();

    /// <inheritdoc/>
    public void StepCycle()
    {
        if (!IsPoweredOff) { Processor.StepCycle(); }
        Bus.Tick();
        I8080Signals signals = Processor.Signals;
        I8080Signals next = Bus.Clock.TimingPulse ? signals | I8080Signals.Restart75 : signals & ~I8080Signals.Restart75;
        if (next != signals) { Processor.Signals = next; }
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
    ///  Runs for a time, in the machine's seconds.
    /// </summary>
    /// <param name="seconds">The seconds.</param>
    public void RunSeconds(double seconds) => Run((ulong)(seconds * Trs80Model100Timing.ClockHertz));

    /// <inheritdoc/>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        if (IsPoweredOff) { return new() { Status = ProcessorExecutionStatus.Waiting, Cycles = 0 }; }
        for (int index = 0; index < maximumCycles; index++)
        {
            StepCycle();
            if (IsPoweredOff || Processor.IsInstructionBoundary)
            {
                return new()
                {
                    Status = Processor.IsHalted || IsPoweredOff
                        ? ProcessorExecutionStatus.Waiting
                        : ProcessorExecutionStatus.InstructionComplete,
                    Cycles = Processor.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = Processor.CycleCount - start };
    }

    /// <summary>
    ///  Gets the text the ROM keeps of the screen, its 40x8 character copy at $FE00-$FF3F, as eight lines.
    /// </summary>
    /// <returns>The lines, with characters outside printable ASCII as spaces.</returns>
    public string[] ScreenText()
    {
        string[] lines = new string[8];
        for (int row = 0; row < 8; row++)
        {
            char[] line = new char[40];
            for (int column = 0; column < 40; column++)
            {
                byte value = Bus.Peek((ushort)(0xFE00 + row * 40 + column));
                line[column] = value is >= 0x20 and < 0x7F ? (char)value : ' ';
            }

            lines[row] = new string(line).TrimEnd();
        }

        return lines;
    }

    // Software turns the power off: the CPU stops and the panel goes blank.
    private void TurnOff()
    {
        IsPoweredOff = true;
        Bus.Lcd.Blank = true;
    }

    string IMachine.Id => "trs80-model100";

    ICpuDebugView IMachine.Cpu => Processor;

    IVideoSource IMachine.Video => Bus.Lcd;

    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
