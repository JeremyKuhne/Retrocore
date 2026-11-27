// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class Vic20DebugTarget
{
    /// <summary>
    ///  Launches a VIC-20 from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>video</c> is <c>ntsc</c> (the 6560, the default) or <c>pal</c> (the 6561). The ROMs are the dumps in
    ///   <c>romDirectory</c> (or <c>RETROCORE_VIC20_ROMS</c>) under MAME's names, in the directory or in its
    ///   <c>vic20</c> (NTSC) or <c>vic20p</c> (PAL) folder; without them, they are built from the SDK's sources.
    ///   <c>ramExpansion</c> is <c>none</c> (the default), <c>3k</c>, <c>8k</c>, <c>16k</c>, <c>24k</c> or <c>32k</c>
    ///   (3K and 24K).
    ///  </para>
    ///  <para>
    ///   <c>cartridge</c> is a file or a list of files: MAME's chip files (named for their address, such as
    ///   <c>.a0</c>), a <c>.prg</c> placed at its address, or a VICE <c>.crt</c>; a cartridge that signs itself
    ///   starts at power-on. <c>sound</c> is <c>speaker</c> (the default), the VIC's voices, or <c>off</c>; <c>cassette</c> puts a tape
    ///   (<c>.tap</c>, <c>.wav</c> or <c>.prg</c>) in the Datasette with PLAY down. <c>diskUnits</c>,
    ///   <c>diskModel</c> and <c>disks</c> connect 1541 or 1540 drives to the serial bus and put disks in them; see
    ///   <see cref="LaunchDisks"/>.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, through the reset sequence.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static Vic20DebugTarget Launch(JsonObject args)
    {
        VicVideoStandard standard = (args.String("video") ?? "ntsc") switch
        {
            "ntsc" => VicVideoStandard.Ntsc,
            "pal" => VicVideoStandard.Pal,
            _ => throw new ArgumentException("video must be ntsc or pal.")
        };

        Vic20Expansion expansion = (args.String("ramExpansion") ?? "none") switch
        {
            "none" => Vic20Expansion.None,
            "3k" => Vic20Expansion.Ram3K,
            "8k" => Vic20Expansion.Ram8K,
            "16k" => Vic20Expansion.Ram16K,
            "24k" => Vic20Expansion.Ram24K,
            "32k" => Vic20Expansion.Ram3K | Vic20Expansion.Ram24K,
            _ => throw new ArgumentException("ramExpansion must be none, 3k, 8k, 16k, 24k or 32k.")
        };

        // A blank romDirectory, as ${env:RETROCORE_VIC20_ROMS} gives when it is not set, names no dumps.
        string? directory = args.String("romDirectory");
        if (string.IsNullOrWhiteSpace(directory))
        {
            directory = Environment.GetEnvironmentVariable("RETROCORE_VIC20_ROMS");
        }

        bool sdkRoms = string.IsNullOrWhiteSpace(directory);
        string sdk = SdkDirectory(args.String("sdkRoms") is { } given ? Path.GetFullPath(given) : null);
        Vic20Roms roms;
        if (directory is null || sdkRoms)
        {
            roms = Vic20SdkModules.BuildRoms(standard, sdk);
        }
        else
        {
            string folder = DumpFolder(Path.GetFullPath(directory), standard);
            try
            {
                roms = Vic20Roms.LoadFromDirectory(folder, standard);
            }
            catch (FileNotFoundException exception)
            {
                throw new ArgumentException(
                    $"{Path.GetFileName(exception.FileName)} is missing; romDirectory needs MAME's {(standard == VicVideoStandard.Ntsc ? "vic20" : "vic20p")} ROM set.");
            }
        }

        (Vic20Cartridge? cartridge, string? cartridgeName) = LoadCartridge(args);
        Vic20Machine machine = new(roms, standard, expansion, cartridge);
        Vic20DebugTarget target = new(machine)
        {
            FastCassette = args.Bool("fastCassette") ?? true,
            SdkRoms = sdkRoms,
            CartridgeName = cartridgeName
        };

        target.SetSound(args.String("sound") ?? "speaker");

        // BASIC's page-zero addresses, which loading a program needs before the session adds the SDK's modules.
        if (File.Exists(Path.Join(sdk, "Basic.asm")))
        {
            target.SetBasicSymbols(Vic20SdkModules.AssembleBasic(sdk, standard).SymbolsWithHistoricalNames);
        }

        target.LaunchDisks(args, sdkRoms ? Environment.GetEnvironmentVariable("RETROCORE_VIC20_ROMS") : directory);
        if (args.String("cassette") is { } tape) { Insert(machine.Cassette, tape); }

        // Power-up's reset sequence takes seven cycles, after which the kernal's first instruction is next.
        machine.Run(7);
        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the kernal and BASIC set up their RAM.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * _machine.CpuHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <summary>
    ///  Loads a <c>.prg</c> file as the kernal's LOAD does. A BASIC program, one at BASIC's start on some VIC-20,
    ///  moves to this machine's start, is linked for it, and BASIC's pointers are set past it; <c>RUN</c> is typed when
    ///  asked. Any other is machine code, which starts at its entry.
    /// </summary>
    /// <param name="prg">The file's bytes.</param>
    /// <param name="run">Whether to run a BASIC program.</param>
    /// <param name="entry">The machine code's entry, or null for its first byte.</param>
    /// <exception cref="ArgumentException">The file is too short, or does not fit in RAM.</exception>
    internal void LoadPrg(ReadOnlySpan<byte> prg, bool run, int? entry)
    {
        if (prg.Length < 3) { throw new ArgumentException("A .prg file is its load address and at least a byte."); }
        int address = prg[0] | (prg[1] << 8);
        bool basic = address is 0x0401 or 0x1001 or 0x1201;
        (ushort start, _) = _machine.LoadProgram(prg);
        if (!basic)
        {
            ProgramCounter = checked((ushort)(entry ?? start));
            return;
        }

        if (run)
        {
            foreach (char key in "RUN\r") { Key(key); }
        }
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        if (device is CommodoreFloppyDrive drive)
        {
            DriveAction(drive, action, args);
            return;
        }

        if (device is not CommodoreDatasette deck)
        {
            throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }

        switch (action)
        {
            case "insert":
                Insert(deck, args.String("path") ?? throw new ArgumentException("path is required."));
                break;
            case "play":
                deck.Play();
                break;
            case "record":
                // RECORD over the tape in it at the head, or a blank one put in for it.
                if (deck.Tape is null) { deck.Insert(new CommodoreTape(), "Blank tape", "TAP", changed: true); }
                deck.Record();
                break;
            case "stop":
                deck.Stop();
                break;
            case "rewind":
                deck.Rewind();
                break;
            case "eject":
                deck.Eject();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    /// <summary>
    ///  Gets the Datasette, which a <c>basic</c> target's tape plays in.
    /// </summary>
    internal CommodoreDatasette BootDeck => _machine.Cassette;

    /// <summary>
    ///  Gets device 8's drive, which a <c>basic</c> target's disk boots from.
    /// </summary>
    /// <exception cref="InvalidOperationException">No drive is connected as 8.</exception>
    internal CommodoreFloppyDrive BootDiskDrive =>
        _machine.Disks.FirstOrDefault(unit => unit.Address == FirstDiskAddress)?.Drive
            ?? throw new InvalidOperationException("No disk drive is connected as device 8.");

    /// <summary>
    ///  Gets whether BASIC's screen shows its READY prompt on a line of its own.
    /// </summary>
    internal bool ShowsReady => _machine.ReadTextScreen().Any(line => line.TrimEnd() == "READY.");

    // The folder of a standard's chips: the directory, or its MAME set's folder.
    private static string DumpFolder(string directory, VicVideoStandard standard)
    {
        string set = Path.Join(directory, standard == VicVideoStandard.Ntsc ? "vic20" : "vic20p");
        return Directory.Exists(set) ? set : directory;
    }

    // The launch's cartridge, a file or a list of files, and its name for the Machine view.
    private static (Vic20Cartridge? Cartridge, string? Name) LoadCartridge(JsonObject args)
    {
        JsonNode? node = args["cartridge"];
        if (node is null || node.GetValueKind() == JsonValueKind.Null) { return (null, null); }
        string[] paths = node switch
        {
            JsonArray list => [.. list.Select(item => item?.GetValueKind() == JsonValueKind.String
                ? item.GetValue<string>()
                : throw new ArgumentException("cartridge lists file paths."))],
            JsonValue value when value.GetValueKind() == JsonValueKind.String => [value.GetValue<string>()],
            _ => throw new ArgumentException("cartridge is a file path or a list of them.")
        };

        if (paths.Length == 0) { return (null, null); }
        string[] full = [.. paths.Select(path => Path.GetFullPath(path))];
        try
        {
            return (Vic20Cartridge.Load(full), string.Join(", ", full.Select(Path.GetFileName)));
        }
        catch (Exception exception) when (exception is FileNotFoundException or DirectoryNotFoundException or InvalidDataException)
        {
            throw new ArgumentException($"The cartridge cannot be loaded: {exception.Message}");
        }
    }

    // Puts a tape in with PLAY down: a TAP image or WAV recording, which saves back to its file, or a program file
    // made into the tape SAVE would write, which saves only as another file. The tape is read before the one in the
    // Datasette comes out, so a file that cannot be read leaves it in.
    private static void Insert(CommodoreDatasette deck, string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        CommodoreTape tape;
        IImageCodec? codec;
        string format;
        if (Path.GetExtension(full).Equals(".prg", StringComparison.OrdinalIgnoreCase))
        {
            string name = Path.GetFileNameWithoutExtension(full);
            tape = CommodoreTapeBuilder.FromPrg(name.Length > 16 ? name[..16] : name, bytes);
            codec = null;
            format = "PRG";
        }
        else
        {
            CommodoreTapeCodec loaded;
            (tape, loaded) = CommodoreTapeCodec.Load(bytes);
            codec = loaded;
            format = loaded.Format;
        }

        deck.Eject();
        deck.Insert(tape, full, format);
        MediaActions.Register(tape, full, codec, bytes);
        deck.Play();
    }

    // retro/media: the Datasette's keys and tape, by device cassette, and the drives' disks, by device disk8 to disk11.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        string id = args.String("device") ?? "cassette";
        IDevice device = _machine.Devices.FirstOrDefault(candidate => candidate.Id == id)
            ?? throw new ArgumentException("device must be cassette or a disk drive, such as disk8.");

        // As retro/device does: the host saves and reverts, and keeps a changed disk or tape that leaves for Undo.
        if (MediaActions.Device(device, action, args, (what, with) => DeviceAction(device, what, with)) is { } answer)
        {
            return answer;
        }

        DeviceAction(device, action, args);
        return MediaState();
    }

    private JsonObject MediaState() => new JsonObject
    {
        ["cassette"] = Cassette(_machine.Cassette),
        ["disks"] = DiskState()
    };

    private static JsonObject Cassette(CommodoreDatasette deck) => new JsonObject
    {
        ["path"] = deck.Media?.Label,
        ["mode"] = deck.Mode.ToString().ToLowerInvariant(),
        ["recording"] = deck.Mode == TapeMode.Recording,
        ["motor"] = deck.Motor,
        ["position"] = deck.Position,
        ["atEnd"] = deck.Tape is null || deck.Position >= deck.Tape.Pulses.Count
    };
}
