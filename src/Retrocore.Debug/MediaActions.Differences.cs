// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Altair;
using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// What a disk changed since its image: the sectors or blocks it differs from the file in, worked out on a drive's own
// request, as it encodes the disk and reads the file.
internal static partial class MediaActions
{
    // How many runs of changed units a summary names before it says how many more.
    private const int SummaryRuns = 4;

    /// <summary>
    ///  Works out what a drive's disk changed against its image as the file is now, by the image's own unit: the
    ///  sectors of a <c>.dsk</c>, JV1 or JVC on their tracks, or the blocks of a block image or 2MG.
    /// </summary>
    /// <param name="device">The drive.</param>
    /// <returns>
    ///  <c>{ unit, count, summary }</c>, such as <c>sector</c>, 14 and <c>tracks 17-18</c>; or null for a disk with no
    ///  image, an image that cannot be read, a format with no fixed units (WOZ, DMK, JV3), or a JVC whose header (its
    ///  geometry) is not the disk's.
    /// </returns>
    internal static JsonObject? Differences(IDevice device)
    {
        if (device is not IMediumSlot { Medium: { } disk } || Source(disk) is not { Codec: { } codec } source)
        {
            return null;
        }

        byte[] file;
        try
        {
            file = File.ReadAllBytes(source.Path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }

        byte[] encoded = codec.Encode(disk.Snapshot()).Bytes;

        // A 2MG's blocks are compared, not its header or the comment and creator data after them.
        if (codec is BlockImageCodec { IsTwoImg: true })
        {
            if (Blocks(encoded) is not { } mine || Blocks(file) is not { } theirs) { return null; }
            encoded = mine;
            file = theirs;
        }

        return Layout(codec, encoded, file) is not { } layout ? null : Compare(layout, encoded, file);
    }

    // The unit an image's format writes the disk in: its size, how many make a track (0 for blocks), and where they
    // start in the disk's encoding and in the file.
    private static (string Unit, int Size, int PerTrack, int Encoded, int File)? Layout(IImageCodec codec, byte[] encoded, byte[] file)
    {
        if (codec is SectorImageCodec) { return ("sector", 256, 16, 0, 0); }
        if (codec is BlockImageCodec) { return ("block", 512, 0, 0, 0); }
        if (codec is AltairDiskCodec) { return ("sector", AltairDisk.SectorBytes, AltairDisk.SectorsPerTrack, 0, 0); }

        if (codec.Format == "JV1") { return ("sector", Jv1Format.SectorSize, Jv1Format.SectorsPerTrack, 0, 0); }
        if (codec.Format != "JVC" || codec is not FloppyImageCodec) { return null; }
        // The header gives the geometry, so a file whose header is not the disk's has its sectors elsewhere.
        ReadOnlySpan<byte> header = JvcFormat.Header(encoded);
        if (!header.SequenceEqual(JvcFormat.Header(file))) { return null; }
        int sectors = header.Length > 0 ? header[0] : JvcFormat.SectorsPerTrack;
        int sides = header.Length > 1 ? header[1] : 1;
        int size = 128 << (header.Length > 2 ? header[2] : 1);
        return ("sector", size, sectors * sides, header.Length, header.Length);
    }

    // A 2MG's blocks, or null for a file that is not a 2MG this reads.
    private static byte[]? Blocks(byte[] image)
    {
        if (!TwoImgContainer.IsTwoImg(image)) { return null; }
        try
        {
            TwoImgContainer.Read(image, out ReadOnlySpan<byte> blocks, out _);
            return blocks.ToArray();
        }
        catch (InvalidDataException)
        {
            return null;
        }
    }

    // Compares the disk's units with the file's, a unit the file lacks counting as changed.
    private static JsonObject Compare((string Unit, int Size, int PerTrack, int Encoded, int File) layout, byte[] encoded, byte[] file)
    {
        int units = Math.Max(encoded.Length - layout.Encoded, file.Length - layout.File) / layout.Size;
        List<int> changed = [];
        for (int unit = 0; unit < units; unit++)
        {
            ReadOnlySpan<byte> mine = Unit(encoded, layout.Encoded + (unit * layout.Size), layout.Size);
            ReadOnlySpan<byte> theirs = Unit(file, layout.File + (unit * layout.Size), layout.Size);
            if (!mine.SequenceEqual(theirs)) { changed.Add(unit); }
        }

        // Sectors are summed up by their tracks, blocks by themselves.
        List<int> named = layout.PerTrack == 0 ? changed : [.. changed.Select(unit => unit / layout.PerTrack).Distinct()];
        string noun = layout.PerTrack == 0 ? "block" : "track";
        return new JsonObject
        {
            ["unit"] = layout.Unit,
            ["count"] = changed.Count,
            ["summary"] = changed.Count == 0 ? "" : $"{noun}{(named.Count == 1 ? "" : "s")} {Runs(named)}",
        };
    }

    // A unit's bytes, empty past the end.
    private static ReadOnlySpan<byte> Unit(byte[] image, int offset, int size) =>
        offset >= image.Length ? [] : image.AsSpan(offset, Math.Min(size, image.Length - offset));

    // Numbers as runs, such as 3, 17-18, 40 and 2 more.
    private static string Runs(List<int> numbers)
    {
        List<(int First, int Last)> runs = [];
        foreach (int number in numbers)
        {
            if (runs.Count > 0 && runs[^1].Last == number - 1)
            {
                runs[^1] = (runs[^1].First, number);
            }
            else
            {
                runs.Add((number, number));
            }
        }

        string named = string.Join(", ", runs.Take(SummaryRuns).Select(run => run.First == run.Last ? $"{run.First}" : $"{run.First}-{run.Last}"));
        return runs.Count > SummaryRuns ? $"{named} and {runs.Count - SummaryRuns} more" : named;
    }
}
