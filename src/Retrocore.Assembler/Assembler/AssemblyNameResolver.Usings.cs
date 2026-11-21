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
        if (node.Dialect != AssemblyDialect.Native)
        {
            _errors.Add(new(index, ".using is only in the native dialect."));
            return null;
        }

        if (node.Label is not null)
        {
            _errors.Add(new(index, "A .using line cannot carry a label."));
            return null;
        }

        if (node.Operand.Memory.Span.Trim().IsEmpty)
        {
            _errors.Add(new(index, ".using requires one or more scope names."));
            return null;
        }

        List<string> names = [];
        try
        {
            foreach (ReadOnlyMemory<char> operand in new AssemblyOperands(node.Operand.Memory, index))
            {
                string name = operand.ToString();
                if (name.StartsWith("::", StringComparison.Ordinal)) { name = name[2..]; }
                foreach (string part in name.Split("::"))
                {
                    if (!AssemblySyntax.IsPlainIdentifier(part.AsSpan()))
                    {
                        _errors.Add(new(index, $".using requires scope names; '{operand}' is not one."));
                        return null;
                    }
                }

                names.Add(operand.ToString());
            }
        }
        catch (AssemblyError error)
        {
            _errors.Add(error);
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
        List<AssemblyDiagnostic>? notes = null;
        foreach (Using directive in _usings)
        {
            for (int at = 0; at < directive.Names.Length; at++)
            {
                if (directive.Targets[at] is null || directive.Used[at]) { continue; }
                (notes ??= []).Add(new(
                    $"Nothing uses a name from {directive.Names[at]} through this .using; it is unnecessary.",
                    _source.Statements[directive.Index].Location,
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
    ///  Identifies the file a statement is in by the chain of <c>.include</c> lines that brought it in, looking
    ///  through macro expansions to where they were invoked; a top-level file's statements give "".
    /// </summary>
    /// <param name="location">The statement's location.</param>
    /// <returns>The include chain.</returns>
    private static string FileKey(AssemblyLocation? location)
    {
        if (location?.ExpandedFrom is null) { return ""; }
        System.Text.StringBuilder? key = null;
        for (AssemblyLocation current = location; current.ExpandedFrom is { } from; current = from)
        {
            if (current.IsMacroExpansion) { continue; }
            key ??= new();
            key.Insert(0, $"{from.Path}:{from.Line}|");
        }

        return key?.ToString() ?? "";
    }
}
