// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Commodore;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;
using System.Globalization;
using System.IO.Compression;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// The changed disks a machine keeps in its recovery journal, and putting them back when it starts again.
internal static partial class MediaActions
{
    // The disks put back from a journal, which their drives say were kept from the last run.
    private static readonly ConditionalWeakTable<IMedium, object> s_recovered = [];

    /// <summary>
    ///  Gets whether a disk was put back from the machine's recovery journal, as kept from its last run.
    /// </summary>
    /// <param name="medium">The disk.</param>
    /// <returns>True when it was.</returns>
    internal static bool IsKept(IMedium medium) => s_recovered.TryGetValue(medium, out _);

    /// <summary>
    ///  Takes a checkpoint of a machine's changed disks, in its drives and ejected from them, under the machine's
    ///  lock; the journal commits it afterward, off the machine's thread.
    /// </summary>
    /// <param name="devices">The machine's devices.</param>
    /// <param name="journal">Its journal, which says which disks it holds as they are already.</param>
    /// <param name="whole">
    ///  Whether to take every changed disk's snapshot, as the last checkpoint does, whatever the journal holds already.
    /// </param>
    /// <returns>
    ///  Each changed disk that came from an image, with its snapshot when the journal lacks this version.
    /// </returns>
    /// <remarks>
    ///  <para>
    ///   A disk the launch built, with no image, is not kept: the next launch builds it again.
    ///  </para>
    /// </remarks>
    internal static List<JournalDisk> Journal(IReadOnlyList<IDevice> devices, RecoveryJournal journal, bool whole = false)
    {
        List<JournalDisk> disks = [];
        foreach (IDevice device in devices)
        {
            // A disk only the launch can put in a drive, as slot 7's, cannot go back in a running machine; the next
            // launch gives the drive its image again.
            if (device is IMediumSlot { Medium: { IsDirty: true } disk }
                && device.Media is { } media
                && device.Info.Operations.HasFlag(MediaOperations.Insert))
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
            disks.Add(new(source.Id, medium.GetType().Name, version, !whole && journal.Holds(source.Id, version) ? null : medium.Snapshot(), entry));
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

        // The drives a kept disk went back in: a second kept for the same drive, as when one could not go back before
        // and another changed there since, stays in the journal rather than replace the first.
        HashSet<string> filled = [];
        foreach (JsonObject disk in journal.Kept)
        {
            string label = "a disk";
            try
            {
                // Everything the entry says is read and checked before the disk goes anywhere, so a bad entry leaves
                // the machine as its launch set it up and stays in the journal.
                label = disk.String("label") ?? label;
                string drive = disk.String("drive") ?? throw new InvalidDataException("It names no drive.");
                IDevice device = devices.FirstOrDefault(device => device.Id == drive)
                    ?? throw new InvalidDataException($"The machine has no {drive} now.");

                JsonObject source = disk.Object("source") ?? throw new InvalidDataException("It names no image.");
                DiskSource from = new(
                    Guid.ParseExact(disk.String("medium") ?? "", "N"),
                    source.String("path") ?? throw new InvalidDataException("It names no image."),
                    CodecOf(source.Object("codec")),
                    FileRevision.FromJson(source.Object("baseline") ?? throw new InvalidDataException("It has no baseline.")));

                string format = disk.String("format") ?? "";
                KeptDisk? outside = null;
                IMediumSlot? slot = null;
                IMedium medium = Load(disk.String("type"), disk.String("kind"), journal.Image(disk), disk.Bool("writeProtected") == true);
                if (disk.Object("ejected") is { } ejected)
                {
                    outside = new KeptDisk(medium, label, format, ejected.String("why") ?? "ejected")
                    {
                        Id = ejected.String("id") ?? $"k-{Guid.NewGuid():N}",
                        When = DateTime.Parse(ejected.String("when") ?? "", CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind),
                    };
                }
                else
                {
                    slot = device as IMediumSlot ?? throw new InvalidDataException($"{device.Info.Name} holds no disk.");
                    if (filled.Contains(drive))
                    {
                        throw new InvalidDataException($"Another disk kept for {device.Info.Name} went back in it.");
                    }
                }

                medium.MarkChanged();
                Keep(medium, from);
                s_recovered.AddOrUpdate(medium, from);
                if (outside is not null)
                {
                    s_ejected.GetValue(device, _ => []).Add(outside);
                }
                else
                {
                    slot?.Mount(medium, label, format);
                    filled.Add(drive);
                }

                journal.Placed(disk, from.Id, medium.Version);
            }
            catch (Exception exception) when (exception is IOException
                or UnauthorizedAccessException
                or InvalidDataException
                or InvalidOperationException
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
            (nameof(FloppyDisk), DmkFormat.SnapshotKind) => DmkFormat.ReadSnapshot(image),
            (nameof(AcornTape), AcornTape.SnapshotKind) => UefFormat.Read(image),
            (nameof(CommodoreDisk), CommodoreDisk.SnapshotKind) => G64Format.Read(image),
            (nameof(CommodoreTape), CommodoreTape.SnapshotKind) => CommodoreTape.FromSnapshot(image),
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
            ["layout"] = floppy.Layout is { } layout ? Convert.ToBase64String(Compress(layout)) : null,
        },
        AcornTapeCodec => new() { ["kind"] = "acornTape" },
        AcornDiskCodec acorn => new() { ["kind"] = "acornDisk", ["format"] = acorn.Format },
        CommodoreDiskCodec disk => new() { ["kind"] = "commodoreDisk", ["format"] = disk.Format },
        CommodoreTapeCodec tape => new() { ["kind"] = "commodoreTape", ["format"] = tape.Format },
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
            "floppy" when codec.String("layout") is { } layout => FloppyImageCodec.ForLayout(format, Decompress(Convert.FromBase64String(layout))),
            "floppy" => FloppyImageCodec.For(format, [format]),
            "acornTape" => new AcornTapeCodec(),
            "acornDisk" => new AcornDiskCodec(format),
            "commodoreDisk" => new CommodoreDiskCodec(format),
            "commodoreTape" => new CommodoreTapeCodec(format),
            _ => null,
        };
    }

    // A DMK or IMD layout, which is mostly zeros and gaps, kept compressed in the journal.
    private static byte[] Compress(byte[] bytes)
    {
        using MemoryStream output = new();
        using (GZipStream zip = new(output, CompressionLevel.Optimal, leaveOpen: true)) { zip.Write(bytes); }
        return output.ToArray();
    }

    private static byte[] Decompress(byte[] bytes)
    {
        using MemoryStream output = new();
        using (GZipStream zip = new(new MemoryStream(bytes), CompressionMode.Decompress)) { zip.CopyTo(output); }
        return output.ToArray();
    }
}
