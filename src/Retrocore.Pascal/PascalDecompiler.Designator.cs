// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  Something with an address: a variable, or a part of one.
    /// </summary>
    private abstract class Designator
    {
        /// <summary>
        ///  Gets its inferred type.
        /// </summary>
        public abstract TypeNode Type { get; }
    }
}
