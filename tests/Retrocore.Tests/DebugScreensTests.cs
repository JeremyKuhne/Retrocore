// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The debugger's monitors: a machine's video shown on a monochrome monitor lights each pixel in the phosphor's
///  color by its brightness.
/// </summary>
[TestClass]
public sealed class DebugScreensTests
{
    [TestMethod]
    public void MonochromeMonitorsLightThePhosphorByBrightness()
    {
        // The terminals' white and near-black, and a pure blue as the Apple III shows it.
        byte[] pixels = [240, 240, 240, 255, 16, 16, 16, 255, 0, 0, 255, 255];
        DebugScreens.Show(pixels, DebugScreens.Green);
        Assert.AreEqual<byte>(51, pixels[0]);
        Assert.AreEqual<byte>(255, pixels[1]);
        Assert.AreEqual<byte>(102, pixels[2]);
        Assert.AreEqual<byte>(255, pixels[3], "alpha is left alone");
        Assert.AreEqual<byte>(17, pixels[5], "the dark background glows faintly");
        Assert.AreEqual<byte>(30, pixels[9], "blue is dim on a monochrome monitor");
    }

    [TestMethod]
    public void WhiteLeavesTheTerminalsAsTheyAreAndColorLeavesEverything()
    {
        byte[] white = [240, 240, 240, 255, 16, 16, 16, 255];
        byte[] shown = [.. white];
        DebugScreens.Show(shown, DebugScreens.White);
        CollectionAssert.AreEqual(white, shown);

        byte[] colors = [255, 0, 0, 255, 0, 128, 255, 255];
        byte[] unchanged = [.. colors];
        DebugScreens.Show(unchanged, DebugScreens.Color);
        CollectionAssert.AreEqual(colors, unchanged);
    }

    [TestMethod]
    public void AMachineTakesOnlyItsOwnMonitors()
    {
        Assert.AreEqual(DebugScreens.Amber, DebugScreens.Require(DebugScreens.Amber, DebugScreens.Monochrome));
        ArgumentException error = Assert.ThrowsExactly<ArgumentException>(
            () => DebugScreens.Require(DebugScreens.Color, DebugScreens.Monochrome));
        Assert.AreEqual("screen must be green, white or amber on this machine.", error.Message);
    }
}
