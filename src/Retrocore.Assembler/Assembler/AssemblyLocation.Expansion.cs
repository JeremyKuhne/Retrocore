// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

public sealed partial class AssemblyLocation
{
    /// <summary>
    ///  Holds source identity and expansion metadata only when a parent exists.
    /// </summary>
    /// <param name="path">The source path.</param>
    /// <param name="from">The enclosing expansion.</param>
    /// <param name="macro">Whether this is a macro body line rather than a line of an included file.</param>
    private sealed class Expansion(string path, AssemblyLocation from, bool macro)
    {
        /// <summary>
        ///  Gets whether this is a macro body line rather than a line of an included file.
        /// </summary>
        internal bool Macro { get; } = macro;

        /// <summary>
        ///  Gets the innermost source path.
        /// </summary>
        internal string Path { get; } = path;

        /// <summary>
        ///  Gets the enclosing expansion location.
        /// </summary>
        internal AssemblyLocation From { get; } = from;
    }
}
