// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Isa;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  The Apple III as the debugger sees it: a 6502, banked memory, the screen, the keyboard and four drives.
/// </summary>
/// <remarks>
///  <para>
///   Memory views and references can name a bank: <c>system</c>, <c>bank0</c> on up, <c>rom</c>, or an X-byte from
///   <c>x80</c> to <c>x8F</c> for the 64K that X-byte reaches, as SOS writes an extended address. A breakpoint on
///   <c>bank2:$2000</c> stops only while bank 2 is switched in.
///  </para>
/// </remarks>
internal sealed partial class Apple3DebugTarget : IDebugTarget
{
    private const byte BrkOpcode = 0x00;
    private const byte JsrOpcode = 0x20;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly Apple3Machine _machine;
    private PascalRuntime? _pascal;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;

    // The monitor the video is shown on: color, or monochrome in its phosphor's color by each pixel's brightness.
    private string _screen = DebugScreens.Color;
    private DebugAudioSink? _sound;
    private bool _resetPending;
    private SosDriverModules? _sosDrivers;

    /// <summary>
    ///  Creates the target for a launched Apple III.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Apple3DebugTarget(Apple3Machine machine)
    {
        _machine = machine;
        Apple3Bus bus = machine.Bus;
        _calls = new(() => bus.StackOffset, (page, offset) => bus.Ram[page + offset]);
        _pixels = new byte[machine.Video.Width * machine.Video.Height * 4];
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/video"] = args => VideoFrame(args.Bool("scanned") ?? false),
            ["apple3/disk"] = _ => DiskState(),
            ["apple3/sound"] = args =>
            {
                SetSound(args.String("mode") ?? throw new ArgumentException("mode is required."));
                return new JsonObject { ["mode"] = _sound is null ? "off" : "speaker" };
            },
            ["apple3/button"] = args =>
            {
                int button = args.Int("button") ?? throw new ArgumentException("button is required.");
                bool pressed = args.Bool("pressed") ?? throw new ArgumentException("pressed is required.");
                Apple3Modifiers key = button == 0 ? Apple3Modifiers.OpenApple : Apple3Modifiers.SolidApple;
                machine.Bus.Modifiers = pressed ? machine.Bus.Modifiers | key : machine.Bus.Modifiers & ~key;
                return new JsonObject { ["button"] = button, ["pressed"] = pressed };
            },
            ["apple3/fastDisk"] = args =>
            {
                FastDisk = args.Bool("enabled") ?? throw new ArgumentException("enabled is required.");
                return new JsonObject { ["fastDisk"] = FastDisk };
            }
        };
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal Apple3Machine Machine => _machine;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>SOS.INTERP</c> loads below the SOS kernel, in the bank switched in at <c>$2000-$9FFF</c> and above.
    ///  </para>
    /// </remarks>
    public PascalRuntime? Pascal => _pascal ??= new PascalRuntime(
        "Apple III Pascal",
        new Apple3PascalMemory(_machine.Bus),
        _machine.Bus.Peek,
        [],
        (0x2000, 0xC000),
        extended: true,
        () => (ushort)(_machine.Bus.ZeroPage << 8),
        () => _machine.Drives.Select(drive => drive.Disk).OfType<WozDisk>(),
        () => CycleCount);

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while a drive's motor turns.
    /// </summary>
    internal bool FastDisk { get; set; } = true;

    /// <summary>
    ///  Gets the directory of the SDK's Apple III sources the launch named, or null for the copy beside the host.
    /// </summary>
    internal string? SdkRoms { get; init; }

    /// <summary>
    ///  Gets whether the boot ROM is the SDK's build, so its source applies; a dump of the same ROM also matches it.
    /// </summary>
    internal bool RomMatchesSource { get; init; } = true;

    /// <inheritdoc/>
    public string ThreadName => "Apple III 6502";

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
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The III's clock changes with the environment register and the beam, so pacing uses the 1.4 MHz the Service
    ///   Reference Manual gives as its average.
    ///  </para>
    /// </remarks>
    public int ClockHertz => 1_400_000;

