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
public sealed record DocumentationUsing(string Scope, IReadOnlyList<string> Names)
{
    /// <summary>
    ///  Finds the qualified scopes the directive names, by the rules for a qualified name's first part: the
    ///  innermost scope around the directive that has a scope of that name.
    /// </summary>
    /// <param name="isScope">Whether a qualified name is a scope.</param>
    /// <returns>The scopes found, in the directive's order; a name that names none is left out.</returns>
    public IEnumerable<string> Targets(Func<string, bool> isScope)
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
            string prefix = Scope;
            while (true)
            {
                string candidate = Qualify(prefix, first);
                if (isScope(candidate))
                {
                    string target = Qualify(prefix, name);
                    if (target == candidate || isScope(target)) { yield return target; }
                    break;
                }

                if (prefix.Length == 0) { break; }
                int previous = prefix.LastIndexOf("::", StringComparison.Ordinal);
                prefix = previous < 0 ? "" : prefix[..previous];
            }
        }
    }

    private static string Qualify(string prefix, string name) => prefix.Length == 0 ? name : $"{prefix}::{name}";
}
