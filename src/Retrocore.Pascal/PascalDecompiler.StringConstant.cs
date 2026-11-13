// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A string constant's address, from LSA.
    /// </summary>
    /// <param name="characters">The string's characters.</param>
    private sealed class StringConstant(byte[] characters) : Expr
    {
        /// <summary>
        ///  Gets the string's characters.
        /// </summary>
        public byte[] Characters { get; } = characters;
    }
}
