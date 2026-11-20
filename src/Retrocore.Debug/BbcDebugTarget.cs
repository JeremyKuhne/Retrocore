// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Isa;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The BBC Micro as the debugger sees it: a 6502 at 2 MHz, the MOS and the paged ROM ROMSEL selects, the screen in
///  every mode, the keyboard, sound, cassette and disks.
/// </summary>
/// <remarks>
///  <para>
///   The paged ROM sockets are separate memory areas, so a source module for BASIC or the DFS applies, and its
///   breakpoints stop, only while ROMSEL has its socket paged in.
///  </para>
/// </remarks>
internal sealed partial class BbcDebugTarget : IDebugTarget
{
    private const byte JsrOpcode = 0x20;
    private const byte BrkOpcode = 0x00;
    private const ushort ResetVector = 0xFFFC;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly BbcMachine _machine;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;
    private DebugAudioSink? _sound;
    private string _soundMode = "off";
    private string _screen = DebugScreens.Color;

    // A BREAK whose reset has not yet reached the MOS's first instruction.
    private bool _resetPending;

    /// <summary>
    ///  Creates the target for a launched BBC Micro.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal BbcDebugTarget(BbcMachine machine)
    {
        _machine = machine;
        _calls = new(machine.Bus.Peek);
        _pixels = new byte[machine.Video.Width * machine.Video.Height * 4];
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
    internal BbcMachine Machine => _machine;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the cassette motor runs.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the ROMs were built from the SDK's sources rather than loaded from dumps.
    /// </summary>
    internal bool SdkRoms { get; set; }

    /// <inheritdoc/>
    public string ThreadName => _machine.Model == BbcModel.ModelA ? "Model A 6502" : "Model B 6502";

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
    ///   The bus's 2 MHz cycles, with those a 1 MHz device's access stretches, so running at real speed keeps to the
    ///   machine's clock.
    ///  </para>
    /// </remarks>
    public ulong CycleCount => (ulong)_machine.Bus.Cycles;

    /// <inheritdoc/>
    public int ClockHertz => BbcTiming.CpuHertz;

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
    ///   <c>$2000</c>, where <c>*RUN</c> conventionally puts machine code: above PAGE with the DFS (<c>$1900</c>) and
    ///   below every mode's screen on both models.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x2000;

    /// <inheritdoc/>
    public Enum ProgramArea => BbcMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Bbc";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "X", "Y"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Zero page", 0, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>$8000-$BFFF</c> is the socket ROMSEL selects now, so each paged ROM is its own area.
    ///  </para>
    /// </remarks>
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

        // Only an opcode fetch runs the instruction at the boundary: an IRQ taken there leaves the PC where it was, so
        // the same boundary comes again after RTI, and observing both would count a PROC's call or return twice.
        if (_basicRom is not null && _machine.Processor.FetchedOpcode) { ObserveBasicCall(before.ProgramCounter); }
        _calls.Observe(_machine.LastCycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public void RunCycles(int cycles)
    {
        for (int count = 0; count < cycles; count++) { _machine.StepCycle(); }
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
    /// <remarks>
    ///  <para>
    ///   The MOS and the languages raise errors with BRK: an error number and a message, ending in a zero, follow it.
    ///  </para>
    /// </remarks>
    public string? Trap(ushort address)
    {
        if (Peek(address) != BrkOpcode) { return null; }

        // BASIC's own messages hold its keywords as tokens, such as "No " then FN's; the MOS's and the DFS's are text.
        bool basic = address is >= 0x8000 and < 0xC000 && BasicPagedIn;
        System.Text.StringBuilder message = new();
        for (int at = address + 2; at < address + 2 + 255 && Peek((ushort)at) is byte value and not 0; at++)
        {
            if (basic && BasicDialect.BbcBasic.Keyword(value) is { Length: > 0 } word) { message.Append(word); }
            else { message.Append(value is >= 0x20 and < 0x7F ? (char)value : '?'); }
        }

        return $"BRK at ${address:X4}: error {Peek((ushort)(address + 1))}, \"{message}\".";
    }

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) is not BbcMemoryArea.Ram and not BbcMemoryArea.None;

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address is not RAM.</exception>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address)) { throw new ArgumentException($"${address:X4} is not RAM."); }
        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) == BbcMemoryArea.Ram;

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || address + bytes.Length > _machine.Bus.Ram.Length)
        {
            throw new ArgumentException($"Program must fit in RAM, $0000-${_machine.Bus.Ram.Length - 1:X4}.");
        }

        _machine.Bus.Load((ushort)address, bytes);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The MOS debugs against <c>Mos.asm</c>, BASIC II against <c>BbcBasic.asm</c> and DNFS 1.20 against
    ///   <c>Dnfs.asm</c>, each when the ROM fitted is the one its source builds. A paged ROM's module belongs to its
    ///   socket.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sdk = BbcSdkModules.SdkDirectory(directory);
        if (!File.Exists(Path.Join(sdk, "Mos.asm"))) { return; }
        if (BbcSdkModules.IsMos(_machine.Bus.MosRom))
        {
            debug.Add(new SourceMapModule(BbcSdkModules.AssembleMos(sdk), BbcMemoryArea.Mos));
        }

        for (int socket = 0; socket < BbcRoms.Sockets; socket++)
        {
            ReadOnlySpan<byte> rom = _machine.Bus.SocketRom(socket);
            BbcMemoryArea area = BbcMemoryArea.PagedRom0 + socket;
            if (BbcSdkModules.IsBasic(rom))
            {
                Assembler.AssemblyResult basic = BbcSdkModules.AssembleBasic(sdk);
                debug.Add(new SourceMapModule(basic, area));
                SetBasic(basic, socket);
            }
            else if (BbcSdkModules.IsDnfs(rom))
            {
                debug.Add(new SourceMapModule(BbcSdkModules.AssembleDnfs(sdk), area));
            }
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As <see cref="BbcKeyboard.Type"/> takes them: <c>$87</c> COPY, <c>$88-$8B</c> the cursor keys and
    ///   <c>$F0-$F9</c> the function keys.
    ///  </para>
    /// </remarks>
    public bool Key(int code) => _machine.Keyboard.Type((byte)code);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BREAK: the CPU and the user VIA reset, and RAM is kept.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        _machine.PressBreak();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stop is at the MOS's first instruction, where the reset vector points.
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
            ["machine"] = DebugMachines.Bbc,
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
        _machine.Video.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        bool modelB = _machine.Model == BbcModel.ModelB;
        return
        [
            new("model", "BBC Micro", ModelName, "The launch's model: bbcb or bbca."),
            new("cpu", "Processor", "6502 at 2 MHz", "Slowed to 1 MHz for the 1 MHz bus and most of SHEILA."),
            new(
                "rom",
                "ROMs",
                RomText(),
                "The dumps in romDirectory or RETROCORE_BBC_ROMS; without them, built from the SDK's sources."),
            new("memory", "Memory", modelB ? "32 KB" : "16 KB", "The Model B has 32 KB, the Model A 16 KB."),
            new("video", "Video", "6845 CRTC, video ULA and SAA5050 teletext", "Modes 0-7."),
            new("sound", "Sound", "SN76489", "Three tones and noise, through the internal speaker."),
            new(
                "cassette",
                "Cassette",
                "Cassette recorder",
                "The serial ULA's cassette port, at 1200 or 300 baud.",
                [_machine.Cassette.Id]),
            new(
                "disk",
                "Disk interface",
                _machine.Bus.DiskController is not null ? "Intel 8271, two drives" : "none",
                "The launch's diskInterface option, on by default on the Model B.",
                _machine.Drives.Count != 0 ? [.. _machine.Drives.Select(drive => drive.Id)] : null)
        ];
    }

    private string ModelName => _machine.Model == BbcModel.ModelA ? "Model A" : "Model B";

    // The ROMs' row: the MOS, then the paged ROMs by socket.
    private string RomText()
    {
        List<string> names = [BbcSdkModules.IsMos(_machine.Bus.MosRom) ? "MOS 1.20" : "MOS"];
        for (int socket = BbcRoms.Sockets - 1; socket >= 0; socket--)
        {
            ReadOnlySpan<byte> rom = _machine.Bus.SocketRom(socket);
            if (BbcSdkModules.IsBasic(rom)) { names.Add("BASIC II"); }
            else if (BbcSdkModules.IsDnfs(rom)) { names.Add("DNFS 1.20"); }
            else if (!rom.IsEmpty) { names.Add($"ROM in socket {socket}"); }
        }

        return string.Join(", ", names) + (SdkRoms ? ", from the SDK's sources" : "");
    }

    // off attaches no sink; speaker hears the SN76489, in stereo.
    private void SetSound(string mode)
    {
        BbcAudio audio = _machine.Audio;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 2, audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        audio.Sink = _sound;
        _soundMode = mode;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Video.Width,
        ["height"] = _machine.Video.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Video.Render(_pixels, scanned);
        DebugScreens.Show(_pixels, _screen);
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(_pixels);
        return frame;
    }
}
