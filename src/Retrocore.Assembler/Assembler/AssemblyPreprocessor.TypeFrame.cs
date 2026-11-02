// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  One non-emitting ca65 type layout.
    /// </summary>
    /// <param name="kind">STRUCT, UNION or ENUM.</param>
    /// <param name="name">The optional local name.</param>
    /// <param name="qualified">The canonical type name.</param>
    /// <param name="start">The first field offset.</param>
    /// <param name="opening">The physical opening line.</param>
    private sealed class TypeFrame(string kind, string name, string qualified, long start, AssemblyLocation opening)
    {
        /// <summary>
        ///  Gets the block kind.
        /// </summary>
        internal string Kind { get; } = kind;

        /// <summary>
        ///  Gets the optional local name.
        /// </summary>
        internal string Name { get; } = name;

        /// <summary>
        ///  Gets the canonical name.
        /// </summary>
        internal string Qualified { get; } = qualified;

        /// <summary>
        ///  Gets the initial offset.
        /// </summary>
        internal long Start { get; } = start;

        /// <summary>
        ///  Gets or sets the next field offset or enum value.
        /// </summary>
        internal long Position { get; set; } = start;

        /// <summary>
        ///  Gets or sets the accumulated storage size, independent of .org field offsets.
        /// </summary>
        internal long End { get; set; }

        /// <summary>
        ///  Gets or sets the optional containing member's canonical name.
        /// </summary>
        internal string? Member { get; set; }

        /// <summary>
        ///  Gets the opening location.
        /// </summary>
        internal AssemblyLocation Opening { get; } = opening;
    }
}
