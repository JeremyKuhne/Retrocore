// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

internal sealed partial class Trs80Model2DebugTarget
{
    private const string CharacterGeneratorDump = "8043316.u9";

    // MAME's names for the boot ROM's versions, newest first: the newest boots from a hard disk too.
    private static readonly string[] s_bootDumps =
        ["u54.u11", "cpu_fc86.u11", "cpu_2119.u11", "cpu_11be.u11", "8047316.u11", "8043216.u11"];

    private static readonly string[] s_folders = ["trs80m2", "trs80m16"];

    /// <summary>
    ///  Launches a Model II, 12 or 16 from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are dumps under MAME's names, in <c>romDirectory</c> (or <c>RETROCORE_TRS80_ROMS</c>) or its
    ///   <c>trs80m2</c> or <c>trs80m16</c> folder: the boot ROM, the newest of <c>u54.u11</c>, <c>cpu_fc86.u11</c>,
    ///   <c>cpu_2119.u11</c>, <c>cpu_11be.u11</c>, <c>8047316.u11</c> and <c>8043216.u11</c> found (or the one
    ///   <c>bootRom</c> names), and the character generator, <c>8043316.u9</c>. Without a ROM directory the machine
    ///   runs ROMs built from the SDK's sources (<c>sdkRoms</c>, or the copy beside the debug host), byte-identical
    ///   to <c>u54.u11</c> and the character generator; a character generator missing from the ROM directory is
    ///   built from its source too.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, reset.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid, or a ROM is missing.</exception>
    internal static Trs80Model2DebugTarget Launch(JsonObject args)
    {
        Trs80Model2Variant variant = (args.String("model") ?? "2") switch
        {
            "2" or "II" or "model2" => Trs80Model2Variant.Model2,
            "12" or "model12" => Trs80Model2Variant.Model12,
            "16" or "16b" or "6000" or "model16" => Trs80Model2Variant.Model16,
            _ => throw new ArgumentException("model must be 2, 12 or 16.")
        };

        Trs80Model2Configuration configuration = new()
        {
            Variant = variant,
            RamKilobytes = args.Int("ramKilobytes") ?? 64
        };

        string? directory = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS");
        string sdk = Trs80DebugTarget.SdkDirectory(args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null);
        byte[] bootRom = directory is null
            ? Trs80SdkModules.AssembleModel2Boot(Path.Join(sdk, "Model2Boot.asm"), 5).Sections[0].Bytes.ToArray()
            : DumpBoot(directory, args.String("bootRom"));

        byte[] characters = directory is not null && Trs80Model3DebugTarget.Find(directory, s_folders, CharacterGeneratorDump) is not null
            ? Trs80Model3DebugTarget.Dump(directory, s_folders, CharacterGeneratorDump, Trs80Model2Roms.CharacterGeneratorSize)
            : Trs80SdkModules.AssembleModel2CharacterGenerator(Path.Join(sdk, "Model2CharacterGenerator.asm"))
                .Sections[0].Bytes.ToArray();

        Trs80Model2Machine machine = new(configuration, new(bootRom, characters));
        Trs80Model2DebugTarget target = new(machine)
        {
            BootRomImage = bootRom,
            FastDisk = args.Bool("fastDisk") ?? true
        };

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

    private static byte[] DumpBoot(string directory, string? named)
    {
        string[] boots = named is not null ? [named] : s_bootDumps;
        string boot = boots.Select(name => Trs80Model3DebugTarget.Find(directory, s_folders, name)).FirstOrDefault(path => path is not null)
            ?? throw new ArgumentException(
                $"The boot ROM is missing from {directory}; romDirectory needs one of {string.Join(", ", boots)}.");

        return File.ReadAllBytes(boot);
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * Trs80Model2Timing.ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    // retro/media: inserts and ejects disks.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        if (args.String("device") != "disk")
        {
            throw new ArgumentException("device must be disk, with action insert or eject.");
        }

        int drive = args.Int("drive") ?? 0;
        if (drive < 0 || drive >= _machine.Drives.Count)
        {
            throw new ArgumentException($"There is no drive {drive}.");
        }

        DeviceAction(_machine.Drives[drive], action, args);
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
