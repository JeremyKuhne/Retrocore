// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Documentation;

/// <summary>
///  What the assembler took from one source file, so its documentation follows the same <c>.using</c> lines.
/// </summary>
/// <param name="UsingAssembled">Whether the <c>.using</c> on a zero-based line was assembled.</param>
/// <param name="InvokedUsings">The names of each <c>.using</c> a macro invoked on a line produced.</param>
public sealed record DocumentationAssembled(Func<int, bool> UsingAssembled, Func<int, IReadOnlyList<string[]>> InvokedUsings)
{
    /// <summary>
    ///  Gets what an assembly took from one of its sources.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="path">The source's path.</param>
    /// <returns>The source's <c>.using</c> lines, or null when the assembly failed and they are not known.</returns>
    public static DocumentationAssembled? From(AssemblyResult result, string path)
    {
        if (!result.Success) { return null; }
        string full = Path.GetFullPath(path);
        HashSet<int> lines = [];
        Dictionary<int, List<string[]>> invoked = [];
        foreach (AssemblyUsing directive in result.Usings)
        {
            if (directive.Location is not { } location) { continue; }

            // A .using from a macro applies from the line that invokes it.
            AssemblyLocation at = location;
            while (at.IsMacroExpansion && at.ExpandedFrom is { } from) { at = from; }
            if (at.Path.Length == 0 || !string.Equals(Path.GetFullPath(at.Path), full, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (ReferenceEquals(at, location))
            {
                lines.Add(at.Line);
                continue;
            }

            if (!invoked.TryGetValue(at.Line, out List<string[]>? names)) { invoked[at.Line] = names = []; }
            names.Add([.. directive.Names]);
        }

        return new(lines.Contains, line => invoked.TryGetValue(line, out List<string[]>? names) ? names : []);
    }
}
