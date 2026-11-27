// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using Retrocore.Machines;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The Commodore VIC-20 as the debugger sees it: a 6502, BASIC and the kernal, the VIC's screen and sound, the
///  keyboard, the Datasette, a cartridge, and 1540 and 1541 drives on the serial bus.
/// </summary>
internal sealed partial class Vic20DebugTarget : IDebugTarget
{
    /// <summary>
    ///  The key code for RESTORE, which interrupts through VIA 1's CA1, the NMI.
    /// </summary>
    internal const int RestoreKey = 256;

    /// <summary>
    ///  The key code for RUN/STOP and RESTORE together, the kernal's warm start: back to BASIC's READY, or with a
    ///  cartridge in, to the cartridge's warm start.
    /// </summary>
    internal const int StopRestoreKey = 257;

    /// <summary>
    ///  The key code for SHIFT and the Commodore key together, which switch the characters between the upper-case
    ///  and graphics set and the lower-case one.
    /// </summary>
    internal const int CommodoreShiftKey = 258;

    private const byte JsrOpcode = 0x20;
    private const byte BrkOpcode = 0x00;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly Vic20Machine _machine;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;
    private readonly Vic20CharacterSet _characters;
    private string _screen = DebugScreens.Color;
    private bool _resetPending;
    private DebugAudioSink? _sound;
    private string _soundMode = "off";

    // A key that types no character, held down until the cycle count reaches the release.
    private int _held;
    private ulong _releaseAt;

