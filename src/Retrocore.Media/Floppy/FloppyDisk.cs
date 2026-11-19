// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  A soft-sectored floppy disk as its sectors: each physical track's sectors in the order they pass the head.
/// </summary>
/// <remarks>
///  <para>
///   The JV1, JV3, JVC, DMK and IMD formats load into this model, so a controller sees one representation. It is a
///   medium: a controller changes it only through <see cref="Write"/> and <see cref="Format"/>, which count the
///   change, and its snapshot is a DMK image, which holds every ID, mark, density, CRC error and order it has.
///  </para>
///  <para>
///   A track holds what a DMK track can: at most 64 sectors, in at most 16 KB with no gaps between fields, more
///   than any controller formats on a 5¼- or 8-inch disk. Cylinders run from 0 to 254 on sides 0 and 1.
///  </para>
/// </remarks>
public sealed class FloppyDisk : IMedium
{
    /// <summary>
    ///  The most cylinders a disk has.
    /// </summary>
    public const int MaximumCylinders = 255;

    private readonly Dictionary<(int Cylinder, int Side), List<FloppySector>> _tracks = [];
    private bool _writeProtected;

    /// <summary>
    ///  Gets or sets whether the disk is write-protected; a change counts in <see cref="Version"/>.
    /// </summary>
    public bool IsWriteProtected
    {
        get => _writeProtected;
        set
        {
            if (value == _writeProtected) { return; }
            _writeProtected = value;
            Version++;
        }
    }

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether writes or formatting have changed the disk since it was loaded or last saved.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <summary>
    ///  Gets the highest cylinder with sectors, plus one.
    /// </summary>
    public int Cylinders => Tracks().Select(track => track.Cylinder + 1).DefaultIfEmpty(0).Max();

    /// <summary>
    ///  Gets the number of sides with sectors.
    /// </summary>
    public int Sides => Tracks().Any(track => track.Side == 1) ? 2 : 1;

    /// <summary>
    ///  Gets the sectors of a physical track in rotational order, or an empty list for an unformatted track.
    /// </summary>
    /// <param name="cylinder">The cylinder the head is on.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <returns>The sectors.</returns>
    public IReadOnlyList<FloppySector> Track(int cylinder, int side) =>
        _tracks.TryGetValue((cylinder, side), out List<FloppySector>? sectors) ? sectors : [];

    /// <summary>
    ///  Adds a sector at the end of a physical track, as an image is read; the disk is not changed by it.
    /// </summary>
    /// <param name="cylinder">The cylinder, 0-254.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <param name="sector">The sector.</param>
    /// <exception cref="InvalidDataException">
    ///  The cylinder or side is not on a disk, or the track would hold more than a disk's track can.
    /// </exception>
    public void Add(int cylinder, int side, FloppySector sector)
    {
        ArgumentNullException.ThrowIfNull(sector);
        if (cylinder is < 0 or >= MaximumCylinders || side is not (0 or 1))
        {
            throw new InvalidDataException($"A disk has cylinders 0-{MaximumCylinders - 1} on sides 0 and 1, not cylinder {cylinder} side {side}.");
        }

        if (!_tracks.TryGetValue((cylinder, side), out List<FloppySector>? sectors))
        {
            sectors = [];
            _tracks.Add((cylinder, side), sectors);
        }

        if (!DmkFormat.Fits([.. sectors, sector]))
        {
            throw new InvalidDataException($"Cylinder {cylinder} side {side} holds more sectors than a track can.");
        }

        sectors.Add(sector);
    }

    /// <summary>
    ///  Writes a sector's data field, as the write sector command does: its data and mark, with a good CRC unless the
    ///  write was cut short.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The controller checks the write-protect notch as the command starts, so the disk takes the write as given.
    ///  </para>
    /// </remarks>
    /// <param name="sector">A sector of this disk.</param>
    /// <param name="data">The data, the sector's size.</param>
    /// <param name="dataAddressMark">The data address mark, <c>$F8</c>-<c>$FB</c>.</param>
    /// <param name="crcError">
    ///  Whether the field was left without its CRC, as when the controller stops writing partway: the bytes written
    ///  stay, the rest are what was there, and reading it reports a CRC error.
    /// </param>
    /// <exception cref="ArgumentException">The data is not the sector's size, or the mark is no data mark.</exception>
    public void Write(FloppySector sector, ReadOnlySpan<byte> data, byte dataAddressMark, bool crcError = false)
    {
        ArgumentNullException.ThrowIfNull(sector);
        sector.Overwrite(data, dataAddressMark, crcError);
        Changed();
    }

    /// <summary>
    ///  Replaces a physical track's sectors, as formatting does.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A track keeps the sectors, in order, that fit on it: a controller formats far fewer than a track holds.
    ///  </para>
    /// </remarks>
    /// <param name="cylinder">The cylinder, 0-254.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <param name="sectors">The new sectors in rotational order.</param>
    public void Format(int cylinder, int side, IEnumerable<FloppySector> sectors)
    {
        ArgumentNullException.ThrowIfNull(sectors);
        ArgumentOutOfRangeException.ThrowIfNegative(cylinder);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(cylinder, MaximumCylinders);
        if (side is not (0 or 1)) { throw new ArgumentOutOfRangeException(nameof(side)); }
        List<FloppySector> track = [];
        foreach (FloppySector sector in sectors)
        {
            if (!DmkFormat.Fits([.. track, sector])) { break; }
            track.Add(sector);
        }

        _tracks[(cylinder, side)] = track;
        Changed();
    }

    /// <summary>
    ///  Enumerates every track that has sectors, by cylinder then side.
    /// </summary>
    /// <returns>The cylinder, side and sectors of each track.</returns>
    public IEnumerable<(int Cylinder, int Side, IReadOnlyList<FloppySector> Sectors)> Tracks() =>
        _tracks.Where(pair => pair.Value.Count != 0)
            .OrderBy(pair => pair.Key.Cylinder).ThenBy(pair => pair.Key.Side)
            .Select(pair => (pair.Key.Cylinder, pair.Key.Side, (IReadOnlyList<FloppySector>)pair.Value));

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The snapshot is a DMK image (<see cref="DmkFormat.SnapshotKind"/>), which holds all of the disk; read it with
    ///   <see cref="DmkFormat.ReadSnapshot"/>, which takes its size codes as they are.
    ///  </para>
    /// </remarks>
    public MediumSnapshot Snapshot() => new(DmkFormat.SnapshotKind, Version, _writeProtected, DmkFormat.Write(this));

    /// <summary>
    ///  Records that the disk was saved to an image that holds all of it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the disk differs from its image, as after a save that could not hold all of it.
    /// </summary>
    public void MarkChanged() => IsDirty = true;

    private void Changed()
    {
        IsDirty = true;
        Version++;
    }
}
