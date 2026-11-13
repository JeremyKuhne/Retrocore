// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A packed array constant's address, from LPA.
    /// </summary>
    /// <param name="bytes">The array's bytes.</param>
    private sealed class PackedConstant(byte[] bytes) : Expr
    {
        /// <summary>
        ///  Gets the array's bytes.
        /// </summary>
        public byte[] Bytes { get; } = bytes;
    }
}
