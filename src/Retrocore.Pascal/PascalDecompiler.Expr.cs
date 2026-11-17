// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A value on the p-machine's stack.
    /// </summary>
    private abstract class Expr
    {
        /// <summary>
        ///  Gets the words it takes on the stack.
        /// </summary>
        public virtual int Words => 1;

        /// <summary>
        ///  Gets its inferred type.
        /// </summary>
        public virtual TypeNode Type { get; } = new();
    }
}
