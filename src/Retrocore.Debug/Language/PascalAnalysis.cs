// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Pascal.Source;

namespace Retrocore.Debug.Language;

/// <summary>
///  A Pascal program's analysis, and when each file it read from disk was last written, so that it is analyzed again
///  once one changes.
/// </summary>
/// <param name="Program">The program.</param>
/// <param name="Stamps">Each file read from disk, and when it was last written.</param>
internal sealed record PascalAnalysis(PascalProgram Program, Dictionary<string, DateTime> Stamps)
{
    /// <summary>
    ///  Gets whether no file it read from disk has changed since.
    /// </summary>
    /// <returns>Whether it is current.</returns>
    public bool IsCurrent() => Stamps.All(stamp => Stamp(stamp.Key) == stamp.Value);

    /// <summary>
    ///  Gets when a file was last written, or <see cref="DateTime.MinValue"/> when it isn't there or can't be read.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The time, in UTC.</returns>
    public static DateTime Stamp(string path)
    {
        try
        {
            return File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return DateTime.MinValue;
        }
    }
}
