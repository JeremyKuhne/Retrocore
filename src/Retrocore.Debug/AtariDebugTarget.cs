// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using Retrocore.Machines.Atari;
using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The Atari 400 or 800 as the debugger sees it: a 6502 at 1.79 MHz sharing its bus with ANTIC, the OS and floating
///  point ROMs, the cartridges, the screen ANTIC and GTIA draw, the keyboard and console keys, POKEY's sound, the 410
///  and the disk drives.
/// </summary>
/// <remarks>
///  <para>
///   The OS, the floating point package and each cartridge are memory areas of their own, so a source module for the
///   OS, the package or BASIC applies, and its breakpoints stop, only where its ROM is.
///  </para>
/// </remarks>
internal sealed partial class AtariDebugTarget : IDebugTarget
{
    private const byte JsrOpcode = 0x20;
    private const ushort ResetVector = 0xFFFC;

    /// <summary>
    ///  The key code for START, held for a moment.
    /// </summary>
    internal const int StartKey = 0xF0;

    /// <summary>
    ///  The key code for SELECT.
    /// </summary>
    internal const int SelectKey = 0xF1;

    /// <summary>
    ///  The key code for OPTION.
    /// </summary>
    internal const int OptionKey = 0xF2;

    /// <summary>
    ///  The key code for BREAK.
    /// </summary>
    internal const int BreakKey = 0xF3;

    /// <summary>
    ///  The key code for SYSTEM RESET.
    /// </summary>
    internal const int SystemResetKey = 0xF4;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly AtariMachine _machine;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;
    private DebugAudioSink? _sound;
    private string _soundMode = "off";
    private string _screen = DebugScreens.Color;

    // A power-on whose reset has not yet reached the OS's first instruction.
    private bool _resetPending;

    // The cycle a held console key, BREAK or SYSTEM RESET is let go at, and which.
    private ulong _releaseAt;
    private int _held;

    /// <summary>
    ///  Creates the target for a launched Atari.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal AtariDebugTarget(AtariMachine machine)
    {
        _machine = machine;
        _calls = new(machine.Bus.Peek);
        _pixels = new byte[machine.Width * machine.Height * 4];
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/media"] = Media,
            ["retro/video"] = args => VideoFrame(args.Bool("scanned") ?? true),
            ["retro/sound"] = args =>
            {
                SetSound(args.String("mode") ?? throw new ArgumentException("mode is required."));
                return new JsonObject { ["mode"] = _soundMode };
            }
        };
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal AtariMachine Machine => _machine;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the cassette motor runs.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the ROMs were built from the SDK's sources rather than loaded from dumps.
    /// </summary>
    internal bool SdkRoms { get; set; }

    /// <inheritdoc/>
    public string ThreadName => _machine.Model == AtariModel.Atari400 ? "400 6502" : "800 6502";