    /// <summary>
    ///  Creates the target for a launched VIC-20.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Vic20DebugTarget(Vic20Machine machine)
    {
        _machine = machine;
        _calls = new(machine.Bus.Peek);
        _pixels = new byte[machine.Vic.Width * machine.Vic.Height * 4];
        _characters = new(machine);
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
    internal Vic20Machine Machine => _machine;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the Datasette's motor runs with a key down.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the ROMs were built from the SDK's sources rather than loaded from dumps.
    /// </summary>
    internal bool SdkRoms { get; set; }

    /// <summary>
    ///  Gets or sets the cartridge's files, as the launch named them, for the Machine view.
    /// </summary>
    internal string? CartridgeName { get; set; }

    /// <inheritdoc/>
    public string ThreadName => _machine.Standard == VicVideoStandard.Ntsc ? "VIC-20 6502" : "VIC-20 (PAL) 6502";

    /// <inheritdoc/>
    public string Cpu => nameof(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6502Isa.Get(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public ICharacterSet? CharacterSet => _characters;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => M6502Frames.Of(_machine.Processor.Registers);

    /// <inheritdoc/>
    public int StackPointer => _machine.Processor.Registers.StackPointer;

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
    public bool IsTakingInterrupt => _machine.Processor.IsTakingInterrupt;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   S is a byte: the stack is page one.
    ///  </para>
    /// </remarks>
    public int StackMask => 0xFF;

    /// <inheritdoc/>
    public bool InInstruction => _machine.Processor.CurrentOpCode is not null;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   1,022,727 Hz on NTSC and 1,108,404 Hz on PAL, rounded to a whole hertz.
    ///  </para>
    /// </remarks>
    public int ClockHertz => (int)Math.Round(_machine.CpuHertz);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine runs as fast as it can while the Datasette plays or records, unless the launch asks not to.
    ///  </para>
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Cassette.Activity != DeviceActivity.Idle;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>$1400</c> is the built-in RAM on every VIC-20, above where a small BASIC program ends and below the
    ///   unexpanded machine's screen at <c>$1E00</c>; with 8K or more in the expansion port, the screen moves down to
    ///   <c>$1000</c> and BASIC starts at <c>$1201</c>, still below it.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x1400;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   All RAM, the built-in 5K and the expansion's, as <see cref="ReadArea"/> reports it.
    ///  </para>
    /// </remarks>
    public Enum ProgramArea => Vic20MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Vic20";

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
    ///   The expansion's RAM reads as RAM, as the built-in 5K does, so a program loaded anywhere in RAM is in its
    ///   <see cref="ProgramArea"/>: on an expanded VIC-20 machine code usually lives in block 1, from <c>$2000</c>.
    ///  </para>
    /// </remarks>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address) switch
    {
        Vic20MemoryArea.ExpansionRam => Vic20MemoryArea.Ram,
        Vic20MemoryArea area => area
    };

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
        ReleaseWhenDue();
        ProcessorCycle cycle = _machine.LastCycle;
        if (cycle.IsOpcodeFetch && !cycle.IsStalled) { _returnedFromInterrupt = cycle.Value == RtiOpcode; }
        _calls.Observe(cycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public void RunCycles(int cycles)
    {
        for (int count = 0; count < cycles; count++)
        {
            _machine.StepCycle();
            ReleaseWhenDue();
        }

        _calls.Reset();
        _returnedFromInterrupt = false;
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
    ///   A BRK goes through the kernal's CBINV vector at <c>$0316</c>, which points at the warm start that RUN/STOP and
    ///   RESTORE take.
    ///  </para>
    /// </remarks>
    public string? Trap(ushort address) => Peek(address) == BrkOpcode ? $"BRK at ${address:X4}." : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC's CHRGET, which BASIC copies into page zero and runs there, counts as BASIC's: Step Into on SYS stops in
    ///   the machine code SYS calls, not in the CHRGET that fetches its address. A cartridge is the program being
    ///   debugged, not ROM to step over.
    ///  </para>
    /// </remarks>
    public bool InRom(ushort address) =>
        _machine.Bus.Area(address) is Vic20MemoryArea.Basic or Vic20MemoryArea.Kernal || InChrget(address);

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address is not RAM.</exception>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address))
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Colour RAM holds four bits; the high four of a byte written there are lost.
    ///  </para>
    /// </remarks>
    public bool CanPoke(ushort address) =>
        _machine.Bus.Area(address) is Vic20MemoryArea.Ram or Vic20MemoryArea.ExpansionRam or Vic20MemoryArea.ColourRam;

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address is < 0 or > ushort.MaxValue || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("Program must fit in the address space.");
        }

        _machine.Bus.Load((ushort)address, bytes);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC and the kernal debug against <c>Vic20/Basic.asm</c> and <c>Vic20/Kernal.asm</c> when the machine's ROMs
    ///   are their builds for its video standard: BASIC from <c>$C000</c> through its end in the kernal chip at
    ///   <c>$E47B</c>, the kernal from <c>$E47C</c>.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sdk = SdkDirectory(directory);
        if (!File.Exists(Path.Join(sdk, "Basic.asm"))) { return; }
        VicVideoStandard standard = _machine.Standard;
        Assembler.AssemblyResult basic = Vic20SdkModules.AssembleBasic(sdk, standard);
        if (Matches(basic.Sections[0].Bytes.Span, Vic20SdkModules.BasicOrigin))
        {
            // BASIC's last part is in the kernal's chip, so the module is not tied to BASIC's area; nothing but these
            // ROMs answers from $C000 to $E47B, and their bytes were just matched.
            debug.Add(new SourceMapModule(basic, area: null, collapseSingleStatementMacros: true));
            SetBasicSymbols(basic.SymbolsWithHistoricalNames);
        }

        Assembler.AssemblyResult kernal = Vic20SdkModules.AssembleKernal(sdk, standard);
        if (Matches(kernal.Sections[0].Bytes.Span, Vic20SdkModules.KernalOrigin))
        {
            debug.Add(new SourceMapModule(kernal, Vic20MemoryArea.Kernal));
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   PETSCII, as <see cref="Vic20Keyboard.Type(byte)"/> takes it: a letter of either case types its key
    ///   unshifted; 3 is RUN/STOP, 19 HOME, 147 CLR and 133-140 f1-f8. Above them, <see cref="RestoreKey"/>,
    ///   <see cref="StopRestoreKey"/> and <see cref="CommodoreShiftKey"/> hold keys that type nothing for a tenth of a
    ///   second.
    ///  </para>
    /// </remarks>
    public bool Key(int code)
    {
        if (code is >= 0 and <= 0xFF) { return _machine.Keyboard.Type((byte)code); }
        if (code is < RestoreKey or > CommodoreShiftKey) { return false; }
        Release();
        _held = code;
        _releaseAt = CycleCount + (ulong)(ClockHertz / 10);
        Hold(code, pressed: true);
        return true;
    }

    /// <inheritdoc/>
    public int MaximumKey => CommodoreShiftKey;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The VIC-20 has no reset button; this pulls the expansion port's reset line, as a reset switch on a cartridge
    ///   or expansion board does: the 6502, the VIAs and the drives on the serial bus reset, RAM is kept, and the
    ///   kernal starts again from its reset vector, starting a cartridge that signs itself.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        Release();
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary) { return false; }
        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Vic.FlushAudio();
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
        string[] rows = TextRows();
        return new JsonObject
        {
            ["machine"] = DebugMachines.Vic20,
            ["standard"] = VideoStandardId(_machine.Standard),
            ["columns"] = _machine.Vic.Columns,
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
        _machine.Vic.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        Vic20Machine machine = _machine;
        bool ntsc = machine.Standard == VicVideoStandard.Ntsc;
        return
        [
            new("video", "Video", ntsc ? "NTSC, the 6560" : "PAL, the 6561", "The launch's video option: ntsc or pal."),
            new(
                "cpu",
                "Processor",
                ntsc ? "6502 at 1.02 MHz" : "6502 at 1.11 MHz",
                "The board's processor, clocked from the VIC's crystal: NTSC's 14.318 MHz divided by 14, PAL's 4.434 MHz divided by 4."),
            new("rom", "ROM", RomText(), "The dumps in romDirectory or RETROCORE_VIC20_ROMS, under MAME's names; without them, built from the SDK's sources."),
            new("memory", "Memory", MemoryText(machine.Bus.Expansion), "The launch's ramExpansion option: none, 3k, 8k, 16k, 24k or 32k."),
            new("sound", "Sound", _soundMode == "off" ? "off" : "the VIC's four voices", "The launch's sound option: speaker plays the VIC's three tones and noise, as the TV does; off is silent."),
            new("cassette", "Cassette", "C2N Datasette", "The Datasette on the cassette port.", [machine.Cassette.Id]),
            new("cartridge", "Cartridge", CartridgeText(), "The launch's cartridge option: a MAME chip file, a .prg or a VICE .crt, or a list of chips."),
            .. DiskRows()
        ];
    }

    /// <summary>
    ///  Gets the launch configuration's <c>video</c> for a standard.
    /// </summary>
    /// <param name="standard">The standard.</param>
    /// <returns><c>ntsc</c> or <c>pal</c>.</returns>
    internal static string VideoStandardId(VicVideoStandard standard) => standard == VicVideoStandard.Ntsc ? "ntsc" : "pal";

    /// <summary>
    ///  Gets the directory of the VIC-20's ROM sources: a directory that holds them, its <c>Vic20</c> folder, or its
    ///  <c>Pet/Vic20</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        if (directory is null) { return Vic20SdkModules.RomDirectory; }
        if (File.Exists(Path.Join(directory, "Kernal.asm"))) { return directory; }
        string vic20 = Path.Join(directory, "Vic20");
        return Directory.Exists(vic20) ? vic20 : Path.Join(directory, "Pet", "Vic20");
    }

    // The memory a VIC-20 has with an expansion.
    private static string MemoryText(Vic20Expansion expansion)
    {
        int kilobytes = 5;
        List<string> blocks = [];
        if (expansion.HasFlag(Vic20Expansion.Ram3K))
        {
            kilobytes += 3;
            blocks.Add("3K at $0400");
        }

        foreach ((Vic20Expansion block, int number) in (ReadOnlySpan<(Vic20Expansion, int)>)
            [(Vic20Expansion.Block1, 1), (Vic20Expansion.Block2, 2), (Vic20Expansion.Block3, 3), (Vic20Expansion.Block5, 5)])
        {
            if (!expansion.HasFlag(block)) { continue; }
            kilobytes += 8;
            blocks.Add($"block {number}");
        }

        return blocks.Count == 0 ? "5 KB, unexpanded" : $"{kilobytes} KB: 5 KB and {string.Join(", ", blocks)}";
    }

    // Whether the machine's ROM at an address holds a build's bytes.
    private bool Matches(ReadOnlySpan<byte> image, int origin)
    {
        for (int i = 0; i < image.Length; i++)
        {
            if (_machine.Bus.Peek((ushort)(origin + i)) != image[i]) { return false; }
        }

        return true;
    }

    private string RomText()
    {
        string kernal = _machine.Standard == VicVideoStandard.Ntsc ? "901486-06" : "901486-07";
        return $"BASIC 2 and kernal {kernal}" + (SdkRoms ? ", from the SDK's sources" : "");
    }

    private string CartridgeText() => _machine.Bus.Cartridge is { } cartridge
        ? $"{CartridgeName ?? "a cartridge"}{(cartridge.Autostarts ? ", which starts itself" : "")}"
        : "empty";

    // The screen as text, each code as the character set the VIC shows reads it, graphics as spaces.
    private string[] TextRows()
    {
        Vic6560 vic = _machine.Vic;
        IVicMemory memory = _machine.Bus;
        int columns = vic.Columns;
        string[] rows = new string[vic.Rows];
        char[] line = new char[columns];
        for (int row = 0; row < rows.Length; row++)
        {
            for (int column = 0; column < columns; column++)
            {
                byte code = memory.FetchVideo((vic.ScreenAddress + (row * columns) + column) & 0x3FFF);
                char character = _characters.Character(code);
                line[column] = character == '\0' ? ' ' : character;
            }

            rows[row] = new string(line);
        }

        return rows;
    }

    // Presses or releases a key that types nothing.
    private void Hold(int code, bool pressed)
    {
        Vic20Keyboard keyboard = _machine.Keyboard;
        switch (code)
        {
            case RestoreKey:
                keyboard.Restore = pressed;
                break;
            case StopRestoreKey:
                keyboard.Set(Vic20Key.Stop, pressed);
                keyboard.Restore = pressed;
                break;
            case CommodoreShiftKey:
                keyboard.Set(Vic20Key.LeftShift, pressed);
                keyboard.Set(Vic20Key.Commodore, pressed);
                break;
        }
    }

    // Lets go of the key held down, if any.
    private void Release()
    {
        if (_held == 0) { return; }
        Hold(_held, pressed: false);
        _held = 0;
    }

    private void ReleaseWhenDue()
    {
        if (_held != 0 && CycleCount >= _releaseAt) { Release(); }
    }

    // off attaches no sink; speaker plays the VIC's stereo samples, as the TV's speaker plays them.
    private void SetSound(string mode)
    {
        Vic6560 vic = _machine.Vic;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 2, vic.SampleRate),
            _ => throw new ArgumentException("sound must be speaker or off.")
        };

        vic.AudioSink = _sound;
        _soundMode = mode;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Vic.Width,
        ["height"] = _machine.Vic.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Vic.Render(_pixels, scanned);
        DebugScreens.Show(_pixels, _screen);
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(_pixels);
        return frame;
    }
}
