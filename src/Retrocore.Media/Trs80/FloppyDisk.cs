// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A soft-sectored floppy disk as its sectors: each physical track's sectors in the order they pass the head.
/// </summary>
/// <remarks>
///  <para>
///   The JV1 and JV3 formats load into and save from this model, so a controller sees one representation.
///  </para>
/// </remarks>
public sealed class FloppyDisk
{
    private readonly Dictionary<(int Cylinder, int Side), List<FloppySector>> _tracks = [];

    /// <summary>
    ///  Gets or sets whether the disk is write-protected.
    /// </summary>
    public bool WriteProtected { get; set; }

    /// <summary>
    ///  Gets the highest cylinder with sectors, plus one.
    /// </summary>
    public int Cylinders => _tracks.Count == 0 ? 0 : _tracks.Keys.Max(key => key.Cylinder) + 1;

    /// <summary>
    ///  Gets the number of sides with sectors.
    /// </summary>
    public int Sides => _tracks.Keys.Any(key => key.Side == 1) ? 2 : 1;

    /// <summary>
    ///  Gets the sectors of a physical track in rotational order, or an empty list for an unformatted track.
    /// </summary>
    /// <param name="cylinder">The cylinder the head is on.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <returns>The sectors.</returns>
    public IReadOnlyList<FloppySector> Track(int cylinder, int side) =>
        _tracks.TryGetValue((cylinder, side), out List<FloppySector>? sectors) ? sectors : [];

    /// <summary>
    ///  Adds a sector at the end of a physical track.
    /// </summary>
    /// <param name="cylinder">The cylinder.</param>
    /// <param name="side">The side.</param>
    /// <param name="sector">The sector.</param>
    public void Add(int cylinder, int side, FloppySector sector)
    {
        ArgumentNullException.ThrowIfNull(sector);
        if (!_tracks.TryGetValue((cylinder, side), out List<FloppySector>? sectors))
        {
            sectors = [];
            _tracks.Add((cylinder, side), sectors);
        }

        sectors.Add(sector);
    }

    /// <summary>
    ///  Replaces a physical track's sectors, as formatting does.
    /// </summary>
    /// <param name="cylinder">The cylinder.</param>
    /// <param name="side">The side.</param>
    /// <param name="sectors">The new sectors in rotational order.</param>
    public void Format(int cylinder, int side, IEnumerable<FloppySector> sectors) =>
        _tracks[(cylinder, side)] = [.. sectors];

    /// <summary>
    ///  Enumerates every track that has sectors, by cylinder then side.
    /// </summary>
    /// <returns>The cylinder, side and sectors of each track.</returns>
    public IEnumerable<(int Cylinder, int Side, IReadOnlyList<FloppySector> Sectors)> Tracks() =>
        _tracks.OrderBy(pair => pair.Key.Cylinder).ThenBy(pair => pair.Key.Side)
            .Select(pair => (pair.Key.Cylinder, pair.Key.Side, (IReadOnlyList<FloppySector>)pair.Value));
}
