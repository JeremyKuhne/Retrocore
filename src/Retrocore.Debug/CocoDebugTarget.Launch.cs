// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Machines.Coco;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

internal sealed partial class CocoDebugTarget
{
    // The path a recording is saved to when its tape is ejected.
    private string? _recordingPath;

    /// <summary>
    ///  Launches a Color Computer from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are the dumps in <c>romDirectory</c> (or <c>RETROCORE_COCO_ROMS</c>) under MAME's names, such as
    ///   <c>bas12.rom</c>, <c>extbas11.rom</c>, <c>coco3.rom</c> and <c>disk11.rom</c>, in the directory or its
    ///   <c>coco</c>, <c>coco2b</c>, <c>coco3</c> and <c>coco_fdc</c> folders.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, reset.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static CocoDebugTarget Launch(JsonObject args)
    {
        CocoModel model = (args.String("model") ?? "coco2") switch
        {
            "coco1" => CocoModel.Coco1,
            "coco2" => CocoModel.Coco2,
            "coco3" => CocoModel.Coco3,
            _ => throw new ArgumentException("model must be coco1, coco2 or coco3.")
        };

        int color = Version(args.String("colorBasic") ?? "1.2", "colorBasic", "1.0", "1.1", "1.2", "1.3");
        int extended = Version(args.String("extendedBasic") ?? "1.1", "extendedBasic", "none", "1.0", "1.1");
        CocoArtifactColors artifacts = (args.String("artifacts") ?? "blue-red") switch
        {
            "blue-red" => CocoArtifactColors.BlueRed,
            "red-blue" => CocoArtifactColors.RedBlue,
            "none" => CocoArtifactColors.None,
            _ => throw new ArgumentException("artifacts must be blue-red, red-blue or none.")
        };

        bool rgb = (args.String("monitor") ?? "composite") switch
        {
            "composite" => false,
            "rgb" => true,
            _ => throw new ArgumentException("monitor must be composite or rgb.")
        };

        CocoConfiguration configuration = new()
        {
            Model = model,
            RamKilobytes = args.Int("ramKilobytes"),
            LowercaseVdg = args.Bool("lowercase") ?? false,
            ArtifactColors = artifacts,
            RgbMonitor = rgb
        };

        string? directory = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS");
        CocoRoms roms;
        CocoDiskController? disk = null;
        JsonNode?[] disks = args["disks"] is JsonArray given ? [.. given] : [];
        if (directory is null)
        {
            // Without dumps, Color, Extended and Disk BASIC are built from the SDK's sources; the CoCo 3's has none
            // yet.
            if (model == CocoModel.Coco3)
            {
                throw new ArgumentException(
                    "Without ROM dumps a CoCo 1 or 2 runs Color, Extended and Disk BASIC, built from the SDK's sources; "
                        + "the CoCo 3's BASIC needs romDirectory (or RETROCORE_COCO_ROMS).");
            }

            string? sdkRoms = args.String("sdkRoms");
            string sdk = CocoSdkModules.SdkDirectory(sdkRoms is null ? null : Path.GetFullPath(sdkRoms));
            AssemblyResult colorBasic = CocoSdkModules.AssembleColorBasic(Path.Join(sdk, "ColorBasic.asm"), color);
            ReadOnlySpan<byte> extendedBasic = extended == 0
                ? []
                : CocoSdkModules.AssembleExtendedBasic(Path.Join(sdk, "ExtendedBasic.asm"), extended).Sections[0].Bytes.Span;

            roms = CocoRoms.ForCoco12(colorBasic.Sections[0].Bytes.Span, extendedBasic);
            if (args.Bool("diskController") ?? disks.Length != 0)
            {
                int version = Version(args.String("diskBasic") ?? "1.1", "diskBasic", "1.0", "1.1");
                disk = new(CocoSdkModules.AssembleDiskBasic(Path.Join(sdk, "DiskBasic.asm"), version).Sections[0].Bytes.Span);
            }

            CocoDebugTarget sdkTarget = Finish(args, configuration, roms, disk, disks);
            sdkTarget.SdkRoms = true;
            return sdkTarget;
        }

        try
        {
            roms = CocoRoms.Load(model, directory, color, extended);
            if (args.Bool("diskController") ?? disks.Length != 0)
            {
                int version = Version(args.String("diskBasic") ?? "1.1", "diskBasic", "1.0", "1.1");
                disk = new(CocoRoms.LoadDiskBasic(directory, version));
            }
        }
        catch (FileNotFoundException exception)
        {
            throw new ArgumentException($"{exception.FileName} is missing; romDirectory needs the Color Computer ROM dumps.");
        }

        return Finish(args, configuration, roms, disk, disks);
    }

