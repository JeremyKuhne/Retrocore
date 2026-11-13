// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  Leaves the range checks or I/O checks on or off from here: (*$R-*) and the like.
    /// </summary>
    /// <param name="option">The compiler option's letter, such as R or I.</param>
    /// <param name="on">Whether the option is on.</param>
    private sealed class OptionStatement(char option, bool on) : Statement
    {
        /// <summary>
        ///  Gets the compiler option's letter, such as R or I.
        /// </summary>
        public char Option { get; } = option;

        /// <summary>
        ///  Gets a value indicating whether the option is on.
        /// </summary>
        public bool On { get; } = on;
    }
}
