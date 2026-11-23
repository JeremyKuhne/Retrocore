// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.ObjectModel;

namespace Retrocore.Assembler;

/// <summary>
///  The source lines an assembly's conditional assembly left out, for each file it opened.
/// </summary>
/// <remarks>
///  <para>
///   A line is assembled when the assembly took it in any pass over it: a file included twice, in one place where an
///   <c>.if</c> takes a branch and another where it skips it, has that branch assembled. A conditional directive's
///   own line is assembled when the branch around it is. A macro's body is assembled when its definition is: an
///   <c>.if</c> inside a body is decided again in each expansion, so expansions report nothing. A <c>.repeat</c>'s
///   body is assembled when some iteration took it, so a body repeated no times is skipped.
///  </para>
///  <para>
///   A file the assembly never opened, such as one only a skipped branch includes, has no entry: nothing says what
///   its lines would be.
///  </para>
///  <para>
///   Branches are chosen while sources are expanded, before code is laid out, so an error found later (an undefined
///   symbol, a branch out of range) leaves the report exact. After an error found while expanding, a later branch
///   may have been chosen from a definition the error lost, or never reached: every line decided from the first such
///   error on is undecided, and so is every line the assembly didn't reach. So is a line of a MACRO-10 source that
///   produced no statement, whose conditionals are expanded with the rest of its text and not reported.
///  </para>
/// </remarks>
public sealed class AssemblySkippedLines
{
    private static readonly StringComparer s_paths =
        Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

    private readonly Dictionary<string, int> _lineCounts;

    /// <summary>
    ///  Creates a report.
    /// </summary>
    /// <param name="lineCounts">Each opened file's line count, by full path.</param>
    /// <param name="skipped">Each opened file's skipped runs.</param>
    /// <param name="undecided">The undecided runs of the files that have some.</param>
    internal AssemblySkippedLines(
        Dictionary<string, int> lineCounts,
        Dictionary<string, AssemblyLineRange[]> skipped,
        Dictionary<string, AssemblyLineRange[]> undecided)
    {
        _lineCounts = lineCounts;
        Skipped = ReadOnly(skipped);
        Undecided = ReadOnly(undecided);
    }

    /// <summary>
    ///  Gets the paths comparer the report uses: ignoring case where the file system does.
    /// </summary>
    internal static StringComparer PathComparer => s_paths;

    /// <summary>
    ///  Gets, for each file the assembly opened by full path, the runs of lines it skipped, in line order; a file
    ///  it skipped nothing of has none.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<AssemblyLineRange>> Skipped { get; }

    /// <summary>
    ///  Gets, by full path, the runs of lines whose state this assembly can't vouch for, in line order; only files
    ///  that have such lines are here, and none are when expansion found no error.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<AssemblyLineRange>> Undecided { get; }

    /// <summary>
    ///  Gets whether every line of every opened file is known to be assembled or skipped.
    /// </summary>
    public bool IsComplete => Undecided.Count == 0;

    /// <summary>
    ///  Gets whether the assembly assembled a source line.
    /// </summary>
    /// <param name="path">The file, as any path that names it.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>
    ///  Whether the line was assembled; null when it is undecided, past the file's end, or in a file the assembly
    ///  never opened.
    /// </returns>
    public bool? IsAssembled(string path, int line)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (path.Length == 0) { return null; }
        string full = Path.GetFullPath(path);
        if (!_lineCounts.TryGetValue(full, out int count) || line < 0 || line >= count) { return null; }
        bool undecided = Undecided.TryGetValue(full, out IReadOnlyList<AssemblyLineRange>? runs) && In(runs, line);
        return undecided ? null : !In(Skipped[full], line);
    }

    // Binary search of sorted, disjoint runs.
    private static bool In(IReadOnlyList<AssemblyLineRange> ranges, int line)
    {
        int low = 0;
        int high = ranges.Count - 1;
        while (low <= high)
        {
            int middle = low + ((high - low) / 2);
            AssemblyLineRange range = ranges[middle];
            if (line < range.Start) { high = middle - 1; }
            else if (line >= range.End) { low = middle + 1; }
            else { return true; }
        }

        return false;
    }

    private static ReadOnlyDictionary<string, IReadOnlyList<AssemblyLineRange>> ReadOnly(Dictionary<string, AssemblyLineRange[]> runs)
    {
        Dictionary<string, IReadOnlyList<AssemblyLineRange>> copy = [with(runs.Count, s_paths)];
        foreach (KeyValuePair<string, AssemblyLineRange[]> pair in runs)
        {
            copy[pair.Key] = Array.AsReadOnly(pair.Value);
        }

        return new(copy);
    }

    /// <summary>
    ///  Creates the report of files that had no conditionals, each assembled whole.
    /// </summary>
    /// <param name="path">The file's path.</param>
    /// <param name="lineCount">Its line count.</param>
    /// <returns>The report.</returns>
    internal static AssemblySkippedLines Whole(string path, int lineCount)
    {
        Dictionary<string, int> counts = [with(s_paths)];
        Dictionary<string, AssemblyLineRange[]> skipped = [with(s_paths)];
        if (path.Length != 0)
        {
            string full = Path.GetFullPath(path);
            counts[full] = lineCount;
            skipped[full] = [];
        }

        return new(counts, skipped, [with(s_paths)]);
    }
}
