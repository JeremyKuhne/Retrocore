// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  A caller-clocked BBC Micro, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   An NMOS 6502 at 2 MHz, slowed to the 1 MHz clock for the slow devices (see <see cref="BbcBus"/>). The machine
///   powers on with every chip reset; BREAK (<see cref="PressBreak"/>) resets only the CPU and the user VIA, so the
///   operating system can tell a BREAK from a power-on by the system VIA's interrupt enables.
///  </para>
/// </remarks>
public sealed class BbcMachine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<BbcMemoryArea>();

    private bool _irq;
    private bool _nmi;

    /// <summary>
    ///  Constructs a machine at power-on.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="model">The model.</param>
    /// <param name="diskInterface">
    ///  Whether the 8271 disk interface is fitted; by default on the Model B, which the DFS ROM needs for its disks.
    /// </param>
    public BbcMachine(BbcRoms roms, BbcModel model = BbcModel.ModelB, bool? diskInterface = null)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Model = model;
        Bus = new(roms, model, diskInterface ?? model == BbcModel.ModelB);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        Processor.Reset();
        Devices = [Bus.Cassette, .. Bus.Drives];
    }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public BbcModel Model { get; }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public BbcBus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<BbcBus> Processor { get; }

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public BbcVideo Video => Bus.Video;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public BbcKeyboard Keyboard => Bus.Keyboard;

    /// <summary>
    ///  Gets the sound.
    /// </summary>
    public BbcAudio Audio => Bus.Audio;

    /// <summary>
    ///  Gets the cassette recorder.
    /// </summary>
    public BbcCassette Cassette => Bus.Cassette;

    /// <summary>
    ///  Gets the disk drives: none, or drives 0 and 1 on the 8271.
    /// </summary>
    public IReadOnlyList<BbcFloppyDrive> Drives => Bus.Drives;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The cassette recorder, then the disk drives.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<IDevice> Devices { get; }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Presses and releases BREAK: the CPU and the user VIA reset, keeping RAM. With CTRL held (see
    ///  <see cref="BbcKeyboard.Press"/>) the operating system starts afresh, as after power-on; with SHIFT it boots
    ///  the filing system's disk or tape.
    /// </summary>
    public void PressBreak()
    {
        Bus.ResetOnBreak();
        Processor.Reset();
    }

    /// <summary>
    ///  Advances the CPU one cycle, and the devices one or, for a slow access, two or three 2 MHz cycles;
    ///  <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        bool nmi = Bus.NonMaskableInterrupt;
        if (nmi != _nmi)
        {
            Processor.Signals = nmi
                ? Processor.Signals | ProcessorSignals.NonMaskableInterrupt
                : Processor.Signals & ~ProcessorSignals.NonMaskableInterrupt;

            _nmi = nmi;
        }

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
    }

    /// <summary>
    ///  Runs an exact number of CPU cycles.
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
    public void Run(TimeSpan duration)
    {
        long end = Bus.Cycles + (duration.Ticks / (TimeSpan.TicksPerSecond / BbcTiming.CpuHertz));
        while (Bus.Cycles < end) { StepCycle(); }
    }

    /// <summary>
    ///  Finishes the current instruction, or runs one, within a cycle limit.
    /// </summary>
    /// <param name="maximumCycles">The most CPU cycles to run.</param>
    /// <returns>Why it stopped and the CPU cycles it ran.</returns>
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
    ///  Reads the screen as text, from the 6845's start address.
    /// </summary>
    /// <returns>
    ///  In teletext, 25 lines of 40 characters, with control codes as spaces. In the other modes, a line per character
    ///  row, each character matched against the MOS's own font in any colour but the background's (logical colour 0),
    ///  and a space where none matches. The BBC's character 96 reads as £.
    /// </returns>
    public string[] ReadTextScreen()
    {
        BbcVideo video = Video;
        Chips.Crtc6845 crtc = video.Crtc;
        int columns = crtc[1];
        int rows = crtc[6];
        ushort start = crtc.StartAddress;
        string[] lines = new string[rows];
        if (video.Teletext)
        {
            Span<char> line = stackalloc char[columns];
            for (int row = 0; row < rows; row++)
            {
                for (int column = 0; column < columns; column++)
                {
                    // The SAA5050 shows £ at $23, # at $5F and a bar at $60, so the MOS stores the BBC's #, _ and £
                    // (character 96) there.
                    int code = Bus.Ram[video.ScreenAddress(start + (row * columns) + column, 0)] & 0x7F;
                    line[column] = code switch
                    {
                        < 0x20 => ' ',
                        0x23 => '£',
                        0x5F => '#',
                        0x60 => '_',
                        _ => (char)code
                    };
                }

                lines[row] = new string(line);
            }

            return lines;
        }

        // Pixels a byte holds: the pixel rate over the 6845's byte rate.
        int pixelsPerByte = (2 << ((video.Control >> 2) & 3)) / (video.FastClock ? 2 : 1);
        int bytesPerCharacter = Math.Max(1, 8 / pixelsPerByte);
        int textColumns = columns / bytesPerCharacter;
        int mask = pixelsPerByte switch { 8 => 0x80, 4 => 0x88, _ => 0xAA };
        Span<char> text = stackalloc char[textColumns];
        Span<byte> glyph = stackalloc byte[8];
        for (int row = 0; row < rows; row++)
        {
            for (int column = 0; column < textColumns; column++)
            {
                for (int line = 0; line < 8; line++)
                {
                    int dots = 0;
                    for (int index = 0; index < bytesPerCharacter; index++)
                    {
                        int address = start + (row * columns) + (column * bytesPerCharacter) + index;
                        int data = Bus.Ram[video.ScreenAddress(address, line)];
                        for (int pixel = 0; pixel < pixelsPerByte; pixel++)
                        {
                            dots = (dots << 1) | ((data & mask) != 0 ? 1 : 0);
                            data <<= 1;
                        }
                    }

                    glyph[line] = (byte)dots;
                }

                text[column] = Match(glyph);
            }

            lines[row] = new string(text);
        }

        return lines;
    }

    /// <inheritdoc/>
    string IMachine.Id => "bbc";

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
    void IMachine.QueueKey(byte code) => Keyboard.Type(code);

    // The MOS's font, at $C000: characters $20-$7F, 8 bytes each.
    private char Match(ReadOnlySpan<byte> glyph)
    {
        for (int code = 0x20; code < 0x80; code++)
        {
            bool same = true;
            for (int line = 0; line < 8 && same; line++)
            {
                same = Bus.Peek((ushort)(0xC000 + ((code - 0x20) * 8) + line)) == glyph[line];
            }

            if (same) { return code == 0x60 ? '£' : (char)code; }
        }

        return ' ';
    }
}
