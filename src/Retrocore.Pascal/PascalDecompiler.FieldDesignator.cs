// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A record's field, at a word offset.
    /// </summary>
    /// <param name="record">The record.</param>
    /// <param name="offset">The field's word offset in the record.</param>
    private sealed class FieldDesignator(Designator record, int offset) : Designator
    {
        /// <summary>
        ///  Gets the record.
        /// </summary>
        public Designator Record { get; } = record;

        /// <summary>
        ///  Gets the field's word offset in the record.
        /// </summary>
        public int Offset { get; } = offset;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = record.Type.Field(offset);
    }
}
