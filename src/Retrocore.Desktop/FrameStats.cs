// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  The times between the display's frames, and how many drew a new picture, for the status bar and the smoke run.
/// </summary>
internal sealed class FrameStats
{
    private readonly List<double> _intervals = new(capacity: 4096);
    private TimeSpan? _last;
    private int _secondFrames;
    private TimeSpan _secondStart;

    /// <summary>
    ///  Gets when the first display frame came, by the wall clock.
    /// </summary>
    internal DateTime? FirstFrame { get; private set; }

    /// <summary>
    ///  Gets the display frames in the last whole second.
    /// </summary>
    internal int FramesPerSecond { get; private set; }

    /// <summary>
    ///  Gets the display frames counted.
    /// </summary>
    internal int Frames => _intervals.Count;

    /// <summary>
    ///  Gets the display frames that drew a new picture.
    /// </summary>
    internal int Drawn { get; private set; }

    /// <summary>
    ///  Records a display frame.
    /// </summary>
    /// <param name="time">The frame's time.</param>
    /// <param name="drew">Whether it drew a new picture.</param>
    internal void Frame(TimeSpan time, bool drew)
    {
        FirstFrame ??= DateTime.Now;
        if (_last is { } last) { _intervals.Add((time - last).TotalMilliseconds); }
        _last = time;
        if (drew) { Drawn++; }

        _secondFrames++;
        if (time - _secondStart >= TimeSpan.FromSeconds(1))
        {
            FramesPerSecond = _secondFrames;
            _secondFrames = 0;
            _secondStart = time;
        }
    }

    /// <summary>
    ///  Forgets the frames so far, as after the window settles.
    /// </summary>
    internal void Restart()
    {
        _intervals.Clear();
        Drawn = 0;
        _last = null;
    }

    /// <summary>
    ///  Gets a percentile of the times between frames.
    /// </summary>
    /// <param name="percent">The percentile, 0 to 100.</param>
    /// <returns>The time in milliseconds, or 0 with too few frames.</returns>
    internal double Percentile(double percent)
    {
        if (_intervals.Count == 0) { return 0; }
        double[] sorted = [.. _intervals];
        Array.Sort(sorted);
        return sorted[Math.Clamp((int)Math.Ceiling(percent / 100 * sorted.Length) - 1, 0, sorted.Length - 1)];
    }
}