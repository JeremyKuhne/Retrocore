// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Optional ca65-only expansion state; native preprocessing does not allocate its tables.
    /// </summary>
    private sealed class Ca65State
    {
        private byte[]? _characters;

        /// <summary>
        ///  Gets inline textual definitions.
        /// </summary>
        internal Dictionary<string, TextDefinition> Defines { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets or sets one bit per defined name length (63 for longer names), so lines that cannot mention a
        ///  definition skip expansion without allocating.
        /// </summary>
        internal ulong DefineLengths { get; set; }

        /// <summary>
        ///  Gets known type and field sizes by canonical name.
        /// </summary>
        internal Dictionary<string, long> Sizes { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets open structure, union and enumeration frames.
        /// </summary>
        internal List<TypeFrame> Types { get; } = [];

        /// <summary>
        ///  Gets the source-to-output character map.
        /// </summary>
        internal byte[] Characters => _characters ??= [.. Enumerable.Range(0, 256).Select(value => (byte)value)];

        /// <summary>
        ///  Gets or sets whether source character mappings have changed.
        /// </summary>
        internal bool CharactersChanged { get; set; }

        /// <summary>
        ///  Gets or sets ca65's active instruction-set mask.
        /// </summary>
        internal int Cpu { get; set; } = 2;

        /// <summary>
        ///  Gets or sets the lazily cached source-order numeric resolver.
        /// </summary>
        internal Func<string, long?>? NumberLookup { get; set; }
    }
}
