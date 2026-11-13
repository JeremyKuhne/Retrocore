// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a pointer points to; for a VAR parameter, what it stands for.
    /// </summary>
    /// <param name="pointer">The pointer.</param>
    private sealed class Dereference(Expr pointer) : Designator
    {
        /// <summary>
        ///  Gets the pointer.
        /// </summary>
        public Expr Pointer { get; } = pointer;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = pointer.Type.Target();
    }
}
