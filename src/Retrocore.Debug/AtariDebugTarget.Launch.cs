// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;
using Retrocore.Machines.Devices;
using Retrocore.Media.Atari;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class AtariDebugTarget
{
    private const int MaximumDrives = 4;

    /// <summary>
    ///  Launches an Atari 400 or 800 from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are the dumps in <c>romDirectory</c> (or <c>RETROCORE_ATARI_ROMS</c>): MAME's <c>a800</c> or
    ///   <c>a800pal</c> chips, the 810's firmware in an <c>atari810</c> folder beside them, and Atari BASIC as
    ///   <c>basic-revc.rom</c> (or <c>-reva</c>, <c>-revb</c>) in the directory or its <c>basic</c> folder. Without the
    ///   directory, or for a ROM it lacks, the ROM is built from the SDK's sources.
    ///  </para>
    ///  <para>
    ///   Atari BASIC is in the left slot unless <c>basicCartridge</c> is <c>none</c> or <c>cartridge</c> names another.
    ///   An <c>executable</c> (an <c>.xex</c>) goes in drive 1 on a disk that boots it, as does a disk image.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, at power-on.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static AtariDebugTarget Launch(JsonObject args)
    {
        AtariModel model = (args.String("model") ?? "atari800") switch
        {
            "atari800" => AtariModel.Atari800,
            "atari400" => AtariModel.Atari400,
            _ => throw new ArgumentException("model must be atari800 or atari400.")
        };

        AtariVideoStandard standard = (args.String("video") ?? "ntsc") switch
        {
            "ntsc" => AtariVideoStandard.Ntsc,
            "pal" => AtariVideoStandard.Pal,
            _ => throw new ArgumentException("video must be ntsc or pal.")
        };

        AtariGraphicsChip chip = (args.String("chip") ?? "gtia") switch
        {
            "gtia" => AtariGraphicsChip.Gtia,
            "ctia" => AtariGraphicsChip.Ctia,
            _ => throw new ArgumentException("chip must be gtia or ctia.")
        };

        int os = standard == AtariVideoStandard.Pal ? AtariSdkModules.OsPal : (args.String("os") ?? "b") switch
        {
            "b" => AtariSdkModules.OsRevisionB,
            "a" => AtariSdkModules.OsRevisionA,
            _ => throw new ArgumentException("os must be a or b; a PAL machine has the PAL OS.")
        };

        int? basic = (args.String("basicCartridge") ?? (args.String("cartridge") is null ? "c" : "none")) switch
        {
            "c" => AtariSdkModules.BasicRevisionC,
            "b" => AtariSdkModules.BasicRevisionB,
            "a" => AtariSdkModules.BasicRevisionA,
            "none" => null,
            _ => throw new ArgumentException("basicCartridge must be c, b, a or none.")
        };

        if (basic is not null && args.String("cartridge") is not null)
        {
            throw new ArgumentException("The left slot holds one cartridge: give basicCartridge none with a cartridge.");
        }

        AtariDiskDriveKind kind = (args.String("diskDrive") ?? "atari810") switch
        {
            "atari810" => AtariDiskDriveKind.Atari810,
            "sio" => AtariDiskDriveKind.CommandLevel,
            _ => throw new ArgumentException("diskDrive must be atari810 or sio.")
        };

        JsonNode?[] disks = args["disks"] is JsonArray given ? [.. given] : [];
        string? executable = args.String("executable");
        if (executable is not null && disks.Length != 0 && disks[0] is not null)
        {
            throw new ArgumentException("An executable boots from drive 1, which disks also names.");
        }

        int drives = args.Int("diskDrives") ?? Math.Max(disks.Length, executable is null ? 0 : 1);
        if (drives is < 0 or > MaximumDrives) { throw new ArgumentException("diskDrives must be 0 to 4."); }
        if (disks.Length > drives)
        {
            throw new ArgumentException($"disks names {disks.Length} disks for {drives} drives.");
        }

        if (executable is not null && drives == 0) { throw new ArgumentException("An executable needs a disk drive."); }

        // A blank romDirectory, as ${env:RETROCORE_ATARI_ROMS} gives when it is not set, names no dumps.
        string? directory = args.String("romDirectory");
        if (string.IsNullOrWhiteSpace(directory))
        {
            directory = Environment.GetEnvironmentVariable("RETROCORE_ATARI_ROMS");
        }

        if (string.IsNullOrWhiteSpace(directory)) { directory = null; }
        string? sdkRoms = args.String("sdkRoms");
        string sdk = AtariSdkModules.SdkDirectory(sdkRoms is null ? null : Path.GetFullPath(sdkRoms));

        bool built = false;
        byte[] image;
        byte[]? firmware = null;
        if (directory is not null && Dumps(directory, os) is { } dumps)
        {
            image = dumps.Image.ToArray();
            firmware = dumps.DiskDrive.IsEmpty ? null : dumps.DiskDrive.ToArray();
        }
        else
        {
            image = AtariSdkModules.BuildImage(sdk, os);
            built = true;
        }

        if (drives != 0 && kind == AtariDiskDriveKind.Atari810 && firmware is null)
        {
            firmware = AtariSdkModules.Assemble810(sdk, 'C').Sections[0].Bytes.ToArray();
            built = true;
        }

        AtariCartridge? left = null;
        if (args.String("cartridge") is { } cartridge)
        {
            left = AtariCartridge.Load(Path.GetFullPath(cartridge));
        }
        else if (basic is { } revision)
        {
            byte[]? dump = directory is null ? null : BasicDump(directory, revision);
            left = new AtariCartridge(dump ?? AtariSdkModules.AssembleBasic(sdk, revision).Sections[0].Bytes.ToArray());
            built |= dump is null;
        }

        AtariCartridge? right = null;
        if (args.String("rightCartridge") is { } rightCartridge)
        {
            if (model == AtariModel.Atari400) { throw new ArgumentException("The 400 has one cartridge slot."); }
            // A raw 8 KB image given for the right slot is a right-slot cartridge; a .car says its own type.
            byte[] bytes = File.ReadAllBytes(Path.GetFullPath(rightCartridge));
            right = bytes.AsSpan().StartsWith("CART"u8)
                ? AtariCartridge.Load(bytes)
                : new AtariCartridge(bytes, AtariCartridgeType.Right8);
        }

        AtariMachine machine = new(
            new AtariRoms(image, firmware ?? []),
            model,
            args.Int("ramKilobytes") is { } kilobytes ? kilobytes * 1024 : null,
            left,
            right,
            standard,
            chip,
            drives,
            kind);

        AtariDebugTarget target = new(machine)
        {
            FastCassette = args.Bool("fastCassette") ?? true,
            SdkRoms = built
        };

        target.SetSound(args.String("sound") ?? "speaker");
        if (args.String("cassette") is { } cassette) { target.InsertTape(cassette); }
        if (executable is not null) { target.InsertDisk(0, executable); }
        for (int drive = 0; drive < disks.Length; drive++)
        {
            if (disks[drive] is JsonValue value && value.GetValue<string>() is { } path)
            {
                target.InsertDisk(drive, path);
            }
        }

        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the OS sets up its vectors and the screen.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        RunCycles((int)(seconds * ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (Atari410, "insert"):
                InsertTape(path ?? throw new ArgumentException("path is required."));
                break;
            case (Atari410 cassette, "record"):
                RecordTape(cassette, path ?? throw new ArgumentException("path is required, for saving the recording."));
                break;
            case (Atari410 cassette, "eject"):
                cassette.Eject();
                break;
            case (Atari410 cassette, "writeProtect"):
                if (cassette.Tape is not { } tape) { throw new ArgumentException($"{cassette.Info.Name} is empty."); }
                tape.IsWriteProtected = args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required.");
                break;
            case (AtariDiskDrive drive, "insert"):
                InsertDisk(drive.Number - 1, path ?? throw new ArgumentException("path is required."));
                break;
            case (AtariDiskDrive drive, "eject"):
                drive.Eject();
                break;
            case (AtariDiskDrive drive, "writeProtect"):
                if (drive.Disk is not { } disk) { throw new ArgumentException($"{drive.Info.Name} is empty."); }
                disk.IsWriteProtected = args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required.");
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    // The OS's and the floating point package's dumps, and the 810's beside them, or null when the directory lacks
    // the chips.
    private static AtariRoms? Dumps(string directory, int os)
    {
        string full = Path.GetFullPath(directory);
        foreach (string candidate in (string[])[full, Path.Join(full, os == AtariSdkModules.OsPal ? "a800pal" : "a800")])
        {
            try
            {
                AtariRoms roms = AtariRoms.LoadFromDirectory(candidate, os == AtariSdkModules.OsRevisionA ? 'A' : 'B');
                if (AtariSdkModules.OsVersionOf(roms.Image[0x0800..]) is { } found && found != os)
                {
                    continue;
                }

                return roms;
            }
            catch (FileNotFoundException)
            {
            }
            catch (DirectoryNotFoundException)
            {
            }
        }

        return null;
    }

    // Atari BASIC's dump for a revision, in the directory or its basic folder.
    private static byte[]? BasicDump(string directory, int revision)
    {
        string name = $"basic-rev{(char)('a' + revision - 1)}.rom";
        foreach (string candidate in (string[])[Path.Join(directory, name), Path.Join(directory, "basic", name)])
        {
            if (File.Exists(candidate)) { return File.ReadAllBytes(candidate); }
        }

        return null;
    }

    // retro/media: inserts, records and ejects tapes, and inserts and ejects disks.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        string device = args.String("device") ?? throw new ArgumentException("device is required.");
        IDevice target;
        if (device == "disk")
        {
            int drive = args.Int("drive") ?? 0;
            if (drive < 0 || drive >= _machine.Drives.Count)
            {
                throw new ArgumentException($"There is no drive {drive}.");
            }

            target = _machine.Drives[drive];
        }
        else if (device == "cassette")
        {
            target = _machine.Cassette;
        }
        else
        {
            throw new ArgumentException("device must be cassette or disk, with action insert or eject, or record for a cassette.");
        }

        // A changed tape or disk is held back, as from retro/device, so an older client cannot lose it.
        if (MediaActions.Device(target, action, args) is { } answer) { return answer; }
        DeviceAction(target, action, args);
        return MediaState();
    }

    // A .cas tape, or a binary load file (.xex), which goes on a tape that boots it. The tape is read before the one in
    // the recorder comes out, so a file that cannot be read leaves it in.
    private void InsertTape(string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        bool cas = !AtariExecutable.IsExecutable(bytes);
        AtariTape tape = cas ? AtariTape.Load(bytes) : AtariTapeBuilder.BootTape(bytes);
        _machine.Cassette.Eject();
        if (cas) { MediaActions.Register(tape, full, new AtariTapeCodec(), bytes); }
        _machine.Cassette.Insert(tape, full, cas ? "CAS" : "XEX");
    }

    // A blank tape whose image is the path, written at once so that saving the recording replaces it, with RECORD and
    // PLAY down.
    private static void RecordTape(Atari410 cassette, string path)
    {
        string full = Path.GetFullPath(path);
        if (Directory.Exists(full) || Path.GetFileName(full).Length == 0)
        {
            throw new ArgumentException($"{full} is a folder; a recording needs a file name.");
        }

        AtariTape tape = new([], Path.GetFileName(full));
        byte[] blank = tape.ToCas();
        ImageWrite written = ImageWriter.Write(full, blank, FileRevision.Read(full));
        if (written.Outcome != "written")
        {
            throw new IOException($"{full} could not be written: {written.Reason ?? written.Outcome}.");
        }

        cassette.Eject();
        MediaActions.Register(tape, full, new AtariTapeCodec(), blank);
        cassette.Insert(tape, full);
        cassette.Record();
    }

    // An ATR or XFD image, or a binary load file (.xex) on a disk that boots it.
    private void InsertDisk(int drive, string path)
    {
        if (drive < 0 || drive >= _machine.Drives.Count)
        {
            throw new ArgumentException($"There is no drive {drive + 1}; the launch's diskDrives gives {_machine.Drives.Count}.");
        }

        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        AtariDiskDrive target = _machine.Drives[drive];
        if (AtariExecutable.IsExecutable(bytes))
        {
            target.Eject();
            target.Insert(AtariExecutable.BootDisk(bytes), full, "XEX");
            return;
        }

        string format = Path.GetExtension(full).TrimStart('.').ToUpperInvariant() == "XFD" ? "XFD" : "ATR";
        AtariDisk disk = AtariDisk.Load(bytes);
        target.Eject();
        MediaActions.Register(disk, full, AtariDiskCodec.For(format), bytes);
        target.Insert(disk, full, format);
    }

    private JsonObject MediaState() => new JsonObject
    {
        ["cassette"] = new JsonObject
        {
            ["path"] = _machine.Cassette.Media?.Label,
            ["recording"] = _machine.Cassette.Mode == TapeMode.Recording,
            ["motor"] = _machine.Cassette.Motor,
            ["atEnd"] = _machine.Cassette.Tape is null || _machine.Cassette.Transport.Position >= _machine.Cassette.Transport.Length
        },
        ["disks"] = _machine.Drives.Select(drive => new JsonObject
        {
            ["drive"] = drive.Number - 1,
            ["path"] = drive.Media?.Label,
            ["mounted"] = drive.Disk is not null,
            ["cylinder"] = drive.Head.Track,
            ["selected"] = drive.Head.Selected
        }).ToJsonArray()
    };
}
