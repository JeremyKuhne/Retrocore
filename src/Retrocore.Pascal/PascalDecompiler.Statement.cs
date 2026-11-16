// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A statement, at its first p-code's offset.
    /// </summary>
    private abstract class Statement
    {
        /// <summary>
        ///  Gets or sets the offset of its first p-code.
        /// </summary>
        public int Offset { get; set; }

        /// <summary>
        ///  Gets or sets the offset of the first p-code of the code it was decompiled from, or null where unknown.
        /// </summary>
        public int? Start { get; set; }

        /// <summary>
        ///  Gets or sets the offset of the last p-code of the code it was decompiled from, or null where unknown.
        /// </summary>
        public int? End { get; set; }
    }
}
