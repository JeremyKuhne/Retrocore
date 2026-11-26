// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Tests;

/// <summary>
///  The schedule of keystrokes the TRS-80 oracles' MAME scripts (<c>tools\Trs80Oracle.lua</c>,
///  <c>tools\Trs80Model3Oracle.lua</c>) type, and the log of when each entry fired.
/// </summary>
/// <remarks>
///  <para>
///   The scripts read a time as digits and a '.', and split the schedule at '|'. So a time is written in plain
///   decimal, never with an exponent or a culture's comma, and an entry's text may not hold a '|'.
///  </para>
/// </remarks>
internal static class MameSchedule
{
    /// <summary>
    ///  The latest an entry may fire after its time: MAME checks the schedule once a frame, and every machine the
    ///  oracles run draws at least 50 frames a second, so a frame (0.02 s) and a margin.
    /// </summary>
    internal const double FrameSeconds = 0.025;

    /// <summary>
    ///  Formats a time for <c>RETRO_SCRIPT</c> or <c>RETRO_END</c>: plain decimal, with a '.' before any fraction,
    ///  whatever the culture.
    /// </summary>
    /// <param name="seconds">The emulated second; zero or more, and finite.</param>
    /// <returns>
    ///  The time to 15 significant digits or 15 decimals, whichever is fewer, such as <c>2.5</c>, <c>3</c> or
    ///  <c>0.00001</c>.
    /// </returns>
    /// <exception cref="ArgumentOutOfRangeException">
    ///  <paramref name="seconds"/> is negative, infinite or not a number.
    /// </exception>
    internal static string Seconds(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(seconds), seconds, "A schedule time is a finite second, zero or more.");
        }

        // "R" and the default format write 1E-05 and 1E+15, which the scripts can't read. A custom format keeps at
        // most 15 significant digits, and writes -0 for negative zero, so zero is written on its own.
        return seconds == 0 ? "0" : seconds.ToString("0.###############", CultureInfo.InvariantCulture);
    }

    /// <summary>
    ///  Formats a schedule entry for <c>RETRO_SCRIPT</c>: the time (see <see cref="Seconds"/>), <c>=</c>, then the
    ///  text with <c>\r</c> for ENTER. For the Model III, 4 and II script the text may instead be a key's
    ///  <c>@port,field,state</c>.
    /// </summary>
    /// <param name="entry">The emulated second to act at, and the text to type or the key to set.</param>
    /// <returns>The entry as <c>seconds=text</c>.</returns>
    /// <exception cref="ArgumentException">The text holds a '|', which separates entries.</exception>
    internal static string Entry((double At, string Text) entry)
    {
        if (entry.Text.Contains('|', StringComparison.Ordinal))
        {
            throw new ArgumentException("A schedule entry's text can't hold '|', which separates entries.", nameof(entry));
        }

        return $"{Seconds(entry.At)}={entry.Text.Replace("\r", "\\r", StringComparison.Ordinal)}";
    }

    /// <summary>
    ///  Formats a whole schedule for <c>RETRO_SCRIPT</c>.
    /// </summary>
    /// <param name="script">The entries, in the order they fire.</param>
    /// <returns>The entries, separated by '|'.</returns>
    /// <exception cref="ArgumentException">
    ///  An entry's time is before the one ahead of it: the scripts fire entries in turn, so it would fire late.
    /// </exception>
    internal static string Script(IEnumerable<(double At, string Text)> script)
    {
        double previous = double.NegativeInfinity;
        foreach ((double at, _) in script)
        {
            if (at < previous)
            {
                throw new ArgumentException($"The schedule goes back from {previous} to {at} seconds.", nameof(script));
            }

            previous = at;
        }

        return string.Join('|', script.Select(Entry));
    }

    /// <summary>
    ///  Checks the script's <c>RETRO_FIRED</c> log: every entry fired, in order, at its time or within <see cref="FrameSeconds"/> after.
    /// </summary>
    /// <param name="script">The schedule MAME was given.</param>
    /// <param name="log">
    ///  The log, a line per entry fired: the entry's time, <c>=</c>, then the emulated second it fired, each to six
    ///  decimals.
    /// </param>
    internal static void ShouldHaveFiredOnTime((double At, string Text)[] script, string log)
    {
        string[] lines = log.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        lines.Should().HaveCount(script.Length, "MAME fires every entry before the end");
        for (int i = 0; i < script.Length; i++)
        {
            string[] parts = lines[i].Split('=');
            double at = double.Parse(parts[0], CultureInfo.InvariantCulture);
            double fired = double.Parse(parts[1], CultureInfo.InvariantCulture);
            at.Should().BeApproximately(script[i].At, 1e-6, "entry {0} is the schedule's", i);
            fired.Should().BeInRange(at, at + FrameSeconds, "entry {0}, at {1} s, fires on its frame", i, at);
        }
    }
}
