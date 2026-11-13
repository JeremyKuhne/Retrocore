// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a type is, as far as the code shows.
    /// </summary>
    private enum TypeKind
    {
        /// <summary>
        ///  Not yet known.
        /// </summary>
        Unknown,

        /// <summary>
        ///  A one-word scalar: an integer, a character, a boolean, or an enumerated value.
        /// </summary>
        Scalar,

        /// <summary>
        ///  A real, two words.
        /// </summary>
        Real,

        /// <summary>
        ///  A pointer.
        /// </summary>
        Pointer,

        /// <summary>
        ///  A record.
        /// </summary>
        Record,

        /// <summary>
        ///  An array.
        /// </summary>
        Array,

        /// <summary>
        ///  A string.
        /// </summary>
        String,

        /// <summary>
        ///  A set.
        /// </summary>
        Set,

        /// <summary>
        ///  A file, typed or untyped.
        /// </summary>
        File,

        /// <summary>
        ///  A text file.
        /// </summary>
        Text
    }
}
