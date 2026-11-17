// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Where Retrocore Memory's inspector says an address is on a screen.
/// </summary>
[TestClass]
public sealed class DebugRegionTests
{
    /// <summary>
    ///  Every row and column of an Apple II text page is the one its address is, as the firmware's BASCALC works it
    ///  out, and the 8 bytes after each 120 are screen holes.
    /// </summary>
    [TestMethod]
    public void AppleTextFindsEachRowAndColumn()
    {
        HashSet<int> placed = [];
        for (int row = 0; row < 24; row++)
        {
            for (int column = 0; column < 40; column++)
            {
                int offset = ((row & 7) * 128) + ((row >> 3) * 40) + column;
                Assert.AreEqual($"row {row}, column {column}", DebugRegion.AppleText(offset));
                placed.Add(offset);
            }
        }

        foreach (int offset in Enumerable.Range(0, 0x400).Where(offset => !placed.Contains(offset)))
        {
            Assert.AreEqual("screen hole", DebugRegion.AppleText(offset), $"${offset:X3}");
        }
    }

    /// <summary>
    ///  Every line and byte of an Apple II hi-res page is the one its address is, as HPOSN works it out.
    /// </summary>
    [TestMethod]
    public void AppleHiresFindsEachLineAndByte()
    {
        HashSet<int> placed = [];
        for (int line = 0; line < 192; line++)
        {
            for (int column = 0; column < 40; column++)
            {
                int offset = ((line & 7) * 0x400) + (((line >> 3) & 7) * 0x80) + ((line >> 6) * 40) + column;
                Assert.AreEqual($"line {line}, byte {column} (dots {column * 7}-{(column * 7) + 6})", DebugRegion.AppleHires(offset));
                placed.Add(offset);
            }
        }

        Assert.AreEqual(0x2000 - (192 * 40), Enumerable.Range(0, 0x2000).Count(offset => DebugRegion.AppleHires(offset) == "screen hole"));
        Assert.AreEqual(192 * 40, placed.Count);
    }

    /// <summary>
    ///  The narrowest region holding an address names it, so a text page inside RAM is the text page.
    /// </summary>
    [TestMethod]
    public void TheNarrowestRegionNamesAnAddress()
    {
        DebugRegion[] regions = [new("RAM", 0x0000, 0xC000, "ram"), new("Text page 1", 0x0400, 0x400, "video")];
        Assert.AreEqual("Text page 1", DebugRegion.At(regions, 0x0400)?.Name);
        Assert.AreEqual("RAM", DebugRegion.At(regions, 0x0800)?.Name);
        Assert.IsNull(DebugRegion.At(regions, 0xC000));
    }
}