    /// <inheritdoc/>
    public bool Accelerated => FastDisk && _machine.Drives.Any(drive => drive.Head.Motor);

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x2000;

    /// <inheritdoc/>
    public Enum ProgramArea => Apple3MemoryArea.Bank0;

    /// <inheritdoc/>
    public string ContractModel => "Apple3";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "X", "Y"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Zero page", 0, 256);

    /// <inheritdoc/>
    public IReadOnlyList<DebugMemoryBank> Banks => field ??= CreateBanks();

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<Machines.Devices.IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.ReadArea(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack pointer points into the stack page, which the debugger shows as page one.
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
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address) =>
        Peek(address) == JsrOpcode ? ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A BRK traps unless it is an SOS call: see <see cref="SosCalls"/>. SOS's debug call, <c>BRK $FE</c>, traps
    ///   too, since a program makes it to be stopped.
    ///  </para>
    /// </remarks>
    public string? Trap(ushort address)
    {
        if (Peek(address) != BrkOpcode) { return null; }
        byte zeroPage = _machine.Bus.ZeroPage;
        byte number = Peek((ushort)(address + 1));
        return zeroPage != SosCalls.CallerZeroPage
            ? $"BRK at ${address:X4}, with zero page at ${zeroPage:X2}00 rather than an SOS caller's ${SosCalls.CallerZeroPage:X2}00."
            : number == SosCalls.DebugCall
                ? $"SOS debug call (BRK ${number:X2}) at ${address:X4}."
                : SosCalls.Name(number) is null ? $"BRK at ${address:X4}: ${number:X2} is not an SOS call." : null;
    }

    /// <inheritdoc/>
    public (string Name, byte Number)? SystemCall(ushort address)
    {
        if (Peek(address) != BrkOpcode || _machine.Bus.ZeroPage != SosCalls.CallerZeroPage) { return null; }
        byte number = Peek((ushort)(address + 1));
        return SosCalls.Name(number) is { } name ? (name, number) : null;
    }

    /// <inheritdoc/>
    public string? DescribeSystemCall(ushort address) =>
        SystemCall(address) is { } call ? SosCalls.Describe(call.Number, address, ReadFar) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Extended addressing applies above the zero page; with X-byte 0, or below $0100, the address is as mapped now.
    ///  </para>
    /// </remarks>
    public byte PeekFar(byte xByte, ushort address) => ReadFar(xByte, address);

    /// <inheritdoc/>
    public void PokeFar(byte xByte, ushort address, byte value)
    {
        if ((xByte & 0x80) != 0 && address >= 0x100)
        {
            _machine.Bus.Ram[_machine.Bus.ExtendedOffset(xByte, address)] = value;
        }
        else
        {
            Poke(address, value);
        }
    }

    // Reads through an X-byte, as extended addressing does above the zero page, or with X-byte 0 as mapped now.
    private byte ReadFar(byte xByte, ushort address) =>
        (xByte & 0x80) != 0 && address >= 0x100 ? _machine.Bus.Ram[_machine.Bus.ExtendedOffset(xByte, address)] : Peek(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   What plays the ROM's part: the boot ROM, SOS's kernel from $B800 up, and Business BASIC's interpreter, from
    ///   $5200, while it is in memory. Invokable modules and drivers, in the switchable banks, are machine code: below
    ///   <c>$A000</c> the interpreter counts only while its own bank is in the window, not a module's that PERFORM or
    ///   EXFN switched in.
    ///  </para>
    /// </remarks>
    public bool InRom(ushort address) => ReadArea(address) is Apple3MemoryArea.Rom
        || address >= SosKernelStart
        || (address is >= Apple3SdkModules.BusinessBasicOrigin and < BusinessBasicEnd
            && BusinessBasicActive
            && (address >= SwitchableEnd || BusinessBasicInWindow));

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address reads ROM, I/O or nothing.</exception>
    public void Poke(ushort address, byte value)
    {
        Apple3Bus bus = _machine.Bus;
        if (bus.ReadArea(address) is Apple3MemoryArea.Rom or Apple3MemoryArea.Io or Apple3MemoryArea.Vias or Apple3MemoryArea.None)
        {
            throw new ArgumentException($"${address:X4} reads {bus.ReadArea(address)} now, not RAM.");
        }

        bus.Ram[bus.RamOffset(address)] = value;
    }

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0x0200 || address + bytes.Length > 0xC000)
        {
            throw new ArgumentException("A program must fit in RAM, $0200-$BFFF.");
        }

