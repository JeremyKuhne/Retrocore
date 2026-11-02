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
    private readonly List<(string Scope, AssemblyStatementKind Kind)> _constantScopes = [];
    private readonly HashSet<string> _constantNamespaces = new(StringComparer.Ordinal);

    /// <summary>
    ///  Mirrors the resolver's scope and cheap-local rules so conditionals see the names emission will use.
    /// </summary>
    /// <param name="node">The emitted statement.</param>
    /// <returns>Whether the statement was a scope directive.</returns>
    private bool TrackScope(AssemblyStatement node)
    {
        if (_constantDialect is { } dialect && dialect != node.Dialect) { _constantCheap = FreshCheapContext(); }
        _constantDialect = node.Dialect;
        if (node.Kind is AssemblyStatementKind.Procedure or AssemblyStatementKind.Scope)
        {
            string name = node.Operand.Text.Trim();
            bool invalidName = name.Length == 0
                ? node.Kind == AssemblyStatementKind.Procedure : !AssemblySyntax.IsPlainIdentifier(name);

            // An invalid opening still pairs with its terminator, so the enclosing scope is kept.
            if (node.Label is not null || invalidName)
            {
                _constantScopes.Add((_constantScope, node.Kind));
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
                _constants.Unset(qualified);
            }

            _constantScopes.Add((_constantScope, node.Kind));
            _constantScope = qualified;
            _constantNamespaces.Add(qualified);
            return true;
        }

        if (node.Kind is not (AssemblyStatementKind.EndScope or AssemblyStatementKind.EndProcedure)) { return false; }
        if (_constantScopes.Count != 0)
        {
            (string parent, AssemblyStatementKind kind) = _constantScopes[^1];
            if ((node.Kind == AssemblyStatementKind.EndProcedure) == (kind == AssemblyStatementKind.Procedure))
            {
                _constantScope = parent;
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

        return name;
    }

    private string ConstantExpression(string text)
    {
        if (_constantScope.Length == 0 && text.IndexOfAny('@', ':') < 0) { return text; }
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
