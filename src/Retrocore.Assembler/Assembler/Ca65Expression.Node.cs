// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal ref partial struct Ca65Expression
{
    /// <summary>
    ///  A translated subexpression: where its text starts in the output, and whether it needs no grouping.
    /// </summary>
    /// <param name="Start">The output offset of the node's first character.</param>
    /// <param name="Atomic">Whether the node is a single token or call that operators cannot split.</param>
    private readonly record struct Node(int Start, bool Atomic);
}