    /// <inheritdoc/>
    public string Cpu => nameof(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6502Isa.Get(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => M6502Frames.Of(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.ProgramCounter;
        set
        {
            ProcessorRegisters registers = _machine.Processor.Registers;
            registers.ProgramCounter = value;
            _machine.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary;

    /// <inheritdoc/>
    public bool InInstruction => _machine.Processor.CurrentOpCode is not null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   ANTIC holds the 6502's RDY line from a write to <c>WSYNC</c> to the next scan line's end, up to 114 cycles.
    ///  </para>
    /// </remarks>
    public bool IsHeld => (_machine.Processor.Signals & ProcessorSignals.ReadyStall) != 0;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => AtariTiming.CpuHertz(_machine.Bus.Standard);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine runs as fast as it can while the cassette motor runs, unless the launch asks not to.
    ///  </para>
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Cassette.Motor;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>$2000</c>: above DOS 2.0S's memory and BASIC's tables for a small program, and below every graphics mode's
    ///   screen on a 48K machine.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x2000;

    /// <inheritdoc/>
    public Enum ProgramArea => AtariMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Atari";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "X", "Y"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Zero page", 0, 256);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The cartridge windows are named by what the bus maps there now: a cartridge, RAM, or nothing.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<DebugRegion> Regions =>
    [
        new("Zero page", 0x0000, 0x100, "ram"),
        new("Stack", 0x0100, 0x100, "ram"),
        new("OS and DOS RAM, the cassette buffer and BASIC's buffers", 0x0200, 0x0500, "ram"),
        .. Ram(),
        Window("Right cartridge", 0x8000, 0x2000),
        Window("Left cartridge", 0xA000, 0x2000),
        Window("Nothing", 0xC000, 0x1000),
        new("GTIA, POKEY, the PIA and ANTIC", 0xD000, 0x0800, "io"),
        new("Floating point ROM", 0xD800, 0x0800, "rom"),
        new("Character set, in the OS ROM", 0xE000, 0x0400, "rom"),
        new("OS ROM", 0xE400, 0x1C00, "rom")
    ];

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack pointer points into page one.
    ///  </para>
    /// </remarks>
    public int? PointsTo(IsaRegister register, long value) => register.Name == "S"
        ? 0x100 | (int)(value & 0xFF)
        : register.Bits >= 16 ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        ProcessorRegisters before = _machine.Processor.Registers;
        bool wasBoundary = _machine.Processor.IsInstructionBoundary;
        _machine.StepCycle();
        _calls.Observe(_machine.LastCycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
        if (_held != 0 && CycleCount >= _releaseAt) { Release(); }
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public void RunCycles(int cycles)
    {
        ulong end = CycleCount + (ulong)cycles;
        while (CycleCount < end)
        {
            _machine.StepCycle();
            if (_held != 0 && CycleCount >= _releaseAt) { Release(); }
        }

        _calls.Reset();
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address) =>
        Peek(address) == JsrOpcode ? ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3) : null;

    /// <inheritdoc/>
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) is AtariMemoryArea.OperatingSystem
        or AtariMemoryArea.FloatingPoint
        or AtariMemoryArea.LeftCartridge
        or AtariMemoryArea.RightCartridge;

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address is not RAM.</exception>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address)) { throw new ArgumentException($"${address:X4} is not RAM."); }
        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) == AtariMemoryArea.Ram;

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("Program must fit in the 64 KB address space.");
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            ushort at = (ushort)(address + index);
            if (!CanPoke(at)) { throw new ArgumentException($"Program must fit in RAM; ${at:X4} is not RAM."); }
            _machine.Bus.Write(at, bytes[index]);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The OS debugs against <c>Os.asm</c> and the floating point package against <c>FloatingPoint.asm</c>, each when
    ///   the ROM is a build of its source; Atari BASIC in either cartridge slot debugs against <c>AtariBasic.asm</c>,
    ///   built for its revision, and only while that slot is mapped.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sdk = AtariSdkModules.SdkDirectory(directory);
        if (!File.Exists(Path.Join(sdk, "Os.asm"))) { return; }
        ReadOnlySpan<byte> image = _machine.Bus.Roms.Image;
        if (AtariSdkModules.OsVersionOf(image[0x0800..]) is { } os)
        {
            debug.Add(new SourceMapModule(AtariSdkModules.AssembleOs(sdk, os), AtariMemoryArea.OperatingSystem));
        }

        if (AtariSdkModules.IsFloatingPoint(image[..0x0800]))
        {
            debug.Add(new SourceMapModule(AtariSdkModules.AssembleFloatingPoint(sdk), AtariMemoryArea.FloatingPoint));
        }

        if (_machine.Bus.Left is { } left && AtariSdkModules.BasicVersionOf(left.Rom) is { } basic)
        {
            Assembler.AssemblyResult result = AtariSdkModules.AssembleBasic(sdk, basic);
            debug.Add(new SourceMapModule(result, AtariMemoryArea.LeftCartridge));
            SetBasic(result.Symbols);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <see cref="SystemResetKey"/>, the highest of the keys that type nothing.
    ///  </para>
    /// </remarks>
    public int MaximumKey => SystemResetKey;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   ATASCII through the keyboard's queue, a carriage return as RETURN; above it, the keys that type nothing, held
    ///   for a tenth of a second: <see cref="StartKey"/>, <see cref="SelectKey"/>, <see cref="OptionKey"/>,
    ///   <see cref="BreakKey"/> and <see cref="SystemResetKey"/>.
    ///  </para>
    /// </remarks>
    public bool Key(int code)
    {
        if (code < 0x80) { return _machine.Keyboard.Type((byte)code); }
        if (code is < StartKey or > SystemResetKey) { return false; }
        Release();
        _held = code;
        _releaseAt = CycleCount + (ulong)(ClockHertz / 10);
        Hold(code, held: true);
        return true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Powers the machine off and on: the 400's and 800's SYSTEM RESET is an interrupt the OS takes as a warm start,
    ///   which <see cref="SystemResetKey"/> presses.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        Release();
        _machine.PowerOn();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stop is at the OS's first instruction, where the reset vector points.
    ///  </para>
    /// </remarks>
    public bool TakeResetStop()
    {
        ushort vector = (ushort)(Peek(ResetVector) | (Peek(ResetVector + 1) << 8));
        if (!_resetPending || !IsInstructionBoundary || ProgramCounter != vector) { return false; }
        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Audio.Flush();
        return _sound.Take() is { } samples
            ? new JsonObject { ["rate"] = _sound.SampleRate, ["channels"] = _sound.Channels, ["samples"] = samples }
            : null;
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("retro/media", MediaState());
    }

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running)
    {
        string[] rows = _machine.ReadTextScreen();
        return new JsonObject
        {
            ["machine"] = DebugMachines.Atari,
            ["model"] = ModelName,
            ["columns"] = rows.Length == 0 ? 40 : rows[0].Length,
            ["rows"] = rows.ToJsonArray(),
            ["cycles"] = CycleCount,
            ["video"] = VideoState(),
            ["media"] = MediaState(),
            ["sound"] = _soundMode,
            ["screen"] = _screen,
            ["screens"] = Screens.ToJsonArray(),
            ["running"] = running
        };
    }

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => DebugScreens.WithColor;

    /// <inheritdoc/>
    public string Screen
    {
        get => _screen;
        set => _screen = DebugScreens.Require(value, Screens);
    }

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        bool pal = _machine.Bus.Standard == AtariVideoStandard.Pal;
        return
        [
            new("model", "Atari", ModelName, "The launch's model: atari800 or atari400."),
            new("cpu", "Processor", pal ? "6502 at 1.77 MHz" : "6502 at 1.79 MHz", "ANTIC takes cycles for its display DMA."),
            new("rom", "ROMs", RomText(), "The dumps in romDirectory or RETROCORE_ATARI_ROMS; without them, built from the SDK's sources."),
            new("memory", "Memory", $"{_machine.Bus.RamSize / 1024} KB", "The launch's ramKilobytes option: 8 to 48 KB."),
            new("video", "Video", pal ? "ANTIC and GTIA, PAL" : "ANTIC and GTIA, NTSC", "The launch's video option: ntsc or pal."),
            new("sound", "Sound", "POKEY", "Four channels, through the TV."),
            new("cassette", "Cassette", "410 Program Recorder", "The serial bus's cassette, at 600 baud.", [_machine.Cassette.Id]),
            new(
                "disk",
                "Disk drives",
                _machine.Drives.Count == 0 ? "none" : $"{_machine.Drives.Count} × {DriveText()}",
                "The launch's diskDrives option, 0 to 4, and diskDrive: atari810 or sio.",
                _machine.Drives.Count != 0 ? [.. _machine.Drives.Select(drive => drive.Id)] : null)
        ];
    }

    private string ModelName => _machine.Model == AtariModel.Atari400 ? "Atari 400" : "Atari 800";

    // The ROMs' row: the OS, the floating point package and the cartridges.
    private string RomText()
    {
        ReadOnlySpan<byte> image = _machine.Bus.Roms.Image;
        List<string> names =
        [
            AtariSdkModules.OsVersionOf(image[0x0800..]) switch
            {
                AtariSdkModules.OsRevisionA => "OS rev. A",
                AtariSdkModules.OsRevisionB => "OS rev. B",
                AtariSdkModules.OsPal => "PAL OS",
                _ => "OS"
            },
            "floating point"
        ];

        if (_machine.Bus.Left is { } left)
        {
            names.Add(AtariSdkModules.BasicVersionOf(left.Rom) is { } basic
                ? $"Atari BASIC rev. {(char)('A' + basic - 1)}"
                : $"left cartridge, {left.Size / 1024} KB");
        }

        if (_machine.Bus.Right is { } right) { names.Add($"right cartridge, {right.Size / 1024} KB"); }
        return string.Join(", ", names) + (SdkRoms ? ", from the SDK's sources" : "");
    }

    // The drives' kind: an 810 with its firmware's revision, or the command-level drive.
    private string DriveText() => _machine.Drives[0] is Atari810 drive ? $"810, firmware rev. {drive.Revision}" : "SIO disk drive";

    // Presses or lets go of a key that types nothing.
    private void Hold(int code, bool held)
    {
        AtariKeyboard keyboard = _machine.Keyboard;
        AtariConsoleKeys console = code switch
        {
            StartKey => AtariConsoleKeys.Start,
            SelectKey => AtariConsoleKeys.Select,
            OptionKey => AtariConsoleKeys.Option,
            _ => 0
        };

        if (console != 0)
        {
            keyboard.ConsoleKeys = held ? keyboard.ConsoleKeys | console : keyboard.ConsoleKeys & ~console;
        }
        else if (code == BreakKey)
        {
            keyboard.Break = held;
        }
        else if (code == SystemResetKey)
        {
            keyboard.SystemReset = held;
        }
    }

    // Lets go of the key held, if any.
    private void Release()
    {
        if (_held == 0) { return; }
        Hold(_held, held: false);
        _held = 0;
    }

    // off attaches no sink; speaker hears POKEY and the console speaker through the TV, in mono.
    private void SetSound(string mode)
    {
        AtariAudio audio = _machine.Audio;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        audio.Sink = _sound;
        _soundMode = mode;
    }

    // The RAM from $0700 to the top of memory, and nothing above it to $8000 on a machine with less than 32 KB.
    private DebugRegion[] Ram()
    {
        int top = Math.Min(_machine.Bus.RamSize, 0x8000);
        return top >= 0x8000
            ? [new("RAM", 0x0700, 0x8000 - 0x0700, "ram")]
            : [new("RAM", 0x0700, top - 0x0700, "ram"), new("Nothing mapped here", (ushort)top, 0x8000 - top, "none")];
    }

    // A cartridge window, named by what the bus maps there now.
    private DebugRegion Window(string cartridge, ushort start, int length) => _machine.Bus.Area(start) switch
    {
        AtariMemoryArea.Ram => new("RAM", start, length, "ram"),
        AtariMemoryArea.LeftCartridge or AtariMemoryArea.RightCartridge => new(cartridge, start, length, "rom"),
        _ => new("Nothing mapped here", start, length, "none")
    };

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Width,
        ["height"] = _machine.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Render(_pixels, scanned);
        DebugScreens.Show(_pixels, _screen);
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(_pixels);
        return frame;
    }
}
