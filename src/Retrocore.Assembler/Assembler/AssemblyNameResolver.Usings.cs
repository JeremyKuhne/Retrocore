// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyNameResolver
{
    /// <summary>
    ///  Reads a <c>.using</c> line's scope names, reporting a line that cannot be one.
    /// </summary>
    /// <param name="node">The directive.</param>
    /// <param name="index">Its statement index.</param>
    /// <returns>The names as written, or null for a line in error.</returns>
    private string[]? UsingNames(AssemblyStatement node, int index)
    {
        string[]? names = ReadUsingNames(node, out string? error);
        if (error is not null) { _errors.Add(new(index, error)); }
        return names;
    }

    /// <summary>
    ///  Reads a <c>.using</c> line's scope names as the resolver accepts them, so the preprocessor and the editor
    ///  follow the same lines it does.
    /// </summary>
    /// <param name="node">The directive.</param>
    /// <param name="error">Why the line is not a <c>.using</c> the resolver accepts, or null.</param>
    /// <returns>The names as written, or null for a line in error.</returns>
    internal static string[]? ReadUsingNames(AssemblyStatement node, out string? error)
    {
        error = null;
        if (node.Dialect != AssemblyDialect.Native) { error = ".using is only in the native dialect."; }
        else if (node.Label is not null) { error = "A .using line cannot carry a label."; }
        else if (node.Operand.Memory.Span.Trim().IsEmpty) { error = ".using requires one or more scope names."; }
        if (error is not null) { return null; }
        List<string> names = [];
        try
        {
            foreach (ReadOnlyMemory<char> operand in new AssemblyOperands(node.Operand.Memory, 0))
            {
                string name = operand.ToString();
                if (name.StartsWith("::", StringComparison.Ordinal)) { name = name[2..]; }
                if (name.Split("::").Any(part => !AssemblySyntax.IsPlainIdentifier(part.AsSpan())))
                {
                    error = $".using requires scope names; '{operand}' is not one.";
                    return null;
                }

                names.Add(operand.ToString());
            }
        }
        catch (AssemblyError failure)
        {
            error = failure.Message;
            return null;
        }

        return [.. names];
    }

    /// <summary>
    ///  Finds the scope a <c>.using</c> operand names, by the rules for a qualified name's first part.
    /// </summary>
    /// <param name="name">The operand: plain, qualified, or absolute.</param>
    /// <param name="from">The scope the directive is in.</param>
    /// <param name="index">The directive's statement index.</param>
    /// <returns>The scope, or null when there is none.</returns>
    private Scope? FindScope(string name, Scope from, int index)
    {
        bool absolute = name.StartsWith("::", StringComparison.Ordinal);
        string[] parts = (absolute ? name[2..] : name).Split("::");
        Scope? found = null;
        if (absolute)
        {
            _root.Children.TryGetValue(parts[0], out found);
        }
        else
        {
            // As for a qualified name, a scope already opened here binds first; only without one does a later one.
            for (Scope? scope = from; scope is not null && found is null; scope = scope.Parent)
            {
                if (scope.Children.TryGetValue(parts[0], out Scope? child) && child.Opening < index) { found = child; }
            }

            for (Scope? scope = from; scope is not null && found is null; scope = scope.Parent)
            {
                scope.Children.TryGetValue(parts[0], out found);
            }
        }

        for (int part = 1; part < parts.Length && found is not null; part++)
        {
            found = found.Children.TryGetValue(parts[part], out Scope? child) ? child : null;
        }

        return found;
    }

    /// <summary>
    ///  Resolves the scopes every <c>.using</c> names, now that every scope is known.
    /// </summary>
    /// <param name="usings">The directives in source order.</param>
    private void ResolveUsings(List<Using> usings)
    {
        _usings = usings;
        foreach (Using directive in usings)
        {
            // A conditional that tested a name through the directive used it, though the resolver never sees it.
            HashSet<int>? conditional = null;
            _source.UsedUsings?.TryGetValue(_source.Statements[directive.Index], out conditional);
            for (int at = 0; at < directive.Names.Length; at++)
            {
                if (conditional?.Contains(at) == true) { directive.Used[at] = true; }

                directive.Targets[at] = FindScope(directive.Names[at], directive.Scope, directive.Index);
                if (directive.Targets[at] is null)
                {
                    _errors.Add(new(directive.Index, $"No scope named '{directive.Names[at]}' for .using."));
                }
            }
        }
    }

    /// <summary>
    ///  Reports each scope a <c>.using</c> names that gave the code no name, as information rather than an error.
    /// </summary>
    /// <returns>The notes, or null when there are none.</returns>
    private List<AssemblyDiagnostic>? UnusedUsings()
    {
        // Each expansion of a macro or .repeat that holds a .using is its own directive; the source line is used if
        // any of them gave the code a name.
        HashSet<(string? Path, int Line, int Column, int At)> used = [];
        foreach (Using directive in _usings)
        {
            AssemblyLocation? location = _source.Statements[directive.Index].Location;
            for (int at = 0; at < directive.Names.Length; at++)
            {
                if (directive.Used[at])
                {
                    used.Add((location?.Path, location?.Line ?? directive.Index, location?.Column ?? 0, at));
                }
            }
        }

        List<AssemblyDiagnostic>? notes = null;
        HashSet<(string? Path, int Line, int Column, int At)> reported = [];
        foreach (Using directive in _usings)
        {
            AssemblyLocation? location = _source.Statements[directive.Index].Location;
            for (int at = 0; at < directive.Names.Length; at++)
            {
                (string? Path, int Line, int Column, int At) source = (location?.Path, location?.Line ?? directive.Index, location?.Column ?? 0, at);
                if (directive.Targets[at] is null || used.Contains(source) || !reported.Add(source)) { continue; }
                (notes ??= []).Add(new(
                    $"Nothing uses a name from {directive.Names[at]} through this .using; it is unnecessary.",
                    location,
                    directive.Index));
            }
        }

        return notes;
    }

    /// <summary>
    ///  Finds a plain name in the scopes the <c>.using</c> directives in effect name, innermost directive first.
    /// </summary>
    /// <param name="name">The plain name.</param>
    /// <param name="site">Where it is used.</param>
    /// <param name="index">The statement index.</param>
    /// <returns>The qualified name, or null when no used scope defines it.</returns>
    private string? FindUsed(string name, Site site, int index)
    {
        for (Using? directive = site.Usings; directive is not null; directive = directive.Next)
        {
            Scope? found = null;
            string? foundName = null;
            for (int at = 0; at < directive.Targets.Length; at++)
            {
                if (directive.Targets[at] is not { } target || !target.Definitions.Contains(name)) { continue; }
                directive.Used[at] = true;
                if (found is null)
                {
                    found = target;
                    foundName = directive.Names[at];
                }
                else if (!ReferenceEquals(found, target))
                {
                    _errors.Add(new(index, $"'{name}' is in both {foundName} and {directive.Names[at]}; qualify it."));
                    break;
                }
            }

            if (found is not null) { return found.Qualify(name); }
        }

        return null;
    }

    /// <summary>
    ///  Identifies the file a statement is in: the top-level source it came from, then each <c>.include</c> that
    ///  brought it in, with the macro invocations that led to that include and the file it included.
    /// </summary>
    /// <param name="location">The statement's location.</param>
    /// <returns>The key, which starts with the key of every file that includes this one.</returns>
    private static string FileKey(AssemblyLocation location)
    {
        // The links from the statement outward: each a macro expansion's invocation or an include's line.
        List<(bool Macro, AssemblyLocation From, AssemblyLocation Inner)> links = [];
        AssemblyLocation current = location;
        for (; current.ExpandedFrom is { } from; current = from)
        {
            links.Add((current.IsMacroExpansion, from, current));
        }

        // The outermost location is in a top-level source, so separate sources are separate files. Two includes
        // from one macro body line differ by the invocations before them and by the files they include; the
        // invocations after the last include are inside the file, so they do not change it.
        List<string> parts = [current.Path, "|"];
        int kept = parts.Count;
        for (int at = links.Count - 1; at >= 0; at--)
        {
            (bool macro, AssemblyLocation from, AssemblyLocation inner) = links[at];
            parts.Add($"{from.Path}:{from.Line}");
            if (macro)
            {
                parts.Add(",");
                continue;
            }

            parts.Add($">{inner.Path}|");
            kept = parts.Count;
        }

        return string.Concat(parts.Take(kept));
    }
}