        for (int i = 0; i < bytes.Length; i++) { Poke((ushort)(address + i), bytes[i]); }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The boot ROM's source, <c>BootRom.asm</c>, applies where the ROM is mapped. SOS 1.3's kernel,
    ///   <c>Sos/SosKernel.asm</c>, applies wherever memory holds its bytes: the loader and INIT while they run, and
    ///   the rest of the kernel in the system bank once the loader has moved it there. Business BASIC 1.23's
    ///   interpreter, <c>BusinessBasic/BusinessBasic.asm</c>, applies where SOS loaded it, at <c>$5200</c> in the bank
    ///   the window shows while it runs.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string roms = Apple3SdkModules.Directory(directory ?? SdkRoms);
        string path = Path.Join(roms, "BootRom.asm");
        if (RomMatchesSource && File.Exists(path))
        {
            debug.Add(new SourceMapModule(Apple3SdkModules.AssembleBootRom(path), Apple3MemoryArea.Rom));
        }

        // The bootstrap loader runs from $A000, where the boot ROM reads block 0: Apple's, the System Demo's copy, or
        // On Three's revision.
        string boot = Path.Join(roms, "Sos", "SosBoot.asm");
        if (File.Exists(boot))
        {
            foreach (string symbol in (ReadOnlySpan<string>)["", "SYSTEM_DEMO", "ON_THREE"])
            {
                debug.Add(new SourceMapModule(Apple3SdkModules.AssembleSosBoot(boot, symbol), area: null));
            }
        }

        string kernel = Path.Join(roms, "Sos", "SosKernel.asm");
        if (File.Exists(kernel))
        {
            AssemblyResult sos = Apple3SdkModules.AssembleSosKernel(kernel);
            debug.Add(new SourceMapModule(sos, area: null));
            _sosDrivers = new SosDriverModules(_machine.Bus, sos, Path.Join(roms, "Sos", "Drivers"));
        }

