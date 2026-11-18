// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class PetDebugTarget
{
    /// <summary>
    ///  Launches a PET from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>model</c> is <c>pet2001</c> (BASIC 1), <c>pet2001-basic2</c> (the default), <c>pet4032</c> (BASIC 4 with
    ///   the graphics keyboard) or <c>pet4032-business</c> (BASIC 4 with the business keyboard). The ROMs are the
    ///   dumps in <c>romDirectory</c> (or <c>RETROCORE_PET_ROMS</c>) under MAME's names, in the directory or in its
    ///   <c>pet2001</c>, <c>pet2001n</c>, <c>pet4016</c> or <c>pet4032b</c> folder; without them, they are built from
    ///   the SDK's sources. <c>basicRevision</c> picks BASIC 1's first chip or BASIC 4's <c>$B000</c> chip,
    ///   <c>revised</c> (the default) or <c>original</c>.
    ///  </para>
    ///  <para>
    ///   <c>ramKilobytes</c> is 4, 8, 16 or 32, by default 8, or 32 on a 4032; <c>snow</c> shows CPU accesses to video
    ///   RAM during the display (on by default on the 2001, whose static board has it, and off otherwise);
    ///   <c>sound</c> is <c>speaker</c> (the default) or <c>off</c>; <c>cassette1</c>
    ///   and <c>cassette2</c> put a tape (<c>.tap</c>, <c>.wav</c> or <c>.prg</c>) in each Datasette with PLAY down.
    ///  </para>
    ///  <para>
    ///   <c>diskUnits</c>, <c>diskModel</c> and <c>disks</c> connect 4040 or 2040 dual drives to the IEEE-488 bus and
    ///   put disks in them; see <see cref="LaunchDisks"/>. A 4032 comes with a 4040 as device 8 when the drive's ROMs
    ///   are found.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, through the reset sequence.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static PetDebugTarget Launch(JsonObject args)
    {
        PetModel model = (args.String("model") ?? "pet2001-basic2") switch
        {
            "pet2001" => PetModel.Pet2001,
            "pet2001-basic2" => PetModel.Pet2001Basic2,
            "pet4032" => PetModel.Pet4032,
            "pet4032-business" => PetModel.Pet4032Business,
            _ => throw new ArgumentException("model must be pet2001, pet2001-basic2, pet4032 or pet4032-business.")
        };

        bool original = (args.String("basicRevision") ?? "revised") switch
        {
            "revised" => false,
            "original" => true,
            _ => throw new ArgumentException("basicRevision must be revised or original.")
        };

        int ram = args.Int("ramKilobytes") ?? (model.BasicVersion() == 4 ? 32 : 8);
        if (ram is not (4 or 8 or 16 or 32))
        {
            throw new ArgumentException("ramKilobytes must be 4, 8, 16 or 32.");
        }

        // A blank romDirectory, as ${env:RETROCORE_PET_ROMS} gives when it is not set, names no dumps.
        string? directory = args.String("romDirectory");
        if (string.IsNullOrWhiteSpace(directory))
        {
            directory = Environment.GetEnvironmentVariable("RETROCORE_PET_ROMS");
        }

        PetRoms roms;
        bool sdkRoms = string.IsNullOrWhiteSpace(directory);
        string sdk = SdkDirectory(args.String("sdkRoms") is { } given ? Path.GetFullPath(given) : null);
        if (directory is null || sdkRoms)
        {
            roms = PetSdkModules.BuildRoms(model, sdk, original);
        }
        else
        {
            string folder = DumpFolder(Path.GetFullPath(directory), model);
            try
            {
                roms = PetRoms.LoadFromDirectory(folder, model, original);
            }
            catch (FileNotFoundException exception)
            {
                throw new ArgumentException($"{exception.FileName} is missing; romDirectory needs MAME's PET ROM chips.");
            }
        }

        PetMachine machine = new(roms, model, ram);
        machine.Video.Snow = args.Bool("snow") ?? model == PetModel.Pet2001;
        PetDebugTarget target = new(machine)
        {
            FastCassette = args.Bool("fastCassette") ?? true,
            SdkRoms = sdkRoms,
            OriginalBasic = original && model.BasicVersion() != 2
        };

        target.SetSound(args.String("sound") ?? "speaker");

        // BASIC's page-zero addresses, which loading a program needs before the session adds the SDK's modules.
        if (File.Exists(Path.Join(sdk, "Basic", PetSdkModules.BasicFile(model))))
        {
            target.SetBasicSymbols(PetSdkModules.AssembleBasic(sdk, model, original).Symbols);
        }

        target.LaunchDisks(args, sdkRoms ? Environment.GetEnvironmentVariable("RETROCORE_PET_ROMS") : directory);
        if (args.String("cassette1") is { } first) { Insert(machine.Bus.Cassette1, first); }
        if (args.String("cassette2") is { } second) { Insert(machine.Bus.Cassette2, second); }

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
        _machine.Run((ulong)(seconds * PetTiming.CpuHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <summary>
    ///  Loads a <c>.prg</c> file where its first two bytes say. A program at BASIC's start is a BASIC program: BASIC's
    ///  pointers are set past it, as LOAD sets them, and <c>RUN</c> is typed when asked. Any other is machine code,
    ///  which starts at its entry.
    /// </summary>
    /// <param name="prg">The file's bytes.</param>
    /// <param name="run">Whether to run a BASIC program.</param>
    /// <param name="entry">The machine code's entry, or null for its first byte.</param>
    /// <exception cref="ArgumentException">The file is too short, or does not fit in RAM.</exception>
    internal void LoadPrg(ReadOnlySpan<byte> prg, bool run, int? entry)
    {
        if (prg.Length < 3) { throw new ArgumentException("A .prg file is its load address and at least a byte."); }
        ushort start = (ushort)(prg[0] | (prg[1] << 8));
        Load(start, prg[2..]);
        if (start != BasicStart)
        {
            ProgramCounter = checked((ushort)(entry ?? start));
            return;
        }

        SetProgramEnd(start + prg.Length - 2);
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

        if (device is not PetDatasette deck)
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

    // The folder of a model's chips: the directory, or its MAME set's folder.
    private static string DumpFolder(string directory, PetModel model)
    {
        string name = model switch
        {
            PetModel.Pet2001 => "pet2001",
            PetModel.Pet2001Basic2 => "pet2001n",
            PetModel.Pet4032 => "pet4016",
            _ => "pet4032b"
        };

        string set = Path.Join(directory, name);
        return Directory.Exists(set) ? set : directory;
    }

    // Puts a tape in with PLAY down: a TAP image or WAV recording, which saves back to its file, or a program file
    // made into the tape SAVE would write, which saves only as another file. The tape is read before the one in the
    // Datasette comes out, so a file that cannot be read leaves it in.
    private static void Insert(PetDatasette deck, string path)
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

    // retro/media: the Datasettes' keys and tapes, by device cassette1 or cassette2, and the disk drives' disks, by
    // device disk8-0 for unit 8's drive 0.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        string id = args.String("device") ?? "cassette1";
        IDevice device = _machine.Devices.FirstOrDefault(candidate => candidate.Id == id)
            ?? throw new ArgumentException("device must be cassette1, cassette2 or a disk drive, such as disk8-0.");

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
        ["cassette1"] = Cassette(_machine.Bus.Cassette1),
        ["cassette2"] = Cassette(_machine.Bus.Cassette2),
        ["disks"] = DiskState()
    };

    private static JsonObject Cassette(PetDatasette deck) => new JsonObject
    {
        ["path"] = deck.Media?.Label,
        ["mode"] = deck.Mode.ToString().ToLowerInvariant(),
        ["recording"] = deck.Mode == TapeMode.Recording,
        ["motor"] = deck.Motor,
        ["position"] = deck.Position,
        ["atEnd"] = deck.Tape is null || deck.Position >= deck.Tape.Pulses.Count
    };
}
