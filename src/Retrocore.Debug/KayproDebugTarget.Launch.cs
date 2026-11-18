// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Kaypro;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class KayproDebugTarget
{
    // The names a dump of each chip may have: MAME's first.
    private static readonly string[] s_monitorDumps = ["81-149c.u47", "81-149c.rom"];
    private static readonly string[] s_characterDumps = ["81-146.u43", "81-146a.bin"];
    private static readonly string[] s_folders = ["kayproii"];

    /// <summary>
    ///  Builds a Kaypro II from a launch's arguments: its ROMs from the SDK's sources, or from the dumps in
    ///  <c>romDirectory</c> (or <c>RETROCORE_KAYPRO_ROMS</c>), and the disks in <c>disks</c>, drive A first.
    /// </summary>
    /// <param name="args">The launch's arguments.</param>
    /// <returns>The target, reset and not yet run.</returns>
    /// <exception cref="ArgumentException">An argument is wrong or a dump is missing.</exception>
    internal static KayproDebugTarget Launch(JsonObject args)
    {
        string? directory = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_KAYPRO_ROMS");
        string sdk = KayproSdkModules.SourceDirectory(args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null);
        byte[] monitor = directory is null
            ? KayproSdkModules.AssembleMonitor(Path.Join(sdk, KayproSdkModules.MonitorSource)).Sections[0].Bytes.ToArray()
            : Dump(directory, args.String("rom") is { } named ? [named] : s_monitorDumps, KayproRoms.MonitorSize);

        byte[] characters = directory is not null && Find(directory, s_characterDumps) is not null
            ? Dump(directory, s_characterDumps, KayproRoms.CharacterGeneratorSize)
            : KayproSdkModules.AssembleCharacterGenerator(Path.Join(sdk, KayproSdkModules.CharacterGeneratorSource))
                .Sections[0].Bytes.ToArray();

        KayproMachine machine = new(new(monitor, characters));
        KayproDebugTarget target = new(machine)
        {
            MonitorImage = monitor,
            FastDisk = args.Bool("fastDisk") ?? true
        };

        string?[] disks = args.ImagePaths("disks", "cpm.img");
        if (disks.Length > machine.Drives.Count)
        {
            throw new ArgumentException($"The Kaypro II has {KayproMachine.DriveCount} drives.");
        }

        for (int drive = 0; drive < disks.Length; drive++)
        {
            if (disks[drive] is { } disk) { target.Insert(drive, disk); }
        }

        machine.Reset();
        return target;
    }

    /// <summary>
    ///  Runs the machine for a while from power-up, ending at an instruction boundary.
    /// </summary>
    /// <param name="seconds">The machine time to run.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * KayproTiming.ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <summary>
    ///  Runs the machine until CP/M shows its prompt, such as <c>A&gt;</c>, and types a command at it.
    /// </summary>
    /// <param name="command">The command, such as <c>DIR</c> or <c>B:STAT</c>.</param>
    /// <param name="seconds">The most machine time to wait for the prompt.</param>
    /// <exception cref="InvalidOperationException">CP/M does not show its prompt in time.</exception>
    internal void TypeAtPrompt(string command, double seconds)
    {
        ulong end = _machine.Processor.CycleCount + (ulong)(seconds * KayproTiming.ClockHertz);
        while (!AtPrompt())
        {
            if (_machine.Processor.CycleCount >= end)
            {
                throw new InvalidOperationException(
                    $"CP/M did not show its prompt within {seconds} seconds to type {command}; is a system disk in drive A?");
            }

            _machine.Run(KayproTiming.ClockHertz / 50);
        }

        foreach (char character in command) { _machine.Bus.Keyboard.Type((byte)character); }
        _machine.Bus.Keyboard.Type(13);
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    // Whether the cursor follows CP/M's prompt: a drive letter and >, at the start of a line.
    private bool AtPrompt()
    {
        KayproVideo video = _machine.Bus.Video;
        for (int row = 0; row < KayproVideo.Rows; row++)
        {
            byte cursor = video.Displayed(row, 2);
            if ((cursor & 0x80) == 0) { continue; }
            char drive = video.Character(video.Displayed(row, 0));
            return drive is >= 'A' and <= 'P' && video.Character(video.Displayed(row, 1)) == '>';
        }

        return false;
    }

    private static string? Find(string directory, string[] names) =>
        names.Select(name => Trs80Model3DebugTarget.Find(directory, s_folders, name)).FirstOrDefault(path => path is not null);

    private static byte[] Dump(string directory, string[] names, int size)
    {
        string path = Find(directory, names)
            ?? throw new ArgumentException($"romDirectory {directory} needs one of {string.Join(", ", names)}.");

        byte[] bytes = File.ReadAllBytes(path);
        return bytes.Length == size
            ? bytes
            : throw new ArgumentException($"{Path.GetFileName(path)} is {bytes.Length} bytes; it should be {size}.");
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

        // A changed disk is held back, as from retro/device, so an older client cannot lose it.
        if (MediaActions.Device(_machine.Drives[drive], action, args) is { } answer) { return answer; }
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
            case (FloppyDrive drive, "insert"):
                Insert(drive.Drive, path ?? throw new ArgumentException("path is required."));
                break;
            case (FloppyDrive drive, "eject"):
                drive.Eject();
                break;
            case (FloppyDrive drive, "writeProtect"):
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

        FloppyMedia.Insert(_machine.Drives[drive], path, FloppyFamily.Kaypro);
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