        // Business BASIC runs where SOS loaded it, at $5200 in the bank the window shows while it runs.
        string basic = Path.Join(roms, "BusinessBasic", "BusinessBasic.asm");
        if (File.Exists(basic))
        {
            AssemblyResult business = Apple3SdkModules.AssembleBusinessBasic(basic);
            debug.Add(new SourceMapModule(business, area: null));
            AddBusinessBasic(business);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   SOS's drivers map to the SDK's sources as SOS loads them.
    ///  </para>
    /// </remarks>
    public bool AddLoadedModules(DebugInfo debug) => _sosDrivers?.Scan(debug) ?? false;

    /// <inheritdoc/>
    public bool Key(int code)
    {
        _machine.Bus.QueueKey((byte)code);
        return true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   CONTROL-RESET: the processor and the devices a reset reaches restart, keeping RAM and the VIAs.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        // In Apple II emulation CONTROL-RESET is an NMI, and the processor is not reset.
        if (_machine.Bus.AppleIIMode)
        {
            _machine.PressReset(control: true);
            return;
        }

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
        _machine.Bus.Audio.Flush();
        return _sound.Take() is { } samples
            ? new JsonObject { ["rate"] = _sound.SampleRate, ["channels"] = _sound.Channels, ["samples"] = samples }
            : null;
    }

    /// <summary>
    ///  Turns the sound on or off: <c>speaker</c> mixes the speaker and the DAC, in mono.
    /// </summary>
    /// <param name="mode">off or speaker.</param>
    internal void SetSound(string mode)
    {
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, _machine.Bus.Audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        _machine.Bus.Audio.Sink = _sound;
    }

    /// <inheritdoc/>
    public void DeviceAction(Machines.Devices.IDevice device, string action, JsonObject args)
    {
        switch (device, action)
        {
            case (Apple2FloppyDrive drive, "insert"):
                string path = Path.GetFullPath(args.String("path") ?? throw new ArgumentException("path is required."));
                drive.Eject();
                Apple2Loader.Insert(drive, path);
                break;
            case (Apple2FloppyDrive drive, "eject"):
                drive.Eject();
                break;
            case (Apple2FloppyDrive drive, "writeProtect"):
                drive.SetWriteProtected(args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required."));
                break;
            case (ProFileDrive drive, "insert"):
                ProFileMedia.Insert(drive, args.String("path") ?? throw new ArgumentException("path is required."));
                break;
            case (ProFileDrive drive, "eject"):
                drive.Eject();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("apple3/disk", DiskState());
    }

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running)
    {
        string[] rows = _machine.ReadTextScreen();
        return new JsonObject
        {
            ["machine"] = DebugMachines.Apple3,
            ["model"] = "Apple III",
            ["columns"] = rows[0].Length,
            ["rows"] = rows.ToJsonArray(),
            ["scanline"] = _machine.Line,
            ["cycles"] = CycleCount,
            ["video"] = VideoState(),
            ["disk"] = DiskState(),
            ["sound"] = _sound is null ? "off" : "speaker",
            ["fastDisk"] = FastDisk,
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
        Apple3Bus bus = _machine.Bus;
        return
        [
            new("model", "Apple III", "6502A at 1 or 2 MHz", "The main board's processor, 1.4 MHz on average with the screen on."),
            new(
                "memory",
                "Memory",
                $"{bus.RamKilobytes} KB, {bus.SwitchableBanks} switchable banks",
                "The launch's ramKilobytes option: 128, 256 (the default) or 512."),
            new("rom", "Boot ROM", RomMatchesSource ? "Apple III boot ROM" : "dump", "Diagnostics, then SOS from the built-in drive."),
            new(
                "disk",
                "Disk controller",
                "built in, four drives",
                "The built-in drive, .D1, and three external ones, .D2-.D4: the launch's disks option.",
                [.. _machine.Drives.Select(drive => drive.Id)]),
            new(
                "environment",
                "Environment register",
                bus.AppleIIMode ? $"${bus.Environment:X2}, Apple II mode" : $"${bus.Environment:X2}",
                "VIA 0 port A: 1 MHz, I/O, video, reset, write protection, the primary stack and the ROM. Apple II mode, "
                    + "set by the Apple II Emulation disk, hides the VIAs, so only turning the machine off leaves it."),
            Slot(1),
            Slot(2),
            Slot(3),
            Slot(4)
        ];
    }

    // A slot: its ProFile card and the ProFile cabled to it, or empty.
    private HardwareRow Slot(int slot)
    {
        if (_machine.Bus.ProFileIn(slot) is not { } card)
        {
            return HardwareRow.Empty(
                slot,
                "Add Card puts a ProFile interface card here; so does the launch's proFiles.",
                free: true);
        }

        return new(
            $"slot{slot}",
            $"Slot {slot}",
            "ProFile interface card",
            "Apple's ProFile hard disk, which SOS reaches through the .PROFILE driver in SOS.DRIVER (the System "
                + "Utilities disk's is set for slot 4). Insert a .po or .hdv image of a SOS volume, up to 65535 blocks; "
                + ".PROFILE as Apple shipped it uses the first 9728. The launch's proFiles installs it; Remove Card takes "
                + "it out.",
            [card.Drive.Id],
            ["removeCard"]);
    }

    /// <inheritdoc/>
    public void HardwareAction(string id, string action, JsonObject args)
    {
        int slot = id is ['s', 'l', 'o', 't', >= '1' and <= '4' and var digit] ? digit - '0' : 0;
        switch (action)
        {
            case "addProFile" when slot != 0 && _machine.Bus.ProFileIn(slot) is null:
                _machine.Bus.InstallProFile(slot);
                break;
            case "removeCard" when slot != 0 && _machine.Bus.ProFileIn(slot) is not null:
                _machine.Bus.RemoveProFile(slot);
                break;
            default:
                throw new ArgumentException($"The {id} hardware does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public JsonObject? Cards()
    {
        JsonObject cards = [];
        for (int slot = 1; slot <= 4; slot++)
        {
            cards[$"{slot}"] = _machine.Bus.ProFileIn(slot) is null ? "empty" : "proFile";
        }

        return cards;
    }

    /// <inheritdoc/>
    public IEnumerable<string> RestoreCards(JsonObject cards)
    {
        List<string> problems = [];
        foreach ((string key, JsonNode? node) in cards)
        {
            string? card = node?.GetValueKind() == System.Text.Json.JsonValueKind.String ? node.GetValue<string>() : null;
            if (!int.TryParse(key, out int slot) || slot is < 1 or > 4 || card is not ("proFile" or "empty"))
            {
                problems.Add($"Slot {key} cannot take the saved card '{node}'.");
                continue;
            }

            bool installed = _machine.Bus.ProFileIn(slot) is not null;
            if (card == "proFile" && !installed) { _machine.Bus.InstallProFile(slot); }
            if (card == "empty" && installed) { _machine.Bus.RemoveProFile(slot); }
        }

        return problems;
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
        return new JsonObject
        {
            ["width"] = _machine.Video.Width,
            ["height"] = _machine.Video.Height,
            ["pixelFormat"] = "rgba",
            ["pixels"] = Convert.ToBase64String(_pixels),
            ["cycles"] = CycleCount
        };
    }

    private JsonObject DiskState() => new JsonObject
    {
        ["dataLatch"] = _machine.Bus.Disk.DataLatch,
        ["writeMode"] = _machine.Bus.Disk.WriteMode,
        ["drives"] = _machine.Drives.Select(drive =>
        {
            DiskDriveState state = _machine.Bus.Disk.State(drive.Drive);
            return new JsonObject
            {
                ["drive"] = drive.Drive,
                ["path"] = drive.Media?.Label,
                ["quarterTrack"] = state.QuarterTrack,
                ["track"] = state.QuarterTrack / 4.0,
                ["motor"] = state.Motor,
                ["mounted"] = state.Mounted,
                ["writeProtected"] = state.WriteProtected,
                ["dirty"] = state.Dirty
            };
        }).ToJsonArray()
    };

    private List<DebugMemoryBank> CreateBanks()
    {
        Apple3Bus bus = _machine.Bus;
        int system = bus.Ram.Length - 0x8000;
        List<DebugMemoryBank> banks =
        [
            new(
                "system",
                "System bank",
                [Apple3MemoryArea.SystemBank],
                [(0x0000, 0x2000), (0xA000, 0x6000)],
                address => bus.Ram[system + (address < 0x2000 ? address : address - 0x8000)],
                (address, value) =>
                {
                    bus.Ram[system + (address < 0x2000 ? address : address - 0x8000)] = value;
                    return true;
                })
        ];

        for (int bank = 0; bank < bus.SwitchableBanks; bank++)
        {
            int offset = bank * 0x8000;
            banks.Add(new(
                $"bank{bank}",
                bank == 0 ? "Bank 0 (graphics)" : $"Bank {bank}",
                [Apple3MemoryArea.Bank0 + bank],
                [(0x2000, 0x8000)],
                address => bus.Ram[offset + address - 0x2000],
                (address, value) =>
                {
                    bus.Ram[offset + address - 0x2000] = value;
                    return true;
                }));
        }

        banks.Add(new(
            "rom",
            "Boot ROM",
            [Apple3MemoryArea.Rom],
            [(0xF000, 0x1000)],
            address => RomByte(address),
            Poke: null));

        // The 64K an X-byte reaches, from $0100: SOS's extended addresses, such as x81:$3000.
        for (int xByte = 0x80; xByte <= 0x8F; xByte++)
        {
            byte value = (byte)xByte;
            banks.Add(new(
                $"x{xByte:x2}",
                $"Extended addressing, X-byte ${xByte:X2}",
                [Apple3MemoryArea.SystemBank],
                [(0x0100, 0xFF00)],
                address => bus.Ram[bus.ExtendedOffset(value, address)],
                (address, data) =>
                {
                    bus.Ram[bus.ExtendedOffset(value, address)] = data;
                    return true;
                }));
        }

        return banks;
    }

    // The boot ROM's byte, whether or not the ROM is mapped in now.
    private byte? RomByte(ushort address)
    {
        Apple3Bus bus = _machine.Bus;
        return bus.Rom[address - 0xF000];
    }

    /// <summary>
    ///  Launches an Apple III from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The boot ROM is <c>apple3.rom</c> in <c>romDirectory</c> (or <c>RETROCORE_APPLE3_ROMS</c>), MAME's name, or
    ///   without it the SDK's <c>BootRom.asm</c>, which is byte-identical to it. The disk sequencer is
    ///   <c>341-0028-a.rom</c> there, or the SDK's Disk II <c>Sequencer16.asm</c>, the same chip.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, at power-on.</returns>
    /// <exception cref="ArgumentException">An argument is invalid.</exception>
    internal static Apple3DebugTarget Launch(JsonObject args)
    {
        int ram = args.Int("ramKilobytes") ?? 256;
        if (ram is not (128 or 256 or 512)) { throw new ArgumentException("ramKilobytes must be 128, 256 or 512."); }

        string? sdk = args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null;
        string? dumps = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_APPLE3_ROMS");
        string? romPath = dumps is null ? null : Path.Join(dumps, Apple3Roms.BootRomFile);
        string? sequencerPath = dumps is null ? null : Path.Join(dumps, Apple3Roms.SequencerFile);
        if (romPath is not null && !File.Exists(romPath))
        {
            throw new ArgumentException($"{romPath} is missing; romDirectory needs MAME's apple3 set.");
        }

        // The Disk II's sources sit beside the Apple III's in the SDK.
        string sources = Apple3SdkModules.Directory(sdk);
        string? root = Path.GetDirectoryName(sources);
        byte[] rom = romPath is not null
            ? File.ReadAllBytes(romPath)
            : Apple3SdkModules.AssembleBootRom(Path.Join(sources, "BootRom.asm")).Sections[0].Bytes.ToArray();

        // A launch can name the repository's Apple III folder, which has no Disk II sources beside it; the host's
        // copy has them.
        string sequencerSource = SdkModules.DiskIIPath("Sequencer16.asm", root);
        if (!File.Exists(sequencerSource)) { sequencerSource = SdkModules.DiskIIPath("Sequencer16.asm"); }
        byte[] sequencer = sequencerPath is not null && File.Exists(sequencerPath)
            ? File.ReadAllBytes(sequencerPath)
            : SdkModules.AssembleDiskII(sequencerSource, origin: 0).Sections[0].Bytes.ToArray();

        Apple3Machine machine = new(new Apple3Roms(rom, sequencer), ram);

        // The reset sequence runs to the first instruction, the reset vector's target, where a breakpoint can stop.
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        Apple3DebugTarget target = new(machine)
        {
            SdkRoms = sdk,
            FastDisk = args.Bool("fastDisk") ?? true
        };

        target.SetSound(args.String("sound") ?? "speaker");
        foreach ((int slot, string? image) in ProFileMedia.LaunchCards(args, "1 to 4"))
        {
            target.HardwareAction($"slot{slot}", "addProFile", []);
            if (image is not null && machine.Bus.ProFileIn(slot) is { } card)
            {
                ProFileMedia.Insert(card.Drive, image);
            }
        }

        if (args["disks"] is JsonArray disks)
        {
            if (disks.Count > machine.Drives.Count) { throw new ArgumentException("The Apple III has four drives."); }
            for (int drive = 0; drive < disks.Count; drive++)
            {
                if (disks[drive] is JsonValue value && value.GetValue<string>() is { } disk)
                {
                    Apple2Loader.Insert(machine.Drives[drive], Path.GetFullPath(disk));
                }
            }
        }

        return target;
    }
}
