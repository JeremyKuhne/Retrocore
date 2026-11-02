// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyNameResolver
{
    /// <summary>
    ///  Definition-site context frozen before resolving any references.
    /// </summary>
    /// <param name="scope">The enclosing lexical namespace.</param>
    /// <param name="cheapPrefix">The cheap-local context in effect.</param>
    /// <param name="anonymous">The unnamed-label group visible here.</param>
    private readonly struct Site(Scope scope, string cheapPrefix, List<(int Index, string Name)> anonymous)
    {
        /// <summary>
        ///  Gets the lexical scope.
        /// </summary>
        internal Scope Scope { get; } = scope;

        /// <summary>
        ///  Gets the cheap-local anchor.
        /// </summary>
        internal string CheapPrefix { get; } = cheapPrefix;

        /// <summary>
        ///  Gets unnamed-label definitions visible at this site.
        /// </summary>
        internal List<(int Index, string Name)> Anonymous { get; } = anonymous;
    }
}
