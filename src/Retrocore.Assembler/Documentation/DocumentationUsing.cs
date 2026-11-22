// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A <c>.using</c> directive in effect: the scope it is in and the scopes it names, whose names code and links in
///  its extent can use unqualified.
/// </summary>
/// <param name="Scope">The qualified scope the directive is in, or "" at file level.</param>
/// <param name="Names">The scope names as written: plain, qualified or absolute.</param>
/// <param name="Line">The directive's zero-based line in its file, or -1 when not known.</param>
public sealed record DocumentationUsing(string Scope, IReadOnlyList<string> Names, int Line = -1)
{
    /// <summary>
    ///  Finds the qualified scopes the directive names, by the rules for a qualified name's first part: the
    ///  innermost scope around the directive that has a scope of that name.
    /// </summary>
    /// <param name="isScope">Whether a qualified name is a scope.</param>
    /// <returns>The scopes found, in the directive's order; a name that names none is left out.</returns>
    public IEnumerable<string> Targets(Func<string, bool> isScope) => Targets(isScope, openedBefore: null);

    /// <summary>
    ///  Finds the qualified scopes the directive names as the assembler does: the innermost scope around the
    ///  directive that has a scope of that name already opened before it, or else one opened later.
    /// </summary>
    /// <param name="isScope">Whether a qualified name is a scope.</param>
    /// <param name="openedBefore">Whether a scope opens before the directive, or null when not known.</param>
    /// <returns>The scopes found, in the directive's order; a name that names none is left out.</returns>
    public IEnumerable<string> Targets(Func<string, bool> isScope, Func<string, bool>? openedBefore)
    {
        foreach (string name in Names)
        {
            if (name.StartsWith("::", StringComparison.Ordinal))
            {
                if (isScope(name[2..])) { yield return name[2..]; }
                continue;
            }

            int separator = name.IndexOf("::", StringComparison.Ordinal);
            string first = separator < 0 ? name : name[..separator];
            string? prefix = openedBefore is null ? null : Enclosing(first, candidate => isScope(candidate) && openedBefore(candidate));
            prefix ??= Enclosing(first, isScope);
            if (prefix is null) { continue; }
            string target = Qualify(prefix, name);
            if (separator < 0 || isScope(target)) { yield return target; }
        }
    }

    // The innermost scope around the directive, the root last, in which a scope of the name passes the test.
    private string? Enclosing(string first, Func<string, bool> test)
    {
        string prefix = Scope;
        while (true)
        {
            if (test(Qualify(prefix, first))) { return prefix; }
            if (prefix.Length == 0) { return null; }
            int previous = prefix.LastIndexOf("::", StringComparison.Ordinal);
            prefix = previous < 0 ? "" : prefix[..previous];
        }
    }

    private static string Qualify(string prefix, string name) => prefix.Length == 0 ? name : $"{prefix}::{name}";
}
