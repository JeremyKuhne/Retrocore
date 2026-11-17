// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Trs80;
using System.Globalization;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// The changed disks a machine keeps in its recovery journal, and putting them back when it starts again.
internal static partial class MediaActions
{
    /// <summary>
    ///  Takes a checkpoint of a machine's changed disks, in its drives and ejected from them, under the machine's
    ///  lock; the journal commits it afterward, off the machine's thread.
    /// </summary>
    /// <param name="devices">The machine's devices.</param>
    /// <param name="journal">Its journal, which says which disks it holds as they are already.</param>
    /// <returns>
    ///  Each changed disk that came from an image, with its snapshot when the journal lacks this version.
    /// </returns>
    /// <remarks>
    ///  <para>
    ///   A disk the launch built, with no image, is not kept: the next launch builds it again.
    ///  </para>
    /// </remarks>
    internal static List<JournalDisk> Journal(IReadOnlyList<IDevice> devices, RecoveryJournal journal)
    {
        List<JournalDisk> disks = [];
        foreach (IDevice device in devices)
        {
            if (device is IMediumSlot { Medium: { IsDirty: true } disk } && device.Media is { } media)
            {
                Add(device, disk, media.Label, media.Format, ejected: null);
            }

            foreach (KeptDisk kept in Ejected(device).Where(kept => kept.Medium.IsDirty))
            {
                Add(device, kept.Medium, kept.Label, kept.Format, kept);
            }
        }

        return disks;

        void Add(IDevice device, IMedium medium, string label, string format, KeptDisk? ejected)
        {
            if (Source(medium) is not { } source) { return; }
            JsonObject entry = new()
            {
                ["drive"] = device.Id,
                ["label"] = label,
                ["format"] = format,
                ["source"] = new JsonObject
                {
                    ["path"] = source.Path,
                    ["baseline"] = source.Baseline.ToJson(),
                    ["codec"] = CodecJson(source.Codec),
                },
            };

            if (ejected is not null)
            {
                entry["ejected"] = new JsonObject
                {
                    ["id"] = ejected.Id,
                    ["why"] = ejected.Why,
                    ["when"] = ejected.When.ToString("O", CultureInfo.InvariantCulture),
                };
            }

            long version = medium.Version;
            disks.Add(new(source.Id, medium.GetType().Name, version, journal.Holds(source.Id, version) ? null : medium.Snapshot(), entry));
        }
    }

    /// <summary>
    ///  Puts the disks a machine's journal held back in its drives, or among their ejected disks, changed against
    ///  their images as they were.
    /// </summary>
    /// <param name="devices">The machine's devices, with the media its launch and saved machine gave them.</param>
    /// <param name="journal">Its journal.</param>
    /// <returns>What could not be put back, which the journal keeps as it was.</returns>
    internal static List<string> Recover(IReadOnlyList<IDevice> devices, RecoveryJournal journal)
    {
        List<string> problems = [];
        foreach (JsonObject disk in journal.Kept)
        {
            string label = disk.String("label") ?? "a disk";
            try
            {
                string drive = disk.String("drive") ?? throw new InvalidDataException("It names no drive.");
                IDevice device = devices.FirstOrDefault(device => device.Id == drive)
                    ?? throw new InvalidDataException($"The machine has no {drive} now.");

                JsonObject source = disk.Object("source") ?? throw new InvalidDataException("It names no image.");
                Guid id = Guid.ParseExact(disk.String("medium") ?? "", "N");
                IMedium medium = Load(disk.String("type"), disk.String("kind"), journal.Image(disk), disk.Bool("writeProtected") == true);
                string format = disk.String("format") ?? "";
                if (disk.Object("ejected") is { } ejected)
                {
                    s_ejected.GetValue(device, _ => []).Add(new KeptDisk(medium, label, format, ejected.String("why") ?? "ejected")
                    {
                        Id = ejected.String("id") ?? $"k-{Guid.NewGuid():N}",
                        When = DateTime.Parse(ejected.String("when") ?? "", CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind),
                    });
                }
                else
                {
                    IMediumSlot slot = device as IMediumSlot ?? throw new InvalidDataException($"{device.Info.Name} holds no disk.");
                    slot.Mount(medium, label, format);
                }

                medium.MarkChanged();
                Keep(medium, new DiskSource(
                    id,
                    source.String("path") ?? throw new InvalidDataException("It names no image."),
                    CodecOf(source.Object("codec")),
                    FileRevision.FromJson(source.Object("baseline") ?? throw new InvalidDataException("It has no baseline."))));

                journal.Placed(disk, id, medium.Version);
            }
            catch (Exception exception) when (exception is IOException
                or UnauthorizedAccessException
                or InvalidDataException
                or FormatException
                or ArgumentException
                or NotSupportedException)
            {
                journal.Unplaced(disk);
                problems.Add($"{Path.GetFileName(label)}, kept from the last run, could not be put back: {exception.Message}");
            }
        }

        return problems;
    }

    // Reads a kept disk's snapshot as the medium it was.
    private static IMedium Load(string? type, string? kind, byte[] image, bool writeProtected)
    {
        IMedium medium = (type, kind) switch
        {
            (nameof(WozDisk), WozDisk.SnapshotKind) => WozDisk.Load(image, writable: true),
            (nameof(Disk35Disk), TwoImgContainer.SnapshotKind) => Disk35Disk.Load(image, writeProtected),
            (nameof(MemoryBlockDevice), TwoImgContainer.SnapshotKind) => MemoryBlockDevice.Load(image, writeProtected),
            (nameof(FloppyDisk), DmkFormat.SnapshotKind) => DmkFormat.Read(image),
            _ => throw new InvalidDataException($"A {type} kept as {kind} cannot be read back."),
        };

        medium.IsWriteProtected = writeProtected;
        return medium;
    }

    // The codec a disk's image is written back with, as the journal keeps it: its format and what it read from the
    // image, such as a .dsk's sector order or a JVC's header.
    private static JsonObject? CodecJson(IImageCodec? codec) => codec switch
    {
        SectorImageCodec sectors => new()
        {
            ["kind"] = "sector",
            ["format"] = sectors.Format,
            ["proDosOrder"] = sectors.ProDosOrder,
        },
        WozCodec woz => new() { ["kind"] = "woz", ["version"] = woz.SourceVersion },
        BlockImageCodec blocks => new()
        {
            ["kind"] = "block",
            ["format"] = blocks.Format,
            ["twoImg"] = blocks.IsTwoImg,
        },
        FloppyImageCodec floppy => new()
        {
            ["kind"] = "floppy",
            ["format"] = floppy.Format,
            ["jvcHeader"] = floppy.JvcHeader is { } header ? Convert.ToBase64String(header) : null,
        },
        _ => null,
    };

    private static IImageCodec? CodecOf(JsonObject? codec)
    {
        string format = codec?.String("format") ?? "";
        return codec?.String("kind") switch
        {
            "sector" => new SectorImageCodec(format, codec.Bool("proDosOrder") == true),
            "woz" => new WozCodec(codec.Int("version") ?? 2),
            "block" => BlockImageCodec.For(codec.Bool("twoImg") == true ? "2MG" : format),
            "floppy" when codec.String("jvcHeader") is { } header => FloppyImageCodec.ForImage("JVC", Convert.FromBase64String(header)),
            "floppy" => FloppyImageCodec.For(format, [format]),
            _ => null,
        };
    }
}
