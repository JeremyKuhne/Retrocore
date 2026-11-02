// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Storage a memory reference can name directly, whatever the memory map, such as the IIe's auxiliary RAM.
/// </summary>
/// <remarks>
///  <para>
///   A bank's addresses are the CPU addresses its bytes answer at when it is mapped, so <c>aux:$0400</c> is the
///   byte auxiliary RAM holds for text page one.
///  </para>
/// </remarks>
/// <param name="Name">The prefix that names it in memory references and expressions, such as <c>aux</c>.</param>
/// <param name="Label">What it is, such as "Auxiliary RAM".</param>
/// <param name="Areas">
///  The memory area that holds each of <paramref name="Ranges"/>, in order, as <see cref="IDebugMemory.ReadArea"/>
///  reports them.
/// </param>
/// <param name="Ranges">The CPU address ranges it holds bytes for.</param>
/// <param name="Peek">Reads a byte without side effects, or returns null where the bank has none.</param>
/// <param name="Poke">Writes a byte, returning false where the bank has none; null when it is read-only.</param>
internal sealed record DebugMemoryBank(
    string Name,
    string Label,
    IReadOnlyList<Enum> Areas,
    IReadOnlyList<(ushort Start, int Length)> Ranges,
    Func<ushort, byte?> Peek,
    Func<ushort, byte, bool>? Poke)
{
    /// <summary>
    ///  Gets the memory area that holds an address.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The area, or null when the bank has no byte there.</returns>
    internal Enum? AreaOf(ushort address)
    {
        for (int index = 0; index < Ranges.Count; index++)
        {
            if (address >= Ranges[index].Start && address < Ranges[index].Start + Ranges[index].Length)
            {
                return Areas[Math.Min(index, Areas.Count - 1)];
            }
        }

        return null;
    }
}
