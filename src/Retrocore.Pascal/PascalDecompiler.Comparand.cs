// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a comparison compares: words, or with EQU and the others, reals, strings, booleans, sets, or arrays.
    /// </summary>
    private enum Comparand
    {
        /// <summary>
        ///  One-word values, compared by EQUI and the others.
        /// </summary>
        Word,

        /// <summary>
        ///  Reals.
        /// </summary>
        Real,

        /// <summary>
        ///  Strings.
        /// </summary>
        String,

        /// <summary>
        ///  Booleans.
        /// </summary>
        Boolean,

        /// <summary>
        ///  Sets.
        /// </summary>
        Set,

        /// <summary>
        ///  Packed arrays of characters, compared byte by byte.
        /// </summary>
        Bytes,

        /// <summary>
        ///  Arrays or records, compared word by word.
        /// </summary>
        Words
    }
}
