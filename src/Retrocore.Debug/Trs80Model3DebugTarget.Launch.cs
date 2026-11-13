// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

internal sealed partial class Trs80Model3DebugTarget
{
    private const string CharacterGeneratorDump = "8044316a.u36";
    private const string Model4PCharacterGeneratorDump = "8049007.u103";
    private const string Level1Dump = "8040032.u104";

    // The path a recording is saved to when its tape is ejected.
    private string? _recordingPath;

    /// <summary>
    ///  Launches a Model III, 4 or 4P from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are dumps under MAME's names, in <c>romDirectory</c> (or <c>RETROCORE_TRS80_ROMS</c>) or its
    ///   <c>trs80m3</c>, <c>trs80m4</c> or <c>trs80m4p</c> folder: the Model III's <c>8041364.u104</c>,
    ///   <c>8040332.u105</c> and <c>8040316c.u106</c> (or <c>8040316b.u106</c>), or one 14K <c>trs80m3.rom</c>, or
    ///   with <c>rom</c> <c>level1</c> its Level I ROM, <c>8040032.u104</c>; the
    ///   Model 4's <c>trs80m4.rom</c>, or the Model III's parts; the 4P's <c>8075332.u69</c>; and the character
    ///   generator, <c>8044316a.u36</c> (the 4P's <c>8049007.u103</c>). Without a ROM directory the machine runs
    ///   ROMs built from the SDK's sources (<c>sdkRoms</c>, or the copy beside the debug host), which are
    ///   byte-identical to the Model III's revision C ROM, the Model 4's and the 4P's; a character generator missing
    ///   from the ROM directory is built from its source too.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, reset.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid, or a ROM is missing.</exception>
    internal static Trs80Model3DebugTarget Launch(JsonObject args)
    {
        Trs80Model3Variant variant = (args.String("model") ?? DefaultModel(args)) switch
        {
            "3" or "III" or "model3" => Trs80Model3Variant.Model3,
            "4" or "model4" => Trs80Model3Variant.Model4,
            "4p" or "4P" or "model4p" => Trs80Model3Variant.Model4P,
            _ => throw new ArgumentException("model must be 3, 4 or 4p.")
        };

        bool level1 = (args.String("rom") ?? "level2") switch
        {
            "level2" => false,
            "level1" when variant == Trs80Model3Variant.Model3 => true,
            "level1" => throw new ArgumentException("Only the Model III has Level I BASIC."),
            _ => throw new ArgumentException("rom must be level2 or level1.")
        };

        Trs80Model3Configuration configuration = new()
        {
            Variant = variant,
            Rom = level1 ? Trs80Rom.Level1 : Trs80Rom.Level2,
            RamKilobytes = args.Int("ramKilobytes") ?? Trs80Model3Configuration.DefaultRam(variant),

            // With a controller and no disk the ROM waits for a disk, as a real machine does until BREAK.
            DiskController = args.Bool("diskController") ?? (args["disks"] is JsonArray { Count: > 0 })
        };

        string? directory = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS");
        string sdk = Trs80DebugTarget.SdkDirectory(args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null);
        byte[] system = directory is null ? SdkSystemRom(sdk, variant, level1) : SystemRom(directory, variant, level1);
        Trs80Model3Machine machine = new(configuration, new(system, CharacterGenerator(directory, sdk, variant)));
        Trs80Model3DebugTarget target = new(machine)
        {
            SystemRomImage = system,
            FastCassette = args.Bool("fastCassette") ?? true
        };

        if (args.String("cassette") is { } cassette)
        {
            if (machine.Cassette is null) { throw new ArgumentException("A Model 4P has no cassette port."); }
            target.Insert(cassette);
        }

        if (args["disks"] is JsonArray disks)
        {
            if (disks.Count > machine.Drives.Count)
            {
                throw new ArgumentException($"The {target.ModelName} has {Trs80DiskController.DriveCount} drives.");
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
    ///  Runs the machine in emulated time, before a program loads.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * Trs80Model3Timing.ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    // trs80-model4 names the Model 4 without a model.
    private static string DefaultModel(JsonObject args) => args.String("machine") == DebugMachines.Trs80Model4 ? "4" : "3";

    private static byte[] SystemRom(string directory, Trs80Model3Variant variant, bool level1)
    {
        if (level1)
        {
            return Dump(directory, ["trs80m3"], Level1Dump, Trs80Model3Roms.BootSize);
        }

        if (variant == Trs80Model3Variant.Model4P)
        {
            return Dump(directory, ["trs80m4p"], "8075332.u69", Trs80Model3Roms.BootSize);
        }

        if (variant == Trs80Model3Variant.Model4 && Find(directory, ["trs80m4"], "trs80m4.rom") is { } model4)
        {
            return Sized(model4, Trs80Model3Roms.SystemSize);
        }

        string[] folders = ["trs80m3", "trs80m4"];
        if (Find(directory, folders, "trs80m3.rom") is { } whole) { return Sized(whole, Trs80Model3Roms.SystemSize); }
        string romC = Find(directory, folders, "8040316c.u106")
            ?? Find(directory, folders, "8040316b.u106")
            ?? throw Missing(directory, "8040316c.u106 (or 8040316b.u106)");

        return
        [
            .. Dump(directory, folders, "8041364.u104", 0x2000),
            .. Dump(directory, folders, "8040332.u105", 0x1000),
            .. Sized(romC, 0x800)
        ];
    }

    private static byte[] SdkSystemRom(string sdk, Trs80Model3Variant variant, bool level1) => (variant switch
    {
        _ when level1 => Trs80SdkModules.AssembleLevel1(Path.Join(sdk, "Level1.asm"), 3),
        Trs80Model3Variant.Model4P => Trs80SdkModules.AssembleModel4PBoot(Path.Join(sdk, "Model4PBoot.asm")),
        Trs80Model3Variant.Model4 => Trs80SdkModules.AssembleModel3(Path.Join(sdk, "Model3.asm"), 4),
        _ => Trs80SdkModules.AssembleModel3(Path.Join(sdk, "Model3.asm"), 3)
    }).Sections[0].Bytes.ToArray();

    private static byte[] CharacterGenerator(string? directory, string sdk, Trs80Model3Variant variant)
    {
        bool model4P = variant == Trs80Model3Variant.Model4P;
        string? dump = directory is null
            ? null
            : model4P
                ? Find(directory, ["trs80m4p"], Model4PCharacterGeneratorDump)
                : Find(directory, ["trs80m3", "trs80m4"], CharacterGeneratorDump);

        return dump is not null
            ? Sized(dump, Trs80Model3Roms.CharacterGeneratorSize)
            : Trs80SdkModules.AssembleModel3CharacterGenerator(Path.Join(sdk, "Model3CharacterGenerator.asm"), model4P)
                .Sections[0].Bytes.ToArray();
    }

    /// <summary>
    ///  Reads a dump from a directory or one of its folders, checking its size.
    /// </summary>
    /// <param name="directory">The ROM directory.</param>
    /// <param name="folders">The folders within it to look in too, as MAME's sets are named.</param>
    /// <param name="name">The dump's name.</param>
    /// <param name="size">Its size.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="ArgumentException">The dump is missing or the wrong size.</exception>
    internal static byte[] Dump(string directory, string[] folders, string name, int size) =>
        Sized(Find(directory, folders, name) ?? throw Missing(directory, name), size);

    /// <summary>
    ///  Finds a dump in a directory or one of its folders.
    /// </summary>
    /// <param name="directory">The ROM directory.</param>
    /// <param name="folders">The folders within it to look in too.</param>
    /// <param name="name">The dump's name.</param>
    /// <returns>Its path, or null.</returns>
    internal static string? Find(string directory, string[] folders, string name) =>
        new[] { directory }.Concat(folders.Select(folder => Path.Join(directory, folder)))
            .Select(folder => Path.Join(folder, name))
            .FirstOrDefault(File.Exists);

    private static byte[] Sized(string path, int size)
    {
        byte[] bytes = File.ReadAllBytes(path);
        return bytes.Length == size
            ? bytes
            : throw new ArgumentException($"{path} is {bytes.Length} bytes; it should be {size}.");
    }

    private static ArgumentException Missing(string directory, string name) =>
        new($"{name} is missing from {directory}; romDirectory needs the machine's ROM dumps under MAME's names.");

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
        else if (device == "cassette" && _machine.Cassette is { } cassette)
        {
            DeviceAction(cassette, action, args);
        }
        else
        {
            throw new ArgumentException("device must be cassette or disk, with action insert or eject, or record for a cassette.");
        }

        return MediaState();
    }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
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
        _machine.Cassette?.Play(new CassetteImage(File.ReadAllBytes(full)), full);
    }

    private void EjectCassette()
    {
        CassetteImage? tape = _machine.Cassette?.Eject();
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
        ["cassette"] = _machine.Cassette is null ? null : new JsonObject
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
