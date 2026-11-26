// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Acorn;
using Retrocore.Machines.Devices;
using Retrocore.Media.Acorn;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class BbcDebugTarget
{
    private const string MosDump = "os12.rom";
    private const string BasicDump = "basic2.rom";
    private const string DnfsDump = "dnfs120.rom";
    private const string CharacterDump = "saa5050";

    /// <summary>
    ///  Launches a BBC Micro from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are the dumps in <c>romDirectory</c> (or <c>RETROCORE_BBC_ROMS</c>) under MAME's names:
    ///   <c>os12.rom</c>, <c>basic2.rom</c>, <c>dnfs120.rom</c> and <c>saa5050</c>, in the directory or its
    ///   <c>bbcb</c>, <c>bbc_acorn8271</c> and <c>saa5050</c> folders. Without either, or with either blank, the ROMs
    ///   are built from the SDK's sources; so is any one the directory lacks.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, at power-on.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static BbcDebugTarget Launch(JsonObject args)
    {
        BbcModel model = (args.String("model") ?? "bbcb") switch
        {
            "bbcb" => BbcModel.ModelB,
            "bbca" => BbcModel.ModelA,
            _ => throw new ArgumentException("model must be bbcb or bbca.")
        };

        JsonNode?[] disks = args["disks"] is JsonArray given ? [.. given] : [];
        bool diskInterface = args.Bool("diskInterface") ?? model == BbcModel.ModelB;
        if (disks.Length != 0 && !diskInterface)
        {
            throw new ArgumentException("Disks need the disk interface.");
        }

        if (disks.Length > 2) { throw new ArgumentException("The disk interface has two drives, 0 and 1."); }

        // A blank romDirectory, as ${env:RETROCORE_BBC_ROMS} gives when it is not set, names no dumps.
        string? directory = args.String("romDirectory");
        if (string.IsNullOrWhiteSpace(directory))
        {
            directory = Environment.GetEnvironmentVariable("RETROCORE_BBC_ROMS");
        }

        if (string.IsNullOrWhiteSpace(directory)) { directory = null; }

        string? sdkRoms = args.String("sdkRoms");
        string sdk = BbcSdkModules.SdkDirectory(sdkRoms is null ? null : Path.GetFullPath(sdkRoms));
        bool built = false;
        byte[] Dump(string name, string folder, Func<string, Assembler.AssemblyResult> assemble)
        {
            if (directory is not null)
            {
                foreach (string candidate in (string[])[Path.Join(directory, name), Path.Join(directory, folder, name)])
                {
                    if (File.Exists(candidate)) { return File.ReadAllBytes(candidate); }
                }
            }

            built = true;
            return assemble(sdk).Sections[0].Bytes.ToArray();
        }

        BbcRoms roms;
        try
        {
            roms = new(
                Dump(MosDump, "bbcb", BbcSdkModules.AssembleMos),
                Dump(CharacterDump, "saa5050", BbcSdkModules.AssembleCharacters));

            roms.Fit(3, Dump(BasicDump, "bbcb", BbcSdkModules.AssembleBasic));
            if (diskInterface) { roms.Fit(0, Dump(DnfsDump, "bbc_acorn8271", BbcSdkModules.AssembleDnfs)); }
        }
        catch (ArgumentException exception)
        {
            throw new ArgumentException($"A ROM in {directory} is the wrong size: {exception.Message}");
        }

        BbcMachine machine = new(roms, model, diskInterface);
        BbcDebugTarget target = new(machine)
        {
            FastCassette = args.Bool("fastCassette") ?? true,
            SdkRoms = built
        };

        // boot holds SHIFT as the machine starts, as SHIFT-BREAK does, so the filing system boots its disk or tape.
        if (args.Bool("boot") == true) { machine.Keyboard.HoldShift(BbcMachine.ShiftBreakCycles); }
        target.SetSound(args.String("sound") ?? "speaker");
        if (args.String("cassette") is { } cassette) { target.InsertTape(cassette); }
        for (int drive = 0; drive < disks.Length; drive++)
        {
            if (disks[drive] is JsonValue value && value.GetValue<string>() is { } image)
            {
                target.InsertDisk(drive, image);
            }
        }

        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the MOS and BASIC set up their workspace.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * BbcTiming.CpuHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (BbcCassette, "insert"):
                InsertTape(path ?? throw new ArgumentException("path is required."));
                break;
            case (BbcCassette, "record") when path is not null:
                RecordTape(path);
                break;
            case (BbcCassette cassette, "record"):
                // RECORD over the tape in it at the head, or a blank one put in for it, saved later with Save As. A
                // tape put in to play is write-protected (InsertTape), so RECORD will not go down on it.
                if (cassette.Tape is null) { cassette.Insert(new AcornTape(), "Blank tape", changed: true); }
                cassette.Record();
                break;
            case (BbcCassette cassette, "play"):
                cassette.Play();
                break;
            case (BbcCassette cassette, "stop"):
                cassette.Stop();
                break;
            case (BbcCassette cassette, "rewind"):
                cassette.Rewind();
                break;
            case (BbcCassette cassette, "eject"):
                cassette.Eject();
                break;
            case (BbcFloppyDrive drive, "insert"):
                InsertDisk(drive.Drive, path ?? throw new ArgumentException("path is required."));
                break;
            case (BbcFloppyDrive drive, "eject"):
                drive.Eject();
                break;
            case (BbcFloppyDrive drive, "writeProtect"):
                drive.SetWriteProtected(args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required."));
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    // retro/media: inserts, records and ejects tapes, presses the recorder's keys, and inserts and ejects disks.
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
            throw new ArgumentException("device must be cassette or disk.");
        }

        // A changed tape or disk is held back, as from retro/device, so an older client cannot lose it. One let go of is
        // ejected or replaced through the host, which keeps it for Undo.
        JsonObject? answer = MediaActions.Device(target, action, args, (what, with) => DeviceAction(target, what, with));
        if (answer is null)
        {
            DeviceAction(target, action, args);
        }
        else if (answer.String("outcome") != "discarded")
        {
            return answer;
        }

        return MediaState();
    }

    // A UEF tape, or a file with an .inf file beside it, which goes on a tape as the MOS would save it. The tape is
    // read before the one in the recorder comes out, so a file that cannot be read leaves it in.
    private void InsertTape(string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        AcornTape tape;
        bool uef = UefFormat.IsUef(bytes);
        if (uef)
        {
            tape = UefFormat.Read(bytes);
        }
        else if (File.Exists(full + ".inf"))
        {
            tape = AcornTapeBuilder.Build([AcornTapeFile.FromInf(File.ReadAllText(full + ".inf"), bytes)]);
        }
        else
        {
            throw new ArgumentException($"{Path.GetFileName(full)} is not a UEF tape, and has no .inf file beside it.");
        }

        // A tape to play is write-protected, so the saved machine puts it back in at the next launch; a recording
        // (RecordTape) stays writable.
        tape.IsWriteProtected = true;
        _machine.Cassette.Eject();
        if (uef) { MediaActions.Register(tape, full, new AcornTapeCodec(), bytes); }
        _machine.Cassette.Insert(tape, full, uef ? "UEF" : "INF");
        _machine.Cassette.Play();
    }

    // A blank tape whose image is the path, written at once so that saving the recording replaces it, with RECORD and
    // PLAY down.
    private void RecordTape(string path)
    {
        string full = Path.GetFullPath(path);
        if (Directory.Exists(full) || Path.GetFileName(full).Length == 0)
        {
            throw new ArgumentException($"{full} is a folder; a recording needs a file name.");
        }

        AcornTape tape = new();
        byte[] blank = UefFormat.Write(tape.HalfCycles);
        ImageWrite written = ImageWriter.Write(full, blank, FileRevision.Read(full));
        if (written.Outcome != "written")
        {
            throw new IOException($"{full} could not be written: {written.Reason ?? written.Outcome}.");
        }

        _machine.Cassette.Eject();
        MediaActions.Register(tape, full, new AcornTapeCodec(), blank);
        _machine.Cassette.Insert(tape, full);
        _machine.Cassette.Record();
    }

    /// <summary>
    ///  Gets the disk interface's drive 0, which SHIFT-BREAK boots.
    /// </summary>
    /// <exception cref="InvalidOperationException">The machine has no disk interface.</exception>
    internal BbcFloppyDrive BootDrive =>
        _machine.Drives.Count != 0 ? _machine.Drives[0] : throw new InvalidOperationException("The machine has no disk interface.");

    // An SSD or DSD image; a DSD's second side is drive 2 or 3, the other side of drive 0 or 1.
    private void InsertDisk(int drive, string path)
    {
        if (drive < 0 || drive >= _machine.Drives.Count)
        {
            throw new ArgumentException($"There is no drive {drive}; disks need the disk interface's drives 0 and 1.");
        }

        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        bool doubleSided = AcornDiskImage.IsDoubleSided(Path.GetExtension(full));
        string format = doubleSided ? "DSD" : "SSD";
        Media.Floppy.FloppyDisk disk = AcornDiskImage.Read(bytes, doubleSided);
        BbcFloppyDrive target = _machine.Drives[drive];
        target.Eject();
        MediaActions.Register(disk, full, new AcornDiskCodec(format), bytes);
        target.Insert(disk, full, format);
    }

    private JsonObject MediaState() => new JsonObject
    {
        ["cassette"] = new JsonObject
        {
            ["path"] = _machine.Cassette.Media?.Label,
            ["recording"] = _machine.Cassette.Mode == TapeMode.Recording,
            ["motor"] = _machine.Cassette.Motor,
            ["atEnd"] = _machine.Cassette.Tape is not { } tape || _machine.Cassette.Position >= tape.HalfCycles.Count
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
