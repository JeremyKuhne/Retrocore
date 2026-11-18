// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class PetDebugTarget
{
    /// <summary>
    ///  The IEEE-488 device numbers a disk unit can take.
    /// </summary>
    internal const int FirstDiskAddress = 8;

    /// <summary>
    ///  The last IEEE-488 device number a disk unit can take.
    /// </summary>
    internal const int LastDiskAddress = 15;

    /// <summary>
    ///  The drive models a unit can be, in the order Add Card lists them.
    /// </summary>
    internal static readonly string[] DiskModels = ["4040", "2040"];

    /// <summary>
    ///  Gets or sets the drives' ROMs by model, <c>4040</c> and <c>2040</c>, for disk units added while the machine
    ///  runs; a model without its dumps is missing.
    /// </summary>
    internal Dictionary<string, Cbm4040Roms> DiskRoms { get; set; } = [];

    /// <summary>
    ///  Loads the drives' ROMs from MAME's sets: the 4040's <c>c4040</c> in a directory, its <c>c4040</c>,
    ///  <c>pet2001n</c> or <c>pet4016</c> folder, or a <c>c4040</c> folder beside it; the 2040's <c>c2040</c> likewise.
    /// </summary>
    /// <param name="directory">The directory, or null.</param>
    /// <returns>The ROMs found, by model.</returns>
    internal static Dictionary<string, Cbm4040Roms> LoadDiskRoms(string? directory)
    {
        Dictionary<string, Cbm4040Roms> roms = [];
        if (string.IsNullOrWhiteSpace(directory)) { return roms; }
        string full = Path.GetFullPath(directory);
        string parent = Path.GetDirectoryName(full) ?? full;
        foreach (string folder in (string[])[Path.Join(full, "c4040"), full, Path.Join(full, "pet2001n"), Path.Join(full, "pet4016"), Path.Join(parent, "c4040")])
        {
            if (File.Exists(Path.Join(folder, "901468-14.uj1")) && File.Exists(Path.Join(folder, "901466-04.uk3")))
            {
                roms["4040"] = Cbm4040Roms.LoadFromDirectory(folder);
                break;
            }
        }

        foreach (string folder in (string[])[Path.Join(full, "c2040"), full, Path.Join(parent, "c2040")])
        {
            if (File.Exists(Path.Join(folder, "901468-06.ul1")) && File.Exists(Path.Join(folder, "901466-01.uk3")))
            {
                roms["2040"] = Cbm4040Roms.Load2040FromDirectory(folder);
                break;
            }
        }

        return roms;
    }

    /// <summary>
    ///  Connects the launch's disk units and puts its disks in them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>diskUnits</c> lists the units' device numbers, 8-15, and <c>diskModel</c> says what they are, 4040 (the
    ///   default) or 2040; <c>disks</c> lists images (<c>.d64</c>, <c>.d67</c> or <c>.g64</c>) for unit 8's drive 0,
    ///   its drive 1, then the next unit's, a null leaving a drive empty. Disks without units connect as many units,
    ///   from 8, as they need. With neither, a BASIC 4 PET gets one unit as 8 when its ROMs are found, and an empty
    ///   <c>diskUnits</c> leaves it out. The ROMs are MAME's <c>c4040</c> or <c>c2040</c> set, in
    ///   <c>driveRomDirectory</c>, else <c>romDirectory</c> or <c>RETROCORE_PET_ROMS</c>.
    ///  </para>
    /// </remarks>
    /// <param name="args">The launch's arguments.</param>
    /// <param name="romDirectory">The PET's ROM directory, or null.</param>
    /// <exception cref="ArgumentException">A number, model or path is invalid, or the ROMs are missing.</exception>
    internal void LaunchDisks(JsonObject args, string? romDirectory)
    {
        DiskRoms = LoadDiskRoms(args.String("driveRomDirectory"));
        foreach ((string found, Cbm4040Roms roms) in LoadDiskRoms(romDirectory)) { DiskRoms.TryAdd(found, roms); }
        string model = args.String("diskModel") ?? "4040";
        if (!DiskModels.Contains(model)) { throw new ArgumentException("diskModel is 4040 or 2040."); }

        JsonNode?[] disks = args.Array("disks") is { } given ? [.. given] : [];
        List<int> units = [];
        if (args.Array("diskUnits") is { } numbers)
        {
            foreach (JsonNode? number in numbers)
            {
                int address = number?.GetValueKind() == JsonValueKind.Number
                    ? number.GetValue<int>()
                    : throw new ArgumentException("diskUnits holds device numbers, 8 to 15.");

                if (address is < FirstDiskAddress or > LastDiskAddress || units.Contains(address))
                {
                    throw new ArgumentException("diskUnits holds different device numbers, 8 to 15.");
                }

                units.Add(address);
            }
        }
        else
        {
            for (int unit = 0; unit < (disks.Length + 1) / 2; unit++) { units.Add(FirstDiskAddress + unit); }

            // The 4000 series came with a 4040 beside it: BASIC 4's disk commands talk to device 8.
            if (units.Count == 0 && _machine.Model.BasicVersion() == 4 && DiskRoms.ContainsKey(model))
            {
                units.Add(FirstDiskAddress);
            }
        }

        if (disks.Length > units.Count * 2)
        {
            throw new ArgumentException($"disks names {disks.Length} images for {units.Count * 2} drives.");
        }

        if (units.Count == 0) { return; }
        Cbm4040Roms driveRoms = RomsFor(model);
        List<Cbm4040> added = [.. units.Select(address => _machine.AddDisk(driveRoms, address))];
        for (int index = 0; index < disks.Length; index++)
        {
            if (disks[index] is not JsonValue value || value.GetValueKind() != JsonValueKind.String) { continue; }
            Cbm4040 unit = added[index / 2];
            Insert(index % 2 == 0 ? unit.Drive0 : unit.Drive1, value.GetValue<string>());
        }
    }

    // A model's ROMs, or why there are none.
    private Cbm4040Roms RomsFor(string model) => DiskRoms.TryGetValue(model, out Cbm4040Roms? roms)
        ? roms
        : throw new ArgumentException(
            $"A {model} needs MAME's c{model} ROM set, in driveRomDirectory or romDirectory.");

    // A row for each device number a disk unit can take: the unit, with its two drives, or a free number.
    private IEnumerable<HardwareRow> DiskRows()
    {
        for (int address = FirstDiskAddress; address <= LastDiskAddress; address++)
        {
            string id = $"ieee{address}";
            string name = $"Device {address}";
            if (_machine.Disks.FirstOrDefault(unit => unit.Address == address) is { } unit)
            {
                string dos = unit.Model == "2040" ? "DOS 1.2" : "DOS 2.0";
                yield return new(
                    id,
                    name,
                    $"{unit.Model} dual disk drive",
                    $"A {unit.Model} on the IEEE-488 bus as device {address}, {dos} on its 6502 and its controller's 6504.",
                    [unit.Drive0.Id, unit.Drive1.Id],
                    ["removeCard"]);
            }
            else
            {
                string description = DiskRoms.Count == 0
                    ? "Free. A 4040 or 2040 needs MAME's c4040 or c2040 ROM set, in driveRomDirectory or romDirectory."
                    : $"Free: Add Card connects a {string.Join(" or ", DiskModels.Where(DiskRoms.ContainsKey))} dual drive as device {address}.";

                yield return new(id, name, "empty", description, Actions: DiskRoms.Count == 0 ? null : ["addCard"]);
            }
        }
    }

    /// <inheritdoc/>
    public void HardwareAction(string id, string action, JsonObject args)
    {
        int address = id.StartsWith("ieee", StringComparison.Ordinal) && int.TryParse(id.AsSpan(4), out int number)
            ? number
            : -1;

        bool present = _machine.Disks.Any(unit => unit.Address == address);
        switch (action)
        {
            case "add4040" or "add2040" when address is >= FirstDiskAddress and <= LastDiskAddress && !present:
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

            Cbm4040? present = _machine.Disks.FirstOrDefault(unit => unit.Address == address);
            if (present is not null && present.Model != card)
            {
                _machine.RemoveDisk(address);
                present = null;
            }

            if (card is null or "empty" || present is not null) { continue; }
            if (DiskRoms.TryGetValue(card, out Cbm4040Roms? roms)) { _machine.AddDisk(roms, address); }
            else { problems.Add($"Device {address}'s {card} needs MAME's c{card} ROM set."); }
        }

        return problems;
    }

    // Puts a disk in a drive, a G64, D64 or D67 image, which saves back to its file. The image is read before the disk in
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

    private JsonArray DiskState() => _machine.Disks.SelectMany(unit => (CommodoreFloppyDrive[])[unit.Drive0, unit.Drive1])
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
