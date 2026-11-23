// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    // Each opened file's lines, by the path its sources and locations carry.
    private readonly Dictionary<string, FileLines> _fileLines = [with(StringComparer.Ordinal)];

    // The file the last marked line was in: a file's lines share its path's string, so most lookups are one compare.
    private string? _markedPath;
    private FileLines? _marked;

    /// <summary>
    ///  Notes a file the assembly opened, once however often it is included.
    /// </summary>
    /// <param name="path">The file's path.</param>
    /// <param name="count">Its line count.</param>
    /// <param name="opaque">Whether lines no pass took may still be assembled.</param>
    private void OpenLines(string path, int count, bool opaque = false)
    {
        if (path.Length == 0 || _fileLines.ContainsKey(path)) { return; }
        _fileLines[path] = new(count, opaque);
    }

    /// <summary>
    ///  Notes a file whose lines are not read one at a time, such as a MACRO-10 source.
    /// </summary>
    /// <param name="source">The file.</param>
    private void OpenOpaqueLines(AssemblySource source)
    {
        if (source.Path.Length == 0 || _fileLines.ContainsKey(source.Path)) { return; }
        int count = 0;
        foreach (ReadOnlyMemory<char> _ in new AssemblyLines(source.Text.AsMemory())) { count++; }
        OpenLines(source.Path, count, opaque: true);
    }

    /// <summary>
    ///  Notes that a pass reached a physical line, and whether it assembled it.
    /// </summary>
    /// <param name="location">The line's location; a macro expansion's lines are its body's.</param>
    /// <param name="assembled">Whether the branch around it was taken.</param>
    private void MarkLine(AssemblyLocation location, bool assembled)
    {
        string path = location.Path;
        if (!ReferenceEquals(path, _markedPath))
        {
            _markedPath = path;
            _marked = _fileLines.TryGetValue(path, out FileLines? found) ? found : null;
        }

        if (_marked is not { } lines || (uint)location.Line >= (uint)lines.Visited.Length) { return; }
        int line = location.Line;
        lines.Visited[line] = _visited;
        if (assembled && lines.Assembled[line] == int.MaxValue) { lines.Assembled[line] = _visited; }
    }

    /// <summary>
    ///  Reports each opened file's skipped and undecided lines.
    /// </summary>
    /// <returns>The report.</returns>
    private AssemblySkippedLines SkippedLines()
    {
        // A choice made at or after the first error may rest on what the error lost.
        int trusted = int.MaxValue;
        foreach ((int Order, AssemblyDiagnostic Diagnostic) error in _diagnostics)
        {
            trusted = Math.Min(trusted, error.Order);
        }

        bool errors = trusted != int.MaxValue;

        StringComparer paths = AssemblySkippedLines.PathComparer;
        Dictionary<string, int> counts = [with(paths)];
        Dictionary<string, byte[]> states = [with(paths)];
        foreach (KeyValuePair<string, FileLines> file in _fileLines)
        {
            FileLines lines = file.Value;
            string full = AssemblySkippedLines.FullPath(file.Key);
            int count = lines.Visited.Length;

            // Two spellings of one file are one file: a line either pass assembled is assembled.
            if (!states.TryGetValue(full, out byte[]? state))
            {
                states[full] = state = new byte[count];
                counts[full] = count;
            }

            for (int line = 0; line < count && line < state.Length; line++)
            {
                LineState here;
                if (lines.Assembled[line] < trusted) { here = LineState.Assembled; }
                else if (lines.Opaque) { here = LineState.Undecided; }

                // Without an error a line no pass took was skipped: in a branch not taken, or a body repeated no
                // times. With one, only a line every pass reached before the error is known to be.
                else
                {
                    // A stopped expansion cut short passes that might have assembled a line an earlier one skipped.
                    bool reached = !_stopped && lines.Visited[line] >= 0 && lines.Visited[line] < trusted;
                    here = !errors || reached ? LineState.Skipped : LineState.Undecided;
                }

                // Assembled anywhere wins, then undecided, then skipped.
                state[line] = (byte)Math.Max(state[line], (byte)here);
            }
        }

        Dictionary<string, AssemblyLineRange[]> skipped = [with(paths)];
        Dictionary<string, AssemblyLineRange[]> undecided = [with(paths)];
        foreach (KeyValuePair<string, byte[]> file in states)
        {
            string full = file.Key;
            byte[] state = file.Value;
            skipped[full] = Runs(state, LineState.Skipped);
            AssemblyLineRange[] unknown = Runs(state, LineState.Undecided);
            if (unknown.Length != 0) { undecided[full] = unknown; }
        }

        return new(counts, skipped, undecided);
    }

    private static AssemblyLineRange[] Runs(byte[] states, LineState wanted)
    {
        List<AssemblyLineRange>? runs = null;
        for (int line = 0; line < states.Length; line++)
        {
            if (states[line] != (byte)wanted) { continue; }
            int start = line;
            while (line + 1 < states.Length && states[line + 1] == (byte)wanted) { line++; }
            (runs ??= []).Add(new(start, line - start + 1));
        }

        return runs is null ? [] : [.. runs];
    }
}
