// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  What a floppy image format cannot hold of a disk, gathered by kind with the tracks each is on, so a disk whose
///  every track is double density says so once.
/// </summary>
internal sealed class FloppyLosses
{
    private readonly List<(string What, SortedSet<int> Tracks)> _byTrack = [];
    private readonly List<string> _whole = [];

    /// <summary>
    ///  Gets whether nothing is lost.
    /// </summary>
    public bool IsEmpty => _byTrack.Count == 0 && _whole.Count == 0;

    /// <summary>
    ///  Records a loss on a track.
    /// </summary>
    /// <param name="what">What is lost, such as <c>Double-density sectors</c>.</param>
    /// <param name="cylinder">The track it is on.</param>
    public void Add(string what, int cylinder)
    {
        int index = _byTrack.FindIndex(loss => loss.What == what);
        if (index < 0)
        {
            _byTrack.Add((what, []));
            index = _byTrack.Count - 1;
        }

        _byTrack[index].Tracks.Add(cylinder);
    }

    /// <summary>
    ///  Records a loss of the whole disk, said as a sentence.
    /// </summary>
    /// <param name="sentence">The loss.</param>
    public void Add(string sentence)
    {
        if (!_whole.Contains(sentence)) { _whole.Add(sentence); }
    }

    /// <summary>
    ///  Gets the losses, each a sentence: <c>Double-density sectors, on tracks 0-39.</c>
    /// </summary>
    /// <returns>The losses.</returns>
    public IReadOnlyList<string> ToList() =>
        [.. _whole, .. _byTrack.Select(loss => $"{loss.What}, on {Where(loss.Tracks)}.")];

    // "track 3", or "tracks 0-2, 5".
    private static string Where(SortedSet<int> tracks)
    {
        List<string> runs = [];
        int? start = null;
        int previous = -2;
        foreach (int track in tracks)
        {
            if (start is not null && track == previous + 1)
            {
                previous = track;
                continue;
            }

            if (start is { } first) { runs.Add(first == previous ? $"{first}" : $"{first}-{previous}"); }
            start = track;
            previous = track;
        }

        if (start is { } last) { runs.Add(last == previous ? $"{last}" : $"{last}-{previous}"); }
        return (tracks.Count == 1 ? "track " : "tracks ") + string.Join(", ", runs);
    }
}
