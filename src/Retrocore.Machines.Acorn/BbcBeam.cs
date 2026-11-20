// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  Where the BBC Micro's beam is, and the frame it draws into: <see cref="BbcVideo.FrameWidth"/> by
///  <see cref="BbcVideo.FrameHeight"/> RGBA, two pixel rows to a line.
/// </summary>
internal struct BbcBeam
{
    /// <summary>
    ///  The frame.
    /// </summary>
    public byte[] Pixels;

    /// <summary>
    ///  The 2 MHz cycles since the horizontal sync started.
    /// </summary>
    public int Cycle;

    /// <summary>
    ///  The frame's line, counted from 0 at the first one drawn; negative above the frame.
    /// </summary>
    public int Line;

    /// <summary>
    ///  The 6845's horizontal sync, as last seen.
    /// </summary>
    public bool HorizontalSync;

    /// <summary>
    ///  The 6845's vertical sync, as last seen.
    /// </summary>
    public bool VerticalSync;

    /// <summary>
    ///  The 6845's display enable, as last seen.
    /// </summary>
    public bool Display;

    /// <summary>
    ///  Whether this is an interlaced picture's odd field, drawn on the odd pixel rows.
    /// </summary>
    public bool OddField;

    /// <summary>
    ///  Whether the picture is interlaced, each field drawing alternate pixel rows.
    /// </summary>
    public bool Interlaced;

    /// <summary>
    ///  The cursor's characters still to come, four from the 6845's cursor output, each shown as the control register says.
    /// </summary>
    public int CursorLeft;

    // The last four characters' address, raster line and display enable, 20 bits each, newest first: the address in
    // bits 6-19, the line in bits 1-5, display enable in bit 0. Four take 80 bits, more than a long holds.
    private UInt128 _pipeline;

    /// <summary>
    ///  Takes in a character's address, raster line and display enable, before any skew.
    /// </summary>
    /// <param name="address">The 6845's address.</param>
    /// <param name="line">The raster line.</param>
    /// <param name="display">The display enable.</param>
    public void Push(int address, int line, bool display) =>
        _pipeline = (_pipeline << 20) | (uint)((address << 6) | ((line & 0x1F) << 1) | (display ? 1 : 0));

    /// <summary>
    ///  Gets a character's address, raster line and display enable from some characters back.
    /// </summary>
    /// <param name="characters">How far back, 0-3.</param>
    /// <returns>The character.</returns>
    public readonly (int Address, int Line, bool Display) Delayed(int characters)
    {
        uint entry = (uint)(_pipeline >> (characters * 20)) & 0xFFFFF;
        return ((int)(entry >> 6) & 0x3FFF, (int)(entry >> 1) & 0x1F, (entry & 1) != 0);
    }

    /// <summary>
    ///  Gets the pixels a character covers on this line's pixel row.
    /// </summary>
    /// <param name="x">The character's first pixel.</param>
    /// <param name="width">Its width in pixels.</param>
    /// <returns>The pixels, or empty when the character is off the frame.</returns>
    public readonly Span<byte> Row(int x, int width)
    {
        int y = PixelRow;
        if (y < 0 || x < 0 || x + width > BbcVideo.FrameWidth) { return []; }
        return Pixels.AsSpan(((y * BbcVideo.FrameWidth) + x) * 4, width * 4);
    }

    /// <summary>
    ///  Starts a line: the line before is copied down a pixel row unless the picture is interlaced, and the new line's
    ///  row is cleared to black.
    /// </summary>
    public readonly void Clear()
    {
        int stride = BbcVideo.FrameWidth * 4;
        int previous = RowOf(Line - 1);
        if (!Interlaced && previous >= 0 && previous + 1 < BbcVideo.FrameHeight)
        {
            Pixels.AsSpan(previous * stride, stride).CopyTo(Pixels.AsSpan((previous + 1) * stride, stride));
        }

        int y = PixelRow;
        if (y < 0) { return; }
        Span<byte> row = Pixels.AsSpan(y * stride, stride);
        for (int offset = 0; offset < row.Length; offset += 4)
        {
            row[offset] = row[offset + 1] = row[offset + 2] = 0;
            row[offset + 3] = 0xFF;
        }
    }

    private readonly int PixelRow => RowOf(Line);

    private readonly int RowOf(int line) =>
        line is >= 0 and < BbcVideo.FrameHeight / 2 ? (line * 2) + (Interlaced && OddField ? 1 : 0) : -1;
}
