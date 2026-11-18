// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  The 6845's counters, syncs, cursor and interlace, stepped a character at a time.
/// </summary>
[TestClass]
public class Crtc6845Tests
{
    /// <summary>
    ///  A small frame: 10 characters a line, 6 displayed, sync at 8 for 2; 4 rows of 2 lines and 1 adjust line, 3
    ///  displayed, vertical sync at row 3 for 1 line; start address $100.
    /// </summary>
    /// <returns>The CRTC, at the top of the frame.</returns>
    private static Crtc6845 Small()
    {
        Crtc6845 crtc = new();
        byte[] values = [9, 6, 8, 0x12, 3, 1, 3, 3, 0, 1, 0x00, 0, 0x01, 0x00, 0x01, 0x07];
        for (int register = 0; register < values.Length; register++)
        {
            crtc.Write(0, (byte)register);
            crtc.Write(1, values[register]);
        }

        crtc.Reset();
        return crtc;
    }

    /// <summary>
    ///  Each line steps the address across the displayed characters; each row starts R1 on from the last.
    /// </summary>
    [TestMethod]
    public void AddressesFollowRowsAndLines()
    {
        Crtc6845 crtc = Small();
        crtc.Address.Should().Be(0x100);
        crtc.DisplayEnable.Should().BeTrue();

        for (int i = 0; i < 6; i++) { crtc.Tick(); }
        crtc.DisplayEnable.Should().BeFalse("character 6 is past R1");
        crtc.Address.Should().Be(0x106);

        for (int i = 0; i < 4; i++) { crtc.Tick(); }
        crtc.RowAddress.Should().Be(1);
        crtc.Address.Should().Be(0x100, "the second line of a row repeats its addresses");

        for (int i = 0; i < 10; i++) { crtc.Tick(); }
        crtc.RowAddress.Should().Be(0);
        crtc.Address.Should().Be(0x106, "the next row starts R1 characters on");
    }

    /// <summary>
    ///  The horizontal sync starts at R2 and lasts R3's low nibble; the vertical sync starts at row R7 and lasts R3's
    ///  high nibble in lines; a frame is (R4 + 1) × (R9 + 1) + R5 lines.
    /// </summary>
    [TestMethod]
    public void SyncsAndFrameLength()
    {
        Crtc6845 crtc = Small();
        int horizontal = 0;
        int firstHorizontal = -1;
        for (int i = 0; i < 10; i++)
        {
            crtc.Tick();
            if (crtc.HorizontalSync)
            {
                horizontal++;
                if (firstHorizontal < 0) { firstHorizontal = i + 1; }
            }
        }

        firstHorizontal.Should().Be(8);
        horizontal.Should().Be(2);

        crtc.Reset();
        int fields = crtc.Fields;
        int lines = 0;
        int verticalLines = 0;
        while (crtc.Fields == fields)
        {
            for (int i = 0; i < 10; i++) { crtc.Tick(); }
            lines++;
            if (crtc.VerticalSync) { verticalLines++; }
        }

        lines.Should().Be(9, "4 rows of 2 lines and 1 adjust line");
        verticalLines.Should().Be(1);
    }

    /// <summary>
    ///  The cursor shows at R14-R15 on lines R10-R11; blink mode 1 hides it.
    /// </summary>
    [TestMethod]
    public void CursorShowsAtItsAddress()
    {
        Crtc6845 crtc = Small();
        crtc.Write(0, 15);
        crtc.Write(1, 0x02);
        crtc.Write(0, 11);
        crtc.Write(1, 1);
        crtc.Reset();
        crtc.Tick();
        crtc.Tick();
        crtc.Cursor.Should().BeTrue();
        crtc.Tick();
        crtc.Cursor.Should().BeFalse();

        crtc.Write(0, 10);
        crtc.Write(1, 0x20);
        crtc.Reset();
        crtc.Tick();
        crtc.Tick();
        crtc.Cursor.Should().BeFalse("blink mode 1 turns the cursor off");
    }

    /// <summary>
    ///  In interlace sync and video mode the raster line counts by two from the field's parity, and the skews delay
    ///  the display enable and cursor.
    /// </summary>
    [TestMethod]
    public void InterlaceAndSkew()
    {
        Crtc6845 crtc = Small();
        crtc.Write(0, 8);
        crtc.Write(1, 0x13);
        crtc.Write(0, 9);
        crtc.Write(1, 3);
        crtc.Reset();
        crtc.DisplayEnable.Should().BeFalse("the display skew is 1");
        crtc.Displayed.Should().BeTrue();
        crtc.Tick();
        crtc.DisplayEnable.Should().BeTrue();

        for (int i = 0; i < 9; i++) { crtc.Tick(); }
        crtc.RowAddress.Should().Be(2, "lines count by two");

        int fields = crtc.Fields;
        while (crtc.Fields == fields) { crtc.Tick(); }
        crtc.OddField.Should().BeTrue();
        crtc.RowAddress.Should().Be(1, "the odd field starts on line 1");
    }
}
