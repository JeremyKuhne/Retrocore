// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  A <c>.using</c> the preprocessor has seen, linked to the ones in effect outside it.
    /// </summary>
    /// <param name="next">The directive in effect before this one, or null.</param>
    /// <param name="scope">The qualified scope the directive is in.</param>
    /// <param name="names">The scope names as written.</param>
    /// <param name="statement">The directive's statement.</param>
    private sealed class UsingDirective(UsingDirective? next, string scope, string[] names, AssemblyStatement statement)
    {
        /// <summary>
        ///  Gets the directive in effect before this one, which is searched after it.
        /// </summary>
        internal UsingDirective? Next { get; } = next;

        /// <summary>
        ///  Gets the qualified scope the directive is in, where its names resolve.
        /// </summary>
        internal string Scope { get; } = scope;

        /// <summary>
        ///  Gets the scope names as written.
        /// </summary>
        internal string[] Names { get; } = names;

        /// <summary>
        ///  Gets the directive's statement, by which the resolver learns which operands conditionals used.
        /// </summary>
        internal AssemblyStatement Statement { get; } = statement;

        /// <summary>
        ///  Gets the qualified scope each name bound to at the directive, as the resolver binds it to a scope opened
        ///  before it; null for a name no scope opened so far has, which binds where it is first used.
        /// </summary>
        internal string?[] Bound { get; } = new string?[names.Length];
    }
}
