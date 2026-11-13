// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Cpu.M6809;
using Retrocore.Isa;
using Retrocore.Machines.Coco;

namespace Retrocore.Debug;

/// <summary>
///  The TRS-80 Color Computer 1, 2 or 3 as the debugger sees it: a 6809, the SAM's or GIME's memory map, the
///  text screen, keyboard, cassette, sound and disks.
/// </summary>
internal sealed partial class CocoDebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(M6809Isa.Description);

    private readonly CocoMachine _machine;
    private readonly M6809CallStack _calls;
    private readonly byte[] _pixels;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private DebugAudioSink? _sound;
    private string _soundMode = "off";
    private string _screen = DebugScreens.Color;

    // A reset button press whose handler has not yet started.
    private bool _resetPending;

    /// <summary>
    ///  Creates the target for a launched Color Computer.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal CocoDebugTarget(CocoMachine machine)
    {
        _machine = machine;
        _calls = new(this);
        Machines.IVideoSource video = machine.Bus.VideoOutput;
        _pixels = new byte[video.Width * video.Height * 4];
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
    internal CocoMachine Machine => _machine;

    /// <inheritdoc/>
    public string ThreadName => _machine.Model switch
    {
        CocoModel.Coco1 => "CoCo 1 6809",
        CocoModel.Coco2 => "CoCo 2 6809",
        _ => "CoCo 3 6809"
    };

    /// <inheritdoc/>
    public string Cpu => M6809Isa.Name;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public DebugFrame Frame => FrameOf(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.PC;
        set
        {
            M6809Registers registers = _machine.Processor.Registers;
            registers.PC = value;
            _machine.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary && !IsIdle;

    /// <inheritdoc/>
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk controller holds HALT while Disk BASIC waits for each byte, and programs may wait in <c>SYNC</c>
    ///   or <c>CWAI</c> for an interrupt.
    ///  </para>
    /// </remarks>
    public bool IsIdle => _machine.Processor.IsHalted || _machine.Processor.IsWaiting;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The slow rate's clock; the SAM's and GIME's double speed runs more cycles in the same time.
    ///  </para>
    /// </remarks>
    public int ClockHertz => (int)Math.Round(CocoTiming.ClockHertz);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine runs as fast as it can while the cassette motor runs, unless the launch asks not to.
    ///  </para>
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Bus.CassetteMotor;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the cassette motor runs.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the ROMs were built from the SDK's sources rather than loaded from dumps.
    /// </summary>
    internal bool SdkRoms { get; set; }

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>$3000</c> is free RAM on every model, above Color BASIC's program and graphics pages.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x3000;

    /// <inheritdoc/>
    public Enum ProgramArea => CocoMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Coco";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "X", "Y", "U"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Direct page", 0x0000, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6809Isa.InstructionSet;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public IReadOnlyList<Machines.Devices.IDevice> Devices => _machine.Devices;

    /// <summary>
    ///  Copies a 6809's registers into a frame, in the instruction set's register order.
    /// </summary>
    /// <param name="registers">The registers.</param>
    /// <returns>The frame.</returns>
    internal static DebugFrame FrameOf(M6809Registers registers)
    {
        DebugFrame frame = new()
        {
            ProgramCounter = registers.PC,
            StackPointer = registers.S
        };

        ReadOnlySpan<ushort> values =
        [
            registers.A, registers.B, registers.D, registers.X, registers.Y, registers.U, registers.S, registers.DP,
            registers.CC, registers.PC
        ];

        for (int index = 0; index < values.Length; index++) { frame[index] = values[index]; }
        return frame;
    }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   D holds two accumulators, not an address.
    ///  </para>
    /// </remarks>
    public int? PointsTo(IsaRegister register, long value) =>
        register.Bits >= 16 && register.Name != "D" ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        if (_machine.Processor.IsInstructionBoundary)
        {
            _beforeInstruction = Frame;
            _instruction = true;
        }

        _machine.StepCycle();
        if (_machine.Processor.IsInstructionBoundary && _instruction)
        {
            _instruction = false;
            _calls.Complete(_beforeInstruction, Frame);
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address) =>
        M6809CallStack.CallAt(this, address, _machine.Processor.Registers.DP);

    /// <inheritdoc/>
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (_machine.Bus.Area(address) != CocoMemoryArea.Ram)
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("Program must fit in the 64 KB address space.");
        }

        for (int i = 0; i < bytes.Length; i++)
        {
            ushort at = (ushort)(address + i);
            if (_machine.Bus.Area(at) != CocoMemoryArea.Ram)
            {
                throw new ArgumentException($"Program must fit in RAM; ${at:X4} is not RAM.");
            }

            _machine.Bus.Write(at, bytes[i]);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A CoCo 1 or 2's Color BASIC debugs against <c>ColorBasic.asm</c>, its Extended Color BASIC against
    ///   <c>ExtendedBasic.asm</c>, and the disk controller's Disk Extended Color BASIC against <c>DiskBasic.asm</c>,
    ///   each built for its version. A CoCo 3's ROM debugs against the CoCo 3's build of <c>ExtendedBasic.asm</c> and
    ///   <c>ColorBasic.asm</c> and against <c>Coco3.asm</c>. The CoCo 3 copies its ROM, and Disk BASIC's, into RAM
    ///   and runs it there, patched, so its modules apply wherever the memory map puts those bytes, and the patched
    ///   places show the patches' source, in <c>Coco3.asm</c>.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sdk = CocoSdkModules.SdkDirectory(directory);
        bool coco3 = _machine.Model == CocoModel.Coco3;
        if (coco3 && CocoSdkModules.IsCoco3Rom(_machine.Bus.Coco3Rom) && File.Exists(Path.Join(sdk, "Coco3.asm")))
        {
            Coco3Assembly rom = CocoSdkModules.AssembleCoco3(sdk);
            debug.Add(new SourceMapModule(rom.Coco3, area: null));
            debug.Add(new SourceMapModule(rom.ExtendedBasic, area: null));
            debug.Add(new SourceMapModule(rom.ColorBasic, area: null));
        }

        string source = Path.Join(sdk, "ColorBasic.asm");
        if (!coco3 && CocoSdkModules.VersionOf(_machine.Bus.ColorBasicRom) is { } version && File.Exists(source))
        {
            debug.Add(new SourceMapModule(CocoSdkModules.AssembleColorBasic(source, version), CocoMemoryArea.ColorBasic));
        }

        source = Path.Join(sdk, "ExtendedBasic.asm");
        if (!coco3 && CocoSdkModules.ExtendedVersionOf(_machine.Bus.ExtendedBasicRom) is { } extended && File.Exists(source))
        {
            debug.Add(new SourceMapModule(CocoSdkModules.AssembleExtendedBasic(source, extended), CocoMemoryArea.ExtendedBasic));
        }

        // The disk controller's ROM is in the cartridge slot when no cartridge is; a CoCo 3 runs a copy in RAM.
        source = Path.Join(sdk, "DiskBasic.asm");
        if (_machine.Bus.Cartridge is null
            && _machine.Bus.DiskController is { } controller
            && CocoSdkModules.DiskVersionOf(controller.Rom.Bytes) is { } disk
            && File.Exists(source))
        {
            debug.Add(new SourceMapModule(CocoSdkModules.AssembleDiskBasic(source, disk), coco3 ? null : CocoMemoryArea.Cartridge));
        }
    }

    /// <inheritdoc/>
    public bool Key(int code) => _machine.Bus.Keyboard.Type((byte)code);

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   RESET restarts the 6809, which fetches the reset vector at <c>$FFFE</c>; the stop is at its first
    ///   instruction.
    ///  </para>
    /// </remarks>
    public bool TakeResetStop()
    {
        ushort vector = (ushort)((Peek(0xFFFE) << 8) | Peek(0xFFFF));
        if (!_resetPending || !IsInstructionBoundary || _machine.Processor.Registers.PC != vector)
        {
            return false;
        }

        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Bus.Audio.Flush();
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
        string[] rows = _machine.Bus.TextRows();
        return new JsonObject
        {
            ["machine"] = DebugMachines.Coco,
            ["model"] = ModelName,
            ["columns"] = rows.Length == 0 ? 32 : rows[0].Length,
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
    public IReadOnlyList<HardwareRow> Hardware()
    {
        CocoConfiguration configuration = _machine.Configuration;
        bool coco3 = configuration.Model == CocoModel.Coco3;
        string video = coco3
            ? configuration.RgbMonitor ? "GIME, RGB monitor" : "GIME, composite monitor"
            : configuration.LowercaseVdg ? "MC6847T1 VDG, with lowercase" : "MC6847 VDG";

        CocoDiskController? disk = _machine.Bus.DiskController;
        return
        [
            new("model", "Color Computer", ModelName, "The launch's model: coco1, coco2 or coco3."),
            new("cpu", "Processor", "6809E at 0.895 MHz", "Doubled by the SAM's or GIME's fast rate."),
            new(
                "rom",
                "ROM",
                RomText(),
                "The dumps in romDirectory or RETROCORE_COCO_ROMS; without them, built from the SDK's sources."),
            new(
                "memory",
                "Memory",
                $"{configuration.RamBytes / 1024} KB",
                "The launch's ramKilobytes option: 4, 16, 32 or 64 KB on a CoCo 1 or 2, 128 or 512 KB on a CoCo 3."),
            new("video", "Video", video, "The launch's lowercase option on a CoCo 2, or monitor on a CoCo 3."),
            new(
                "cassette",
                "Cassette",
                "Cassette recorder",
                "The cassette port, at 1500 baud.",
                [_machine.Cassette.Id]),
            new(
                "cartridge",
                "Cartridge",
                _machine.Bus.Cartridge is { } pack ? $"ROM pack, {pack.Size / 1024.0:0.#} KB" : disk is not null ? "disk controller" : "none",
                "The launch's cartridge option: a ROM pack image, which takes the slot from a disk controller."),
            new(
                "disk",
                "Disk controller",
                disk is not null ? DiskText(disk) : "none",
                "The launch's diskController option, on by default when disks are given.",
                disk is not null ? [.. disk.Drives.Select(drive => drive.Id)] : null)
        ];
    }

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Bus.VideoOutput.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    private string RomText()
    {
        if (_machine.Model == CocoModel.Coco3)
        {
            return "Color, Extended and Super Extended Color BASIC 2.0" + (SdkRoms ? ", from the SDK's sources" : "");
        }

        string color = CocoSdkModules.VersionOf(_machine.Bus.ColorBasicRom) is { } version
            ? $"Color BASIC 1.{version - 10}"
            : "Color BASIC";

        string extended = CocoSdkModules.ExtendedVersionOf(_machine.Bus.ExtendedBasicRom) is { } extendedVersion
            ? $", Extended Color BASIC 1.{extendedVersion - 10}"
            : _machine.Bus.HasExtendedBasic ? ", Extended Color BASIC" : "";

        return color + extended + (SdkRoms ? ", from the SDK's sources" : "");
    }

    // The disk controller's row: its chip and its ROM's version.
    private static string DiskText(CocoDiskController disk) =>
        CocoSdkModules.DiskVersionOf(disk.Rom.Bytes) is { } version
            ? $"WD1793, Disk Extended Color BASIC 1.{version - 10}"
            : "WD1793, Disk Extended Color BASIC";

    private string ModelName => _machine.Model switch
    {
        CocoModel.Coco1 => "Color Computer 1",
        CocoModel.Coco2 => "Color Computer 2",
        _ => "Color Computer 3"
    };

    // off attaches no sink; speaker hears the DAC, cassette and single-bit sound through the TV, in mono.
    private void SetSound(string mode)
    {
        CocoAudio audio = _machine.Bus.Audio;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        audio.Sink = _sound;
        _soundMode = mode;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Bus.VideoOutput.Width,
        ["height"] = _machine.Bus.VideoOutput.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Bus.VideoOutput.Render(_pixels, scanned);
        DebugScreens.Show(_pixels, _screen);
        return new JsonObject
        {
            ["width"] = _machine.Bus.VideoOutput.Width,
            ["height"] = _machine.Bus.VideoOutput.Height,
            ["pixelFormat"] = "rgba",
            ["pixels"] = Convert.ToBase64String(_pixels),
            ["cycles"] = CycleCount
        };
    }
}
