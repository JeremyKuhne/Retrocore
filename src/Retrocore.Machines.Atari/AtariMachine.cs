// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Atari;

/// <summary>
///  A caller-clocked Atari 400 or 800, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   An NMOS 6502 at 1.79 MHz (NTSC) or 1.77 MHz (PAL) sharing its bus with ANTIC, which takes whole cycles for
///   DMA and holds the CPU's RDY line for <c>WSYNC</c>. ANTIC's NMIs and the IRQs of POKEY and the PIA go to the
///   CPU. SYSTEM RESET on the 400 and 800 is an NMI through ANTIC (<see cref="AtariKeyboard.SystemReset"/>), not a
///   reset; <see cref="PowerOn"/> is the only full reset.
///  </para>
/// </remarks>
public sealed class AtariMachine : IMachine, IVideoSource
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<AtariMemoryArea>();

    private bool _irq;
    private bool _nmi;

    /// <summary>
    ///  Constructs a machine at power-on.
    /// </summary>
    /// <param name="roms">The OS ROM.</param>
    /// <param name="model">The model.</param>
    /// <param name="ramSize">
    ///  The RAM in bytes, 8 KB to 48 KB in 8 KB steps; by default 48 KB on the 800 and 16 KB on the 400.
    /// </param>
    /// <param name="left">The left (or the 400's only) cartridge, or null.</param>
    /// <param name="right">The 800's right cartridge, or null.</param>
    /// <param name="standard">The television standard.</param>
    /// <param name="chip">GTIA or the earlier CTIA.</param>
    /// <param name="diskDrives">How many disk drives are on the serial bus, 0-4.</param>
    /// <param name="driveKind">
    ///  How the disk drives are emulated: by default as 810s, which needs the 810's firmware in <paramref name="roms"/>.
    /// </param>
    public AtariMachine(
        AtariRoms roms,
        AtariModel model = AtariModel.Atari800,
        int? ramSize = null,
        AtariCartridge? left = null,
        AtariCartridge? right = null,
        AtariVideoStandard standard = AtariVideoStandard.Ntsc,
        AtariGraphicsChip chip = AtariGraphicsChip.Gtia,
        int diskDrives = 0,
        AtariDiskDriveKind driveKind = AtariDiskDriveKind.Atari810)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Model = model;
        int ram = ramSize ?? (model == AtariModel.Atari400 ? 0x4000 : 0xC000);
        Bus = new(roms, model, ram, standard, chip, left, right, diskDrives, driveKind);
        Devices = [Bus.Cassette, .. Bus.Drives];
        Bus.Keyboard.ShiftLock = () => Bus.Peek(0x02BE);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        PowerOn();
    }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public AtariModel Model { get; }

    /// <summary>
    ///  Gets the memory and chips.
    /// </summary>
    public AtariBus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<AtariBus> Processor { get; }

    /// <summary>
    ///  Gets ANTIC.
    /// </summary>
    public Antic Antic => Bus.Antic;

    /// <summary>
    ///  Gets GTIA.
    /// </summary>
    public Gtia Gtia => Bus.Gtia;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public AtariKeyboard Keyboard => Bus.Keyboard;

    /// <summary>
    ///  Gets the sound.
    /// </summary>
    public AtariAudio Audio => Bus.Audio;

    /// <summary>
    ///  Gets the disk drives, <c>D1:</c> first.
    /// </summary>
    public IReadOnlyList<AtariDiskDrive> Drives => Bus.Drives;

    /// <summary>
    ///  Gets the 410 Program Recorder.
    /// </summary>
    public Atari410 Cassette => Bus.Cassette;

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
    ///  Powers the machine off and on: the CPU and the PIA reset and ANTIC clears <c>NMIEN</c> and <c>DMACTL</c>; RAM
    ///  keeps what it held.
    /// </summary>
    public void PowerOn()
    {
        Bus.Antic.PowerOn();
        Bus.Pia.Reset();
        Bus.ResetCartridges();
        Processor.Signals = ProcessorSignals.None;
        _irq = false;
        _nmi = false;
        Processor.Reset();
    }

    /// <summary>
    ///  Runs machine cycles until the CPU has run one: any DMA cycles ANTIC takes first, then the CPU's (which may be
    ///  held by <c>WSYNC</c>). <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        while (!MachineCycle()) { }
    }

    /// <summary>
    ///  Runs an exact number of machine cycles, DMA included.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(long cycles)
    {
        long end = Bus.Cycles + cycles;
        while (Bus.Cycles < end) { MachineCycle(); }
    }

    /// <summary>
    ///  Runs for a span of emulated time.
    /// </summary>
    /// <param name="duration">The time to run.</param>
    public void Run(TimeSpan duration) =>
        Run((long)(duration.TotalSeconds * AtariTiming.CpuHertz(Bus.Standard)));

    /// <summary>
    ///  Runs to the start of the next frame's vertical blank.
    /// </summary>
    public void RunFrame()
    {
        do { MachineCycle(); }
        while (!(Antic.Line == AtariTiming.VerticalBlankLine && Antic.Cycle == 0));
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The default limit allows for <c>WSYNC</c>, which can hold an instruction for more than a scan line.
    ///  </para>
    /// </remarks>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 512)
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
    ///  Reads the text screen the OS's screen editor shows: 24 lines of 40 characters from <c>SAVMSC</c>.
    /// </summary>
    /// <returns>
    ///  The lines as ATASCII, with inverse video dropped and the control characters (<c>$00-$1F</c>, <c>$7D-$7F</c>)
    ///  as spaces.
    /// </returns>
    public string[] ReadTextScreen()
    {
        ushort screen = (ushort)(Bus.Peek(0x58) | (Bus.Peek(0x59) << 8));
        string[] lines = new string[24];
        Span<char> line = stackalloc char[40];
        for (int row = 0; row < 24; row++)
        {
            for (int column = 0; column < 40; column++)
            {
                int code = Bus.Peek((ushort)(screen + (row * 40) + column)) & 0x7F;

                // ANTIC's internal codes: $00-$3F are ATASCII $20-$5F, $40-$5F are $00-$1F, $60-$7F are themselves.
                int atascii = code switch
                {
                    < 0x40 => code + 0x20,
                    < 0x60 => code - 0x40,
                    _ => code
                };

                line[column] = atascii is >= 0x20 and < 0x7D ? (char)atascii : ' ';
            }

            lines[row] = new string(line);
        }

        return lines;
    }

    /// <summary>
    ///  Gets a copy of the frame, 376 × 240 RGBA.
    /// </summary>
    /// <returns>The pixels.</returns>
    public byte[] RenderBitmap() => Gtia.Frame.ToArray();

    /// <inheritdoc/>
    public int Width => Gtia.FrameWidth;

    /// <inheritdoc/>
    public int Height => Gtia.FrameHeight;

    /// <inheritdoc/>
    public int CyclesPerFrame => AtariTiming.CyclesPerFrame(Bus.Standard);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Both ways give the frame as the beam drew it: ANTIC's display depends on the CPU's timing (display list
    ///   interrupts, mid-line writes), so there is no frame to draw from memory alone.
    ///  </para>
    /// </remarks>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Gtia.Frame.Length)
        {
            throw new ArgumentException("Pixels must be 376×240 RGBA.", nameof(pixels));
        }

        Gtia.Frame.CopyTo(pixels);
    }

    /// <inheritdoc/>
    string IMachine.Id => "atari800";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => this;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Keyboard.Type(code);

    // One machine cycle: returns whether the CPU ran.
    private bool MachineCycle()
    {
        Antic antic = Bus.Antic;
        bool dma = antic.BeginCycle();
        if (antic.TakeNmi()) { _nmi = true; }
        if (!dma)
        {
            ProcessorSignals signals = Processor.Signals;
            signals = _nmi ? signals | ProcessorSignals.NonMaskableInterrupt : signals & ~ProcessorSignals.NonMaskableInterrupt;
            bool irq = Bus.InterruptRequested;
            if (irq != _irq) { _irq = irq; }
            signals = irq ? signals | ProcessorSignals.InterruptRequest : signals & ~ProcessorSignals.InterruptRequest;
            signals = antic.HoldsCpu ? signals | ProcessorSignals.ReadyStall : signals & ~ProcessorSignals.ReadyStall;
            if (signals != Processor.Signals) { Processor.Signals = signals; }
            Processor.StepCycle();

            // NMI is an edge: the CPU has seen it once it has run a cycle with it.
            _nmi = false;
        }

        Bus.Tick();
        antic.EndCycle();
        if (antic.Cycle == 0 && antic.Line == AtariTiming.VerticalBlankLine) { Bus.Keyboard.Frame(); }
        return !dma;
    }
}
