// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Writes a Commodore GCR disk as a G64 image, which holds every cell, or as an image of its sectors, D64 for DOS 2
///  or D67 for DOS 1, which loses anything else on the disk and any sector the drive could not read.
/// </summary>
/// <remarks>
///  <para>
///   A sector image lists as losses the sectors that do not read, the good sectors its layout has no place for (a
///   DOS 1 disk's 20th sector on tracks 18-24, in a D64), and anything at a half-track or past track 35, so a save
///   asks before dropping them.
///  </para>
/// </remarks>
/// <param name="format"><c>G64</c>, <c>D64</c> or <c>D67</c>.</param>
public sealed class CommodoreDiskCodec(string format = "G64") : IImageCodec
{
    /// <inheritdoc/>
    public string Format { get; } = format is "G64" or "D64" or "D67"
        ? format
        : throw new ArgumentException("A Commodore disk is written as G64, D64 or D67.", nameof(format));

    /// <summary>
    ///  Reads a disk image, G64, D64 or D67, by its contents.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk, and the codec that writes it back.</returns>
    /// <exception cref="InvalidDataException">The file is none of them.</exception>
    public static (CommodoreDisk Disk, CommodoreDiskCodec Codec) Load(ReadOnlySpan<byte> image)
    {
        if (G64Format.IsG64(image)) { return (G64Format.Read(image), new("G64")); }
        if (D64Format.IsD64(image)) { return (D64Format.Read(image), new("D64")); }
        if (D67Format.IsD67(image)) { return (D67Format.Read(image), new("D67")); }
        throw new InvalidDataException("The file is neither a G64 image nor a D64 or D67 image's size.");
    }

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != CommodoreDisk.SnapshotKind)
        {
            throw new ArgumentException($"A {Format} image holds a Commodore disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        // None of the formats keeps the write-protect tab, as bare block images keep no lock.
        if (Format == "G64") { return new(snapshot.Image.ToArray(), Losses: []); }
        CommodoreDisk disk = G64Format.Read(snapshot.Image.Span);
        CommodoreDos dos = Format == "D67" ? CommodoreDos.Dos1 : CommodoreDos.Dos2;
        (byte[] image, IReadOnlyList<string> unreadable) = D64Format.WriteSectors(disk, dos, out IReadOnlyList<string> unwritten);
        return new(image,
        [
            .. unreadable.Select(sector => $"{sector}, which does not read, written as zeros."),
            .. D64Format.Omitted(disk, dos).Select(place => $"{place}, which a {Format} image has no place for."),
            .. D64Format.Conflicting(disk, dos).Select(sector => $"{sector}, which holds two good copies that differ; the first is kept.")
        ])
        {
            // DOS 1 formats a sector's header alone; its zeros are what the sector holds until it is first written.
            Notes = unwritten.Count == 0
                ? []
                : [$"{unwritten.Count} sector{(unwritten.Count == 1 ? "" : "s")} DOS 1 formatted but never wrote, kept as zeros."]
        };
    }
}
