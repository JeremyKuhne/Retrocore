// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  One space's marks in a <see cref="MemoryHints"/> file: memory as the CPU maps it, or a bank.
/// </summary>
internal sealed class MemoryHintSpace
{
    /// <summary>
    ///  Gets where code is marked to start.
    /// </summary>
    public SortedSet<int> Code { get; } = [];

    /// <summary>
    ///  Gets the ranges marked as data: each one's first address and length.
    /// </summary>
    public List<(int Start, int Length)> Data { get; } = [];

    /// <summary>
    ///  Gets the names by address.
    /// </summary>
    public SortedDictionary<int, string> Names { get; } = [];

    /// <summary>
    ///  Gets the comments by address.
    /// </summary>
    public SortedDictionary<int, string> Comments { get; } = [];
}
