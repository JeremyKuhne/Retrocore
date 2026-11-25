// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A run of consecutive source lines.
/// </summary>
/// <param name="Start">The zero-based first line.</param>
/// <param name="Count">The number of lines, at least one.</param>
public readonly record struct AssemblyLineRange(int Start, int Count)
{
    /// <summary>
    ///  Gets the zero-based line just past the run.
    /// </summary>
    public int End => Start + Count;

    /// <summary>
    ///  Gets whether the run holds a line.
    /// </summary>
    /// <param name="line">The zero-based line.</param>
    /// <returns>Whether it is in the run.</returns>
    public bool Contains(int line) => line >= Start && line < End;
}
