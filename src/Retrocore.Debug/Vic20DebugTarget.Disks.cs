// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Media.Commodore;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class Vic20DebugTarget
{
    /// <summary>
    ///  The first serial-bus device number a drive can take.
    /// </summary>
    internal const int FirstDiskAddress = 8;

    /// <summary>
    ///  The last serial-bus device number a drive can take.
    /// </summary>
    internal const int LastDiskAddress = 11;

    /// <summary>
    ///  The drive models, in the order Add Card lists them.
    /// </summary>
    internal static readonly string[] DiskModels = ["1541", "1540"];

    // The chips each drive loads, all of which a folder must hold: a set missing one falls through to the next folder.
    private static readonly string[] s_1541Files = ["325302-01.uab4", "901229-06 aa.uab5"];
    private static readonly string[] s_1540Files = ["325302-01.uab4", "325303-01.uab5"];

    /// <summary>
    ///  Gets or sets the drives' ROMs by model, <c>1541</c> and <c>1540</c>, for drives added while the machine runs;
    ///  a model without its dumps is missing.
    /// </summary>
    internal Dictionary<string, Cbm1541Roms> DiskRoms { get; set; } = [];

    /// <summary>
    ///  Loads the drives' ROMs from MAME's sets: the 1541's <c>c1541</c> in a directory, its <c>c1541</c>,
    ///  <c>vic20</c> or <c>vic20p</c> folder, or a <c>c1541</c> folder beside it; the 1540's <c>c1540</c> likewise,
    ///  in the directory, its <c>c1540</c> folder or one beside it.
    /// </summary>
    /// <param name="directory">The directory, or null.</param>
    /// <returns>The ROMs found, by model.</returns>
    internal static Dictionary<string, Cbm1541Roms> LoadDiskRoms(string? directory)
    {
        Dictionary<string, Cbm1541Roms> roms = [];
        if (string.IsNullOrWhiteSpace(directory)) { return roms; }
        string full = Path.GetFullPath(directory);
        string parent = Path.GetDirectoryName(full) ?? full;
        foreach (string folder in (string[])[Path.Join(full, "c1541"), full, Path.Join(full, "vic20"), Path.Join(full, "vic20p"), Path.Join(parent, "c1541")])
        {
            if (HasAll(folder, s_1541Files))
            {
                roms["1541"] = Cbm1541Roms.Load1541FromDirectory(folder);
                break;
            }
        }

        foreach (string folder in (string[])[Path.Join(full, "c1540"), full, Path.Join(parent, "c1540")])
        {
            if (HasAll(folder, s_1540Files))
            {
                roms["1540"] = Cbm1541Roms.Load1540FromDirectory(folder);
                break;
            }
        }

        return roms;

        static bool HasAll(string folder, string[] files) => files.All(file => File.Exists(Path.Join(folder, file)));
    }

    /// <summary>
    ///  Connects the launch's drives and puts its disks in them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>diskUnits</c> lists the drives' device numbers, 8-11, and <c>diskModel</c> says what they are, 1541 (the
    ///   default) or 1540; <c>disks</c> lists images (<c>.d64</c> or <c>.g64</c>) for those drives in the order
    ///   <c>diskUnits</c> lists them, a null leaving a drive empty. Disks without units connect as many drives, from 8, as they need. With
    ///   neither, no drive is connected, as a VIC-20 came without one. The ROMs are MAME's <c>c1541</c> (901229-06) or
    ///   <c>c1540</c> set, in <c>driveRomDirectory</c>, else <c>romDirectory</c> or <c>RETROCORE_VIC20_ROMS</c>.
    ///  </para>
    /// </remarks>
    /// <param name="args">The launch's arguments.</param>
    /// <param name="romDirectory">The VIC-20's ROM directory, or null.</param>
    /// <exception cref="ArgumentException">A number, model or path is invalid, or the ROMs are missing.</exception>
    internal void LaunchDisks(JsonObject args, string? romDirectory)
    {
        DiskRoms = LoadDiskRoms(args.String("driveRomDirectory"));
        foreach ((string found, Cbm1541Roms roms) in LoadDiskRoms(romDirectory)) { DiskRoms.TryAdd(found, roms); }
        string model = args.String("diskModel") ?? "1541";
        if (!DiskModels.Contains(model)) { throw new ArgumentException("diskModel is 1541 or 1540."); }

        string?[] disks = args.ImagePaths("disks", "game.d64");
        List<int> units = [];

        // Anything but a list of numbers is a mistake, not a request for the default units.
        if (args["diskUnits"] is { } listed && listed is not JsonArray && listed.GetValueKind() != JsonValueKind.Null)
        {
            throw new ArgumentException("diskUnits must be a list of device numbers, 8 to 11, such as [8].");
        }

        if (args.Array("diskUnits") is { } numbers)
        {
            foreach (JsonNode? number in numbers)
            {
                int address = number is JsonValue value && value.TryGetValue(out int whole)
                    ? whole
                    : throw new ArgumentException("diskUnits holds device numbers, 8 to 11.");

                if (address is < FirstDiskAddress or > LastDiskAddress || units.Contains(address))
                {
                    throw new ArgumentException("diskUnits holds different device numbers, 8 to 11.");
                }

                units.Add(address);
            }
        }
        else
        {
            for (int unit = 0; unit < disks.Length; unit++) { units.Add(FirstDiskAddress + unit); }
        }

        if (disks.Length > units.Count)
        {
            throw new ArgumentException($"disks names {disks.Length} images for {units.Count} drives.");
        }

        if (units.Count == 0) { return; }
        Cbm1541Roms driveRoms = RomsFor(model);
        List<Cbm1541> added = [.. units.Select(address => _machine.AddDisk(driveRoms, address))];
        for (int index = 0; index < disks.Length; index++)
        {
            if (disks[index] is { } path) { Insert(added[index].Drive, path); }
        }
    }

    // A model's ROMs, or why there are none.
    private Cbm1541Roms RomsFor(string model) => DiskRoms.TryGetValue(model, out Cbm1541Roms? roms)
        ? roms
        : throw new ArgumentException(
            $"A {model} needs MAME's c{model} ROM set, in driveRomDirectory or romDirectory.");

    // A row for each device number a drive can take: the drive, or a free number.
    private IEnumerable<HardwareRow> DiskRows()
    {
        for (int address = FirstDiskAddress; address <= LastDiskAddress; address++)
        {
            string id = $"serial{address}";
            string name = $"Device {address}";
            if (_machine.Disks.FirstOrDefault(unit => unit.Address == address) is { } unit)
            {
                yield return new(
                    id,
                    name,
                    $"{unit.Model} disk drive",
                    $"A {unit.Model} on the serial bus as device {address}, its DOS on its own 6502.",
                    [unit.Drive.Id],
                    ["removeCard"]);
            }
            else
            {
                string description = DiskRoms.Count == 0
                    ? "Free. A 1541 or 1540 needs MAME's c1541 or c1540 ROM set, in driveRomDirectory or romDirectory."
                    : $"Free: Add Card connects a {string.Join(" or ", DiskModels.Where(DiskRoms.ContainsKey))} as device {address}.";

                yield return new(id, name, "empty", description, Actions: DiskRoms.Count == 0 ? null : ["addCard"]);
            }
        }
    }

    /// <inheritdoc/>
    public void HardwareAction(string id, string action, JsonObject args)
    {
        int address = id.StartsWith("serial", StringComparison.Ordinal) && int.TryParse(id.AsSpan(6), out int number)
            ? number
            : -1;

        bool present = _machine.Disks.Any(unit => unit.Address == address);
        switch (action)
        {
            case "add1541" or "add1540" when address is >= FirstDiskAddress and <= LastDiskAddress && !present:
                _machine.AddDisk(RomsFor(action[3..]), address);
                break;
            case "removeCard" when present:
                _machine.RemoveDisk(address);
                break;
            default:
                throw new ArgumentException($"The {id} hardware does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public JsonObject? Cards()
    {
        JsonObject cards = [];
        for (int address = FirstDiskAddress; address <= LastDiskAddress; address++)
        {
            cards[$"{address}"] = _machine.Disks.FirstOrDefault(unit => unit.Address == address)?.Model ?? "empty";
        }

        return cards;
    }

    /// <inheritdoc/>
    public IEnumerable<string> RestoreCards(JsonObject cards)
    {
        List<string> problems = [];
        foreach ((string key, JsonNode? node) in cards)
        {
            string? card = node?.GetValueKind() == JsonValueKind.String ? node.GetValue<string>() : null;
            bool known = card == "empty" || (card is not null && DiskModels.Contains(card));
            if (!int.TryParse(key, out int address) || address is < FirstDiskAddress or > LastDiskAddress || !known)
            {
                problems.Add($"Device {key} cannot take the saved '{node}'.");
                continue;
            }

            Cbm1541? present = _machine.Disks.FirstOrDefault(unit => unit.Address == address);
            if (present is not null && present.Model != card)
            {
                _machine.RemoveDisk(address);
                present = null;
            }

            if (card is null or "empty" || present is not null) { continue; }
            if (DiskRoms.TryGetValue(card, out Cbm1541Roms? roms)) { _machine.AddDisk(roms, address); }
            else { problems.Add($"Device {address}'s {card} needs MAME's c{card} ROM set."); }
        }

        return problems;
    }

    // Puts a disk in a drive, a G64 or D64 image, which saves back to its file. The image is read before the disk in
    // the drive comes out, so a file that cannot be read leaves it in.
    private static void Insert(CommodoreFloppyDrive drive, string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        (CommodoreDisk disk, CommodoreDiskCodec codec) = CommodoreDiskCodec.Load(bytes);
        drive.Eject();
        drive.Insert(disk, full, codec.Format);
        MediaActions.Register(disk, full, codec, bytes);
    }

    // A drive's actions: insert, eject and writeProtect; saving is the session's.
    private static void DriveAction(CommodoreFloppyDrive drive, string action, JsonObject args)
    {
        switch (action)
        {
            case "insert":
                Insert(drive, args.String("path") ?? throw new ArgumentException("path is required."));
                break;
            case "eject":
                drive.Eject();
                break;
            case "writeProtect":
                drive.SetWriteProtected(args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required."));
                break;
            default:
                throw new ArgumentException($"{drive.Info.Name} does not support {action}.");
        }
    }

    private JsonArray DiskState() => _machine.Disks.Select(unit => unit.Drive)
        .Select(drive => (JsonNode)new JsonObject
        {
            ["device"] = drive.Id,
            ["path"] = drive.Media?.Label,
            ["mounted"] = drive.Disk is not null,
            ["writeProtected"] = drive.Disk?.IsWriteProtected ?? false,
            ["track"] = drive.Head.Track,
            ["motor"] = drive.Motor
        }).ToJsonArray();
}
