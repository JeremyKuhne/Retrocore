// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

internal sealed partial class Trs80DebugTarget
{
    private const string CharacterGeneratorDump = "mcm6670p.z29";
    private const string Level1Dump = "level1.rom";

    // The path a recording is saved to when its tape is ejected.
    private string? _recordingPath;

    /// <summary>
    ///  Launches a Model I from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are the dumps in <c>romDirectory</c> (or <c>RETROCORE_TRS80_ROMS</c>) under MAME's names, the
    ///   1.3 parts named with <c>_alt</c>. Without dumps they are assembled from the SDK's sources, which are
    ///   byte-identical to them.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, reset.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static Trs80DebugTarget Launch(JsonObject args)
    {
        bool level1 = (args.String("rom") ?? "level2") switch
        {
            "level2" => false,
            "level1" => true,
            _ => throw new ArgumentException("rom must be level2 or level1.")
        };

        int revision = (args.String("revision") ?? "1.3") switch
        {
            "1.2" => 12,
            "1.3" => 13,
            _ => throw new ArgumentException("revision must be 1.2 or 1.3.")
        };

        Trs80Doubler doubler = (args.String("doubler") ?? "none") switch
        {
            "none" => Trs80Doubler.None,
            "percom" => Trs80Doubler.Percom,
            "tandy" => Trs80Doubler.Tandy,
            "both" => Trs80Doubler.Both,
            _ => throw new ArgumentException("doubler must be none, percom, tandy or both.")
        };

        bool expansion = args.Bool("expansionInterface") ?? !level1;
        Trs80Configuration configuration = new()
        {
            Rom = level1 ? Trs80Rom.Level1 : Trs80Rom.Level2,
            RamKilobytes = args.Int("ramKilobytes") ?? (expansion ? 48 : level1 ? 4 : 16),
            ExpansionInterface = expansion,
            // With a controller and no disk the ROM waits for a disk to boot, as a real Model I does until BREAK.
            DiskController = expansion && (args.Bool("diskController") ?? Disks(args).Length != 0),
            LowercaseModification = args.Bool("lowercase") ?? false,
            VideoSnow = args.Bool("snow") ?? false,
            Doubler = doubler
        };

        string? dumps = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS");
        string sdk = SdkDirectory(args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null);
        byte[] system = dumps is null ? SdkSystem(sdk, level1, revision) : DumpSystem(dumps, level1, revision);

        // Radio Shack's lowercase kit replaced the character generator, so a lowercase machine has the kit's font
        // unless the launch asks for the stock one. No dump of the kit's chip is known, so it comes from the SDK.
        bool kit = (args.String("characterGenerator") ?? (configuration.LowercaseModification ? "kit" : "stock")) switch
        {
            "stock" => false,
            "kit" => true,
            _ => throw new ArgumentException("characterGenerator must be stock or kit.")
        };

        byte[] characters = kit
            ? Image(Trs80SdkModules.AssembleCharacterGenerator(Path.Join(sdk, "CharacterGeneratorKit.asm")))
            : dumps is not null && File.Exists(Path.Join(dumps, CharacterGeneratorDump))
                ? File.ReadAllBytes(Path.Join(dumps, CharacterGeneratorDump))
                : Image(Trs80SdkModules.AssembleCharacterGenerator(Path.Join(sdk, "CharacterGenerator.asm")));

        Trs80Machine machine = new(configuration, new(system, characters));
        Trs80DebugTarget target = new(machine, level1 ? null : Trs80SdkModules.RevisionOf(system))
        {
            FastCassette = args.Bool("fastCassette") ?? true
        };

        if (args.String("cassette") is { } cassette) { target.Insert(cassette); }
        if (args["disks"] is JsonArray disks)
        {
            if (disks.Count > Trs80DiskController.DriveCount)
            {
                throw new ArgumentException("A Model I has four drives.");
            }

            for (int drive = 0; drive < disks.Count; drive++)
            {
                if (disks[drive] is JsonValue value && value.GetValue<string>() is { } disk)
                {
                    target.Insert(drive, disk);
                }
            }
        }

        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the ROM sets up its RAM vectors.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * Trs80Timing.ClockHertz));

        // A program loads between instructions.
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    private static JsonNode?[] Disks(JsonObject args) => args["disks"] is JsonArray disks ? [.. disks] : [];

    private static byte[] DumpSystem(string directory, bool level1, int revision)
    {
        string suffix = revision == 13 ? "_alt" : "";
        string[] names = level1 ? [Level1Dump] : [$"rom-a{suffix}.z1", $"rom-b{suffix}.z2", $"rom-c{suffix}.z3"];
        string[] paths = [.. names.Select(name => Path.Join(directory, name))];
        if (paths.FirstOrDefault(path => !File.Exists(path)) is { } missing)
        {
            throw new ArgumentException($"{missing} is missing; romDirectory needs the Model I ROM dumps.");
        }

        byte[] system = [.. paths.SelectMany(File.ReadAllBytes)];
        return level1 ? system : system[..Trs80SdkModules.Level2Size];
    }

    private static byte[] SdkSystem(string directory, bool level1, int revision) => Image(level1
        ? Trs80SdkModules.AssembleLevel1(Path.Join(directory, "Level1.asm"))
        : Trs80SdkModules.AssembleLevel2(Path.Join(directory, "Level2.asm"), revision));

    private static byte[] Image(Assembler.AssemblyResult result) => result.Sections[0].Bytes.ToArray();

    // retro/media: inserts, records and ejects cassettes, and inserts and ejects disks.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        string device = args.String("device") ?? throw new ArgumentException("device is required.");
        int drive = args.Int("drive") ?? 0;
        if (device == "disk")
        {
            if (drive < 0 || drive >= _machine.Drives.Count)
            {
                throw new ArgumentException($"There is no drive {drive}.");
            }

            DeviceAction(_machine.Drives[drive], action, args);
        }
        else if (device == "cassette")
        {
            DeviceAction(_machine.Cassette, action, args);
        }
        else
        {
            throw new ArgumentException("device must be cassette or disk, with action insert or eject, or record for a cassette.");
        }

        return MediaState();
    }

    /// <inheritdoc/>
    public IReadOnlyList<Machines.Devices.IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public void DeviceAction(Machines.Devices.IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (Trs80CassetteDrive, "insert"):
                Insert(path ?? throw new ArgumentException("path is required."));
                break;
            case (Trs80CassetteDrive cassette, "record"):
                EjectCassette();
                string full = Path.GetFullPath(path ?? throw new ArgumentException("path is required, for saving the recording."));
                cassette.Record(new CassetteImage(), full);
                _recordingPath = full;
                break;
            case (Trs80CassetteDrive, "eject"):
                EjectCassette();
                break;
            case (Trs80FloppyDrive drive, "insert"):
                Insert(drive.Drive, path ?? throw new ArgumentException("path is required."));
                break;
            case (Trs80FloppyDrive drive, "eject"):
                drive.Eject();
                break;
            case (Trs80FloppyDrive drive, "writeProtect"):
                drive.SetWriteProtected(args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required."));
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    private void Insert(string path)
    {
        EjectCassette();
        string full = Path.GetFullPath(path);
        _machine.Cassette.Play(new CassetteImage(File.ReadAllBytes(full)), full);
    }

    // A recording is saved to its path when it is ejected.
    private void EjectCassette()
    {
        CassetteImage? tape = _machine.Cassette.Eject();
        if (_recordingPath is { } path && tape is not null) { File.WriteAllBytes(path, tape.ToArray()); }
        _recordingPath = null;
    }

    private void Insert(int drive, string path)
    {
        if (drive < 0 || drive >= _machine.Drives.Count)
        {
            throw new ArgumentException($"There is no drive {drive}.");
        }

        string full = Path.GetFullPath(path);
        (FloppyDisk disk, string format) = Trs80DiskImage.Read(File.ReadAllBytes(full), Path.GetExtension(full));
        _machine.Drives[drive].Insert(disk, full, format);
    }

    private JsonObject MediaState() => new JsonObject
    {
        ["cassette"] = new JsonObject
{
            ["path"] = _machine.Cassette.Media?.Label,
            ["recording"] = _recordingPath is not null,
            ["motor"] = _machine.Bus.Cassette.MotorOn,
            ["atEnd"] = _machine.Bus.Cassette.AtEnd
},
        ["disks"] = _machine.Drives.Select(drive => new JsonObject
{
            ["drive"] = drive.Drive,
            ["path"] = drive.Media?.Label,
            ["mounted"] = drive.Disk is not null,
            ["cylinder"] = drive.Head.Track,
            ["selected"] = drive.Head.Selected
}).ToJsonArray()
    };
}
