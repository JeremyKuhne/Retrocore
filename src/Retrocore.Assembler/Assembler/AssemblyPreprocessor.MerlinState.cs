// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Optional Merlin-only lexical state.
    /// </summary>
    private sealed class MerlinState
    {
        /// <summary>
        ///  Gets macro files already loaded by USE, which Merlin 32 loads once however often they are named.
        /// </summary>
        internal HashSet<string> Used { get; } = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        ///  Gets the collision-checked source-name mapping.
        /// </summary>
        internal MerlinNames Names { get; } = new();

        /// <summary>
        ///  Gets original EQU text for hexadecimal trailers in string directives.
        /// </summary>
        internal Dictionary<string, string> Equates => Names.Equates;

        /// <summary>
        ///  Gets or sets whether XC has already selected the 65C02 mode.
        /// </summary>
        internal bool Extended { get; set; }

        /// <summary>
        ///  Gets or sets the in-memory output filename.
        /// </summary>
        internal string? Output { get; set; }
    }
}
