// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A run of addresses in a <see cref="MemoryMap"/>, from <paramref name="Start"/> to <paramref name="End"/>
///  inclusive.
/// </summary>
/// <param name="Start">The first address.</param>
/// <param name="End">The last address.</param>
/// <param name="Why">What the machine keeps there, for a reserved area; null for free RAM.</param>
internal sealed record MemoryArea(int Start, int End, string? Why = null)
{
    /// <summary>
    ///  Gets the number of bytes.
    /// </summary>
    internal int Length => End - Start + 1;

    /// <summary>
    ///  Tests whether the area shares an address with a run.
    /// </summary>
    /// <param name="start">The run's first address.</param>
    /// <param name="end">The run's last address.</param>
    /// <returns>Whether they overlap.</returns>
    internal bool Overlaps(int start, int end) => start <= End && end >= Start;

    /// <summary>
    ///  Tests whether the area holds an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether it does.</returns>
    internal bool Contains(int address) => address >= Start && address <= End;

    /// <summary>
    ///  Gets the area as the map and its errors write it, <c>$0800-$BFFF</c>.
    /// </summary>
    /// <returns>The text.</returns>
    public override string ToString() => Start == End ? $"${Start:X4}" : $"${Start:X4}-${End:X4}";
}
