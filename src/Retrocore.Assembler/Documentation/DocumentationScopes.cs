// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Where a line is in a source's scopes: the scope that contains it and the <c>.using</c> directives in effect.
/// </summary>
/// <param name="Scope">The qualified scope, or "" at file level.</param>
/// <param name="Usings">The <c>.using</c> directives in effect, innermost first.</param>
public sealed record DocumentationScopes(string Scope, IReadOnlyList<DocumentationUsing> Usings)
{
    /// <summary>
    ///  Gets the file level of a source with no <c>.using</c>.
    /// </summary>
    public static DocumentationScopes Root { get; } = new("", []);
}
