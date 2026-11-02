// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyNameResolver
{
    /// <summary>
    ///  A lexical namespace and its definition inventory.
    /// </summary>
    /// <param name="parent">The enclosing namespace.</param>
    /// <param name="name">The unqualified namespace name.</param>
    /// <param name="opening">The opening statement index.</param>
    /// <param name="procedure">Whether this scope is a .proc.</param>
    private sealed class Scope(Scope? parent, string name, int opening, bool procedure)
    {
        /// <summary>
        ///  Gets the enclosing lexical scope.
        /// </summary>
        internal Scope? Parent { get; } = parent;

        /// <summary>
        ///  Gets the fully qualified namespace prefix.
        /// </summary>
        internal string Prefix { get; } = parent is null || parent.Prefix.Length == 0
            ? name : $"{parent.Prefix}::{name}";

        /// <summary>
        ///  Gets the opening statement index.
        /// </summary>
        internal int Opening { get; } = opening;

        /// <summary>
        ///  Gets whether .proc opened this scope.
        /// </summary>
        internal bool Procedure { get; } = procedure;

        /// <summary>
        ///  Gets or sets whether an end-minus-entry size can represent this procedure's emitted span.
        /// </summary>
        internal bool Contiguous { get; set; } = true;

        /// <summary>
        ///  Gets names declared anywhere in this scope.
        /// </summary>
        internal HashSet<string> Definitions { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets directly nested namespaces.
        /// </summary>
        internal Dictionary<string, Scope> Children { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Qualifies a name in this namespace.
        /// </summary>
        /// <param name="value">The relative name.</param>
        /// <returns>The compiler symbol name.</returns>
        internal string Qualify(string value) => Prefix.Length == 0 ? value : $"{Prefix}::{value}";
    }
}