    // Builds the machine and puts in the media the launch names.
    private static CocoDebugTarget Finish(
        JsonObject args,
        CocoConfiguration configuration,
        CocoRoms roms,
        CocoDiskController? disk,
        JsonNode?[] disks)
    {
        CocoMachine machine = new(configuration, roms, disk);
        CocoDebugTarget target = new(machine) { FastCassette = args.Bool("fastCassette") ?? true };
        target.SetSound(args.String("sound") ?? "speaker");
        if (args.String("cartridge") is { } cartridge)
        {
            machine.Bus.Cartridge = new(File.ReadAllBytes(Path.GetFullPath(cartridge)), args.Bool("autostart") ?? true);
        }

        if (args.String("cassette") is { } cassette) { target.Insert(cassette); }
        if (disks.Length > Trs80DiskController.DriveCount)
        {
            throw new ArgumentException("The disk controller has four drives.");
        }

        for (int drive = 0; drive < disks.Length; drive++)
        {
            if (disks[drive] is JsonValue value && value.GetValue<string>() is { } image)
            {
                target.Insert(drive, image);
            }
        }

        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so BASIC sets up its RAM.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * CocoTiming.ClockHertz));

        // A program loads between instructions.
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <inheritdoc/>
    public void DeviceAction(Machines.Devices.IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (CocoCassetteDrive, "insert"):
                Insert(path ?? throw new ArgumentException("path is required."));
                break;
            case (CocoCassetteDrive cassette, "record"):
                EjectCassette();
                string full = Path.GetFullPath(path ?? throw new ArgumentException("path is required, for saving the recording."));
                cassette.Record(new CassetteImage(), full);
                _recordingPath = full;
                break;
            case (CocoCassetteDrive, "eject"):
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

    // A version argument's number, such as 12 for "1.2", or 0 for "none".
    private static int Version(string value, string name, params string[] allowed)
    {
        if (!allowed.Contains(value))
        {
            throw new ArgumentException($"{name} must be {string.Join(", ", allowed[..^1])} or {allowed[^1]}.");
        }

        string digits = value.Replace(".", "", StringComparison.Ordinal);
        return value == "none" ? 0 : int.Parse(digits, System.Globalization.CultureInfo.InvariantCulture);
    }

    // retro/media: inserts, records and ejects cassettes, and inserts and ejects disks.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        string device = args.String("device") ?? throw new ArgumentException("device is required.");
        int drive = args.Int("drive") ?? 0;
        IReadOnlyList<Trs80FloppyDrive> drives = Drives;
        if (device == "disk")
        {
            if (drive < 0 || drive >= drives.Count) { throw new ArgumentException($"There is no drive {drive}."); }
            DeviceAction(drives[drive], action, args);
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

    private IReadOnlyList<Trs80FloppyDrive> Drives => _machine.Bus.DiskController?.Drives ?? [];

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
        if (drive < 0 || drive >= Drives.Count)
        {
            throw new ArgumentException($"There is no drive {drive}; disks need the disk controller.");
        }

        string full = Path.GetFullPath(path);
        Drives[drive].Insert(JvcFormat.Read(File.ReadAllBytes(full)), full, "JVC");
    }

    private JsonObject MediaState() => new JsonObject
    {
        ["cassette"] = new JsonObject
        {
            ["path"] = _machine.Cassette.Media?.Label,
            ["recording"] = _recordingPath is not null,
            ["motor"] = _machine.Bus.CassetteMotor,
            ["atEnd"] = _machine.Bus.Cassette.AtEnd
        },
        ["disks"] = Drives.Select(drive => new JsonObject
        {
            ["drive"] = drive.Drive,
            ["path"] = drive.Media?.Label,
            ["mounted"] = drive.Disk is not null,
            ["cylinder"] = drive.Head.Track,
            ["selected"] = drive.Head.Selected
        }).ToJsonArray()
    };
}
