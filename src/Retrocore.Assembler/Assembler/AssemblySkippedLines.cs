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
///   own line is assembled when the branch around it is, except that one carrying a label, such as
///   <c>Done: .endif</c>, is assembled when the label is defined: when the branch it closes was taken.
///  </para>
///  <para>
///   Each expansion of a macro is a pass over its body, so a body line is assembled when some expansion took it: a
///   branch of an <c>.if</c> in the body that no expansion took is skipped, as is the body of a macro never invoked,
///   while its <c>.macro</c> and <c>.endmacro</c> lines go with the definition. A <c>.repeat</c>'s body is likewise
///   assembled when some iteration took it, so a body repeated no times is skipped.
///  </para>
///  <para>
///   A file the assembly never opened, such as one only a skipped branch includes, has no entry: nothing says what
///   its lines would be.
///  </para>
///  <para>
///   Branches are chosen while sources are expanded, before code is laid out, so an error found later (an undefined
///   symbol, a branch out of range) leaves the report exact. An error found while expanding, a line that doesn't
///   parse included, may lose a definition a later branch depends on: every line decided from the first such error
///   on is undecided, and so is every line the assembly didn't reach. A line skipped before the error stays skipped
///   only in a root source outside a macro's body; in an included file or a body, the error may have prevented a
///   later inclusion or expansion that would assemble it, so it is undecided. An expansion stopped at its line limit
///   leaves every line it did not assemble undecided.
///  </para>
///  <para>
///   A MACRO-10 source's conditionals are expanded with the rest of its text and not reported, so a line of one is
///   assembled when its expander passed it on and undecided otherwise, error or not; when its expansion reports an
///   error, every line of it is undecided. A source without preprocessing directives, parsed directly, has no
///   conditionals: its lines are assembled but for those that didn't parse, which are undecided.
///  </para>
/// </remarks>
public sealed class AssemblySkippedLines
{
    private static readonly StringComparer s_paths =
        Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

    private readonly Dictionary<string, int> _lineCounts;
    private readonly bool _knowsEveryFile;

    /// <summary>
    ///  Creates a report.
    /// </summary>
    /// <param name="lineCounts">Each opened file's line count, by full path.</param>
    /// <param name="skipped">Each opened file's skipped runs.</param>
    /// <param name="undecided">The undecided runs of the files that have some.</param>
    /// <param name="knowsEveryFile">
    ///  Whether every file the assembly would open is in the report: false after an expansion error, which may have
    ///  refused or never reached one, or when a source had no path to record.
    /// </param>
    internal AssemblySkippedLines(
        Dictionary<string, int> lineCounts,
        Dictionary<string, AssemblyLineRange[]> skipped,
        Dictionary<string, AssemblyLineRange[]> undecided,
        bool knowsEveryFile)
    {
        _lineCounts = lineCounts;
        _knowsEveryFile = knowsEveryFile;
        Skipped = ReadOnly(skipped);
        Undecided = ReadOnly(undecided);
    }

    /// <summary>
    ///  Gets the paths comparer the report uses: ignoring case where the file system does.
    /// </summary>
    internal static StringComparer PathComparer => s_paths;

    /// <summary>
    ///  Gets, for each file the assembly opened by full path, the runs of lines it skipped, in line order; a file
    ///  it skipped nothing of has an empty list.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<AssemblyLineRange>> Skipped { get; }

    /// <summary>
    ///  Gets, by full path, the runs of lines whose state this assembly can't vouch for, in line order; only files
    ///  that have such lines are here: none when parsing found no error, except in MACRO-10 sources.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<AssemblyLineRange>> Undecided { get; }

    /// <summary>
    ///  Gets whether every line of every opened file is known to be assembled or skipped.
    /// </summary>
    public bool IsComplete => Undecided.Count == 0;

    /// <summary>
    ///  Gets whether the assembly opened a file.
    /// </summary>
    /// <param name="path">The file, as any path that names it.</param>
    /// <returns>Whether it is in the report.</returns>
    public bool Opened(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        return path.Length != 0 && _lineCounts.ContainsKey(FullPath(path));
    }

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
        return State(path, line, out _);
    }

    /// <summary>
    ///  Gets whether a line is in the build: whether it was assembled, false in a file the assembly never opened when
    ///  the report knows every file it would open, and null when that can't be told.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>Whether the line is in the build, or null.</returns>
    internal bool? InBuild(string path, int line)
    {
        bool? assembled = State(path, line, out bool opened);

        // After an expansion error the file may be one the assembly would have opened but refused or never reached.
        return opened ? assembled : _knowsEveryFile ? false : null;
    }

    private bool? State(string path, int line, out bool opened)
    {
        opened = false;
        if (path.Length == 0) { return null; }
        string full = FullPath(path);
        if (!_lineCounts.TryGetValue(full, out int count)) { return null; }
        opened = true;
        if (line < 0 || line >= count) { return null; }
        bool undecided = Undecided.TryGetValue(full, out IReadOnlyList<AssemblyLineRange>? runs) && In(runs, line);
        return undecided ? null : !In(Skipped[full], line);
    }

    /// <summary>
    ///  Gets the full path the report keys a file by, or the path as given when it names no file the platform can
    ///  resolve.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <returns>The key.</returns>
    internal static string FullPath(string path)
    {
        try
        {
            return Path.GetFullPath(path);
        }
        catch (Exception failure) when (failure is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return path;
        }
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
    ///  Creates the report of a source that had no conditionals, assembled whole but for the lines that didn't parse.
    /// </summary>
    /// <param name="path">The file's path.</param>
    /// <param name="lineCount">Its line count.</param>
    /// <param name="errors">The zero-based lines that didn't parse, in order, or null.</param>
    /// <returns>The report.</returns>
    internal static AssemblySkippedLines Whole(string path, int lineCount, IReadOnlyList<int>? errors)
    {
        Dictionary<string, int> counts = [with(s_paths)];
        Dictionary<string, AssemblyLineRange[]> skipped = [with(s_paths)];
        Dictionary<string, AssemblyLineRange[]> undecided = [with(s_paths)];

        // A source without conditionals includes nothing, so its own file is every file.
        if (path.Length != 0)
        {
            string full = FullPath(path);
            counts[full] = lineCount;
            skipped[full] = [];
            if (errors is { Count: > 0 })
            {
                List<AssemblyLineRange> runs = [];
                foreach (int line in errors)
                {
                    if (runs.Count != 0 && line < runs[^1].End) { continue; }
                    if (runs.Count != 0 && line == runs[^1].End)
                    {
                        runs[^1] = new(runs[^1].Start, runs[^1].Count + 1);
                        continue;
                    }

                    runs.Add(new(line, 1));
                }

                undecided[full] = [.. runs];
            }
        }

        // A line that didn't parse might have been a misspelled .include, so with one the files are not all known.
        return new(counts, skipped, undecided, knowsEveryFile: path.Length != 0 && errors is not { Count: > 0 });
    }
}
