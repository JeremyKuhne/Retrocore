// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyNameResolver
{
    /// <summary>
    ///  A <c>.using</c> directive, linked to the directives in effect outside it.
    /// </summary>
    /// <param name="next">The directive in effect before this one, or null.</param>
    /// <param name="index">The directive's statement index.</param>
    /// <param name="scope">The scope the directive is in.</param>
    /// <param name="names">The scope names as written.</param>
    private sealed class Using(Using? next, int index, Scope scope, string[] names)
    {
        /// <summary>
        ///  Gets the directive in effect before this one, which is searched after it.
        /// </summary>
        internal Using? Next { get; } = next;

        /// <summary>
        ///  Gets the directive's statement index.
        /// </summary>
        internal int Index { get; } = index;

        /// <summary>
        ///  Gets the scope the directive is in, where its names resolve.
        /// </summary>
        internal Scope Scope { get; } = scope;

        /// <summary>
        ///  Gets the scope names as written.
        /// </summary>
        internal string[] Names { get; } = names;

        /// <summary>
        ///  Gets the scopes the names resolve to, once every scope is known; null for a name that names none.
        /// </summary>
        internal Scope?[] Targets { get; } = new Scope?[names.Length];

        /// <summary>
        ///  Gets whether each name's scope gave the code a name, so a <c>.using</c> that gives none can be reported.
        /// </summary>
        internal bool[] Used { get; } = new bool[names.Length];

        /// <summary>
        ///  Gets or sets the statement where the directive's extent ends, or -1 when it lasts to the end.
        /// </summary>
        internal int End { get; set; } = -1;
    }
}
