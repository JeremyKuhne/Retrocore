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
    }
}
