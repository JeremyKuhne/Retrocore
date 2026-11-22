// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    // Names the preprocessor invents for conditional evaluation; the resolver chooses its own collision-free names.
    private const string PrivatePrefix = "__retro_scope_";

    private string _constantScope = "";
    private string _constantCheap = "";
    private int _constantContexts;
    private AssemblyDialect? _constantDialect;
    private readonly List<(string Scope, AssemblyStatementKind Kind, UsingDirective? Usings)> _constantScopes = [];
    private UsingDirective? _constantUsings;
    private readonly HashSet<string> _constantNamespaces = [with(StringComparer.Ordinal)];

    /// <summary>
    ///  Mirrors the resolver's scope and cheap-local rules so conditionals see the names emission will use.
    /// </summary>
    /// <param name="node">The emitted statement.</param>
    /// <returns>Whether the statement was a scope directive.</returns>
    private bool TrackScope(AssemblyStatement node)
    {
        if (_constantDialect is { } dialect && dialect != node.Dialect) { _constantCheap = FreshCheapContext(); }
        _constantDialect = node.Dialect;
        if (node.Kind == AssemblyStatementKind.Using)
        {
            // The resolver reports a malformed directive; one it accepts applies from the next line.
            if (AssemblyNameResolver.ReadUsingNames(node, out _) is { } names)
            {
                _constantUsings = new(_constantUsings, _constantScope, names, node);
            }

            return true;
        }

        if (node.Kind is AssemblyStatementKind.Procedure or AssemblyStatementKind.Scope)
        {
            string name = node.Operand.Text.Trim();

            // A continued scope has the same names as where it was first opened.
            if (node.Kind == AssemblyStatementKind.Scope && AssemblySyntax.ContinuedScope(name) is { } continued)
            {
                name = continued;
            }

            bool invalidName = name.Length == 0
                ? node.Kind == AssemblyStatementKind.Procedure : !AssemblySyntax.IsPlainIdentifier(name);

            // An invalid opening still pairs with its terminator, so the enclosing scope is kept.
            if (node.Label is not null || invalidName)
            {
                _constantScopes.Add((_constantScope, node.Kind, _constantUsings));
                return true;
            }

            if (name.Length == 0)
            {
                name = $"{PrivatePrefix}anonymous_{_project.Statements.Count}";
            }

            string qualified = ConstantQualified(_constantScope, name);
            if (node.Kind == AssemblyStatementKind.Procedure)
            {
                if (_defined.Add(qualified)) { _constantCheap = qualified; }
                RecordHistoricalNames(node, qualified);
                _constants.Unset(qualified);
            }

            _constantScopes.Add((_constantScope, node.Kind, _constantUsings));
            _constantScope = qualified;
            _constantNamespaces.Add(qualified);
            return true;
        }

        if (node.Kind is not (AssemblyStatementKind.EndScope or AssemblyStatementKind.EndProcedure)) { return false; }
        if (_constantScopes.Count != 0)
        {
            (string parent, AssemblyStatementKind kind, UsingDirective? usings) = _constantScopes[^1];
            if ((node.Kind == AssemblyStatementKind.EndProcedure) == (kind == AssemblyStatementKind.Procedure))
            {
                _constantScope = parent;
                _constantUsings = usings;
                _constantCheap = FreshCheapContext();
                _constantScopes.RemoveAt(_constantScopes.Count - 1);
            }
        }

        return true;
    }

    private string FreshCheapContext() => $"{PrivatePrefix}cheap_{++_constantContexts}";

    private static string ConstantQualified(string prefix, string name) => prefix.Length == 0 ? name : $"{prefix}::{name}";

    private string ConstantName(string name)
    {
        if (name.StartsWith("::", StringComparison.Ordinal)) { return name[2..]; }
        if (name[0] == '@') { return ConstantQualified(_constantCheap, name); }
        int separator = name.IndexOf("::", StringComparison.Ordinal);
        string first = separator < 0 ? name : name[..separator];
        string prefix = _constantScope;
        while (prefix.Length != 0)
        {
            // Symbols and scopes are separate namespaces; only a scope can qualify a name.
            string candidate = ConstantQualified(prefix, first);
            if (separator < 0 ? _defined.Contains(candidate) : _constantNamespaces.Contains(candidate))
            {
                return ConstantQualified(prefix, name);
            }

            int previous = prefix.LastIndexOf("::", StringComparison.Ordinal);
            prefix = previous < 0 ? "" : prefix[..previous];
        }

        // Then the scopes the .using directives in effect name, then historical names.
        return separator >= 0 || _defined.Contains(name) ? name : UnscopedName(name);
    }

    // A plain name no enclosing scope defines: one a .using in effect gives, or a historical name.
    private string UnscopedName(string name)
    {
        string? used = _constantUsings is null ? null : UsedName(name);
        return used ?? HistoricalTarget(name) ?? name;
    }

    // A plain name defined so far in a scope that a .using in effect names, innermost directive first.
    private string? UsedName(string name)
    {
        for (UsingDirective? directive = _constantUsings; directive is not null; directive = directive.Next)
        {
            string? found = null;
            string? foundScope = null;
            for (int at = 0; at < directive.Names.Length; at++)
            {
                string scopeName = directive.Names[at];
                if (UsedScope(scopeName, directive.Scope) is not { } scope) { continue; }
                string candidate = ConstantQualified(scope, name);
                if (!_defined.Contains(candidate)) { continue; }
                _project.UsedUsings ??= [];
                if (!_project.UsedUsings.TryGetValue(directive.Statement, out HashSet<int>? used))
                {
                    _project.UsedUsings[directive.Statement] = used = [];
                }

                used.Add(at);
                if (found is null)
                {
                    found = candidate;
                    foundScope = scopeName;
                }
                else if (found != candidate)
                {
                    _nameAmbiguity = $"'{name}' is in both {foundScope} and {scopeName}; qualify it.";
                    break;
                }
            }

            if (found is not null) { return found; }
        }

        return null;
    }

    // The qualified name of the scope a .using operand names, among the scopes opened so far.
    private string? UsedScope(string name, string from)
    {
        if (name.StartsWith("::", StringComparison.Ordinal)) { return name[2..]; }
        int separator = name.IndexOf("::", StringComparison.Ordinal);
        string first = separator < 0 ? name : name[..separator];
        string prefix = from;
        while (true)
        {
            if (_constantNamespaces.Contains(ConstantQualified(prefix, first)))
            {
                return ConstantQualified(prefix, name);
            }

            if (prefix.Length == 0) { return null; }
            int previous = prefix.LastIndexOf("::", StringComparison.Ordinal);
            prefix = previous < 0 ? "" : prefix[..previous];
        }
    }

    private string ConstantExpression(string text)
    {
        bool plain = _constantScope.Length == 0 && _constantUsings is null && _historicalNames is null;
        if (plain && text.IndexOfAny('@', ':') < 0) { return text; }
        StringBuilder? result = null;
        int copied = 0;
        AssemblyNameReferences references = new(text.AsMemory());
        while (references.MoveNext())
        {
            if (references.Current.Span[0] is '.' or ':'
                && !references.Current.Span.StartsWith("::", StringComparison.Ordinal))
            {
                continue;
            }

            string name = references.Current.ToString();
            string resolved = ConstantName(name);
            if (resolved == name) { continue; }
            result ??= new(text.Length);
            result.Append(text, copied, references.Start - copied).Append(resolved);
            copied = references.Start + name.Length;
        }

        return result is null ? text : result.Append(text, copied, text.Length - copied).ToString();
    }
}
