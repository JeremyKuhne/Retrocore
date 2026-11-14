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
    /// <param name="site">
    ///  Whether it is a use the code makes, with a type of its own that inference puts in the record at the offset: in
    ///  its field, or, where the two cannot be one, as a variant's.
    /// </param>
    private sealed class FieldDesignator(Designator record, int offset, bool site = false) : Designator
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
        public override TypeNode Type { get; } = site ? Site(record.Type, offset) : record.Type.Field(offset);

        // Makes the record one with a field at the offset, and gives a type of the use's own.
        private static TypeNode Site(TypeNode record, int offset)
        {
            record.Field(offset);
            return new TypeNode();
        }
    }
}
