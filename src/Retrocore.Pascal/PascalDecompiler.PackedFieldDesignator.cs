// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A packed record's field: some bits of a word.
    /// </summary>
    /// <param name="record">The record.</param>
    /// <param name="word">The word offset in the record of the word that holds the field.</param>
    /// <param name="bit">The field's first bit.</param>
    /// <param name="width">The field's width in bits.</param>
    private sealed class PackedFieldDesignator(Designator record, int word, int bit, int width) : Designator
    {
        /// <summary>
        ///  Gets the record.
        /// </summary>
        public Designator Record { get; } = record;

        /// <summary>
        ///  Gets the word offset in the record of the word that holds the field.
        /// </summary>
        public int Word { get; } = word;

        /// <summary>
        ///  Gets the field's first bit.
        /// </summary>
        public int Bit { get; } = bit;

        /// <summary>
        ///  Gets the field's width in bits.
        /// </summary>
        public int Width { get; } = width;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = record.Type.PackedField(word, bit, width);
    }
}
