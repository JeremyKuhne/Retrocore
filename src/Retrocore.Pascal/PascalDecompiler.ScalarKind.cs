// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a one-word scalar is: an integer, a character, a boolean, or a unit's enumerated type.
    /// </summary>
    private enum ScalarKind
    {
        /// <summary>
        ///  An integer.
        /// </summary>
        Integer,

        /// <summary>
        ///  A character.
        /// </summary>
        Char,

        /// <summary>
        ///  A boolean.
        /// </summary>
        Boolean,

        /// <summary>
        ///  A unit's enumerated type.
        /// </summary>
        Enumeration
    }
}
