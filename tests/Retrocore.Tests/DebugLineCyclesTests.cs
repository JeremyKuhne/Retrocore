// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Verifies changes to source-line cycle counts since the last event.
/// </summary>
[TestClass]
public class DebugLineCyclesTests
{
    /// <summary>
    ///  A partial line that returns to the last-sent count is not a change.
    /// </summary>
    [TestMethod]
    public void RestoredCountIsNotChanged()
    {
        DebugLineCycles lines = new();
        (string Path, int Line) line = ("test", 1);
        lines.Update(line, 8, entered: true, track: true);
        lines.Sent();

        lines.Update(line, 4, entered: true, track: true);
        lines.Changed.Should().BeTrue();
        lines.Update(line, 4, entered: false, track: true);
        lines.Last[line].Should().Be(8UL);
        lines.Changed.Should().BeFalse();

        lines.Update(line, 9, entered: true, track: true);
        lines.Changed.Should().BeTrue();
        lines.Sent();
        lines.Update(line, 8, entered: true, track: true);
        lines.Changed.Should().BeTrue();
    }

    /// <summary>
    ///  New zero counts are changes and clearing removes all tracked counts.
    /// </summary>
    [TestMethod]
    public void NewZeroCountAndClear()
    {
        DebugLineCycles lines = new();
        (string Path, int Line) line = ("test", 1);
        lines.Update(line, 0, entered: true, track: true);
        lines.Changed.Should().BeTrue();
        lines.Sent();
        lines.Update(line, 0, entered: true, track: true);
        lines.Changed.Should().BeFalse();
        lines.Clear();
        lines.Last.Should().BeEmpty();
        lines.Update(line, 0, entered: true, track: true);
        lines.Changed.Should().BeTrue();
    }

    /// <summary>
    ///  Restoring one line does not hide another line's change.
    /// </summary>
    [TestMethod]
    public void ChangesAreTrackedIndependently()
    {
        DebugLineCycles lines = new();
        (string Path, int Line) first = ("test", 1);
        (string Path, int Line) second = ("test", 2);
        lines.Update(first, 8, entered: true, track: true);
        lines.Update(second, 4, entered: true, track: true);
        lines.Sent();
        lines.Update(first, 3, entered: true, track: true);
        lines.Update(second, 6, entered: true, track: true);
        lines.Update(first, 8, entered: true, track: true);
        lines.Changed.Should().BeTrue();
        lines.Update(second, 4, entered: true, track: true);
        lines.Changed.Should().BeFalse();
    }
}
