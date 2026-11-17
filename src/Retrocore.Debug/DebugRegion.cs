// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A named part of a machine's address space, such as the 6502's zero page, a text page or the I/O space, as
///  Retrocore Memory's inspector and map name it.
/// </summary>
/// <param name="Name">The name, such as <c>Text page 1</c>.</param>
/// <param name="Start">The first address.</param>
/// <param name="Length">The bytes it spans.</param>
/// <param name="Kind">What it holds: <c>ram</c>, <c>rom</c>, <c>io</c> or <c>video</c>.</param>
/// <param name="Detail">
///  Where an offset in the region is, such as <c>row 3, column 12</c> on a text screen, or null for none.
/// </param>
internal sealed record DebugRegion(string Name, ushort Start, int Length, string Kind, Func<int, string?>? Detail = null)
{
    /// <summary>
    ///  Gets whether the region holds an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>True when the address is in the region.</returns>
    internal bool Contains(int address) => address >= Start && address < Start + Length;

    /// <summary>
    ///  Gets the narrowest region holding an address, so a text page inside RAM names the text page.
    /// </summary>
    /// <param name="regions">The regions.</param>
    /// <param name="address">The address.</param>
    /// <returns>The region, or null when none holds it.</returns>
    internal static DebugRegion? At(IReadOnlyList<DebugRegion> regions, int address) =>
        regions.Where(region => region.Contains(address)).MinBy(region => region.Length);

    /// <summary>
    ///  Gets where an offset in an Apple II text page is: each 128 bytes hold rows n, n+8 and n+16 of 40 columns,
    ///  and their last 8 bytes are the screen holes the firmware keeps slot data in.
    /// </summary>
    /// <param name="offset">The offset in the 1K page.</param>
    /// <returns>The row and column, or that it is a screen hole.</returns>
    internal static string AppleText(int offset)
    {
        int within = offset & 0x7F;
        if (within >= 120) { return "screen hole"; }
        return $"row {(within / 40 * 8) + (offset >> 7)}, column {within % 40}";
    }

    /// <summary>
    ///  Gets where an offset in an Apple II hi-res page is: line y's bytes are at (y &amp; 7) * $400 +
    ///  ((y / 8) &amp; 7) * $80 + (y / 64) * 40, 40 bytes of 7 dots each, with 8 bytes of screen holes per $80.
    /// </summary>
    /// <param name="offset">The offset in the 8K page.</param>
    /// <returns>The line and byte, or that it is a screen hole.</returns>
    internal static string AppleHires(int offset)
    {
        int within = offset & 0x7F;
        if (within >= 120) { return "screen hole"; }
        int line = (within / 40 * 64) + (((offset >> 7) & 7) * 8) + ((offset >> 10) & 7);
        return $"line {line}, byte {within % 40} (dots {within % 40 * 7}-{(within % 40 * 7) + 6})";
    }

    /// <summary>
    ///  Gets where an offset in a screen laid out a row after another is.
    /// </summary>
    /// <param name="columns">The columns in a row.</param>
    /// <returns>The offset's row and column.</returns>
    internal static Func<int, string?> Rows(int columns) => offset => $"row {offset / columns}, column {offset % columns}";
}
