// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's 240x64 LCD: ten HD44102 column drivers, five across the top half and five across the bottom.
/// </summary>
/// <remarks>
///  <para>
///   Drivers 0-4 make the top 32 rows, left to right, and 5-9 the bottom 32. Each drives 50 columns but for the
///   rightmost of each row, 4 and 9, of which only the first 40 are wired, so their last 10 columns are RAM the
///   panel does not show (Bitchin100's "Model 100 LCD Programming"). The CPU reaches every driver whose chip select
///   is high, port A's bits selecting drivers 0-7 and port B's bits 0 and 1 drivers 8 and 9; a read from several at
///   once ORs them, as MAME has it. Port $FE (any even port of $F0-$FF) carries instructions and status, and $FF
///   (any odd one) display data.
///  </para>
/// </remarks>
public sealed class Trs80Model100Lcd : IVideoSource
{
    /// <summary>
    ///  The panel's width in dots.
    /// </summary>
    public const int Width = 240;

    /// <summary>
    ///  The panel's height in dots.
    /// </summary>
    public const int Height = 64;

    private const int Drivers = 10;

    // The panel's colors: dark dots on a gray-green ground.
    private static readonly byte[] s_lit = [0x28, 0x30, 0x28];
    private static readonly byte[] s_unlit = [0xA8, 0xB4, 0x98];

    private readonly Lcd44102[] _drivers = new Lcd44102[Drivers];

    /// <summary>
    ///  Builds the panel's drivers, as power-on leaves them.
    /// </summary>
    internal Trs80Model100Lcd()
    {
        for (int index = 0; index < Drivers; index++) { _drivers[index] = new(); }
    }

    /// <summary>
    ///  Gets a column driver.
    /// </summary>
    /// <param name="index">The driver, 0 to 9.</param>
    /// <returns>The driver.</returns>
    public Lcd44102 this[int index] => _drivers[index];

    /// <summary>
    ///  Gets or sets whether the panel is blank, as it is with the power off.
    /// </summary>
    public bool Blank { get; internal set; }

    int IVideoSource.Width => Width;

    int IVideoSource.Height => Height;

    int IVideoSource.CyclesPerFrame => Trs80Model100Timing.CyclesPerFrame;

    /// <summary>
    ///  Gets whether a dot of the panel is lit.
    /// </summary>
    /// <param name="x">The column, 0 to 239.</param>
    /// <param name="y">The row, 0 to 63.</param>
    /// <returns>Whether it is dark.</returns>
    public bool Dot(int x, int y)
    {
        int driver = (y >> 5) * 5 + x / Lcd44102.Columns;
        return _drivers[driver].Dot(y & 31, x % Lcd44102.Columns);
    }

    /// <summary>
    ///  Renders the panel, a pixel to a dot.
    /// </summary>
    /// <param name="pixels">Exactly 240 x 64 x 4 bytes of RGBA.</param>
    /// <param name="scanned">Not used: the panel shows the drivers' RAM as it is, or nothing while it is blank.</param>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException("The span is the wrong size.", nameof(pixels));
        }

        int offset = 0;
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                byte[] color = !Blank && Dot(x, y) ? s_lit : s_unlit;
                pixels[offset] = color[0];
                pixels[offset + 1] = color[1];
                pixels[offset + 2] = color[2];
                pixels[offset + 3] = 0xFF;
                offset += 4;
            }
        }
    }

    /// <summary>
    ///  Writes every selected driver.
    /// </summary>
    /// <param name="select">The chip selects, driver 0 in bit 0.</param>
    /// <param name="data">Whether the byte is display data (an odd port) rather than an instruction.</param>
    /// <param name="value">The byte.</param>
    internal void Write(int select, bool data, byte value)
    {
        for (int index = 0; index < Drivers; index++)
        {
            if ((select & (1 << index)) != 0) { _drivers[index].Write(data, value); }
        }
    }

    /// <summary>
    ///  Reads every selected driver, ORing what they return; 0 with none selected.
    /// </summary>
    /// <param name="select">The chip selects, driver 0 in bit 0.</param>
    /// <param name="data">Whether to read display data (an odd port) rather than status.</param>
    /// <param name="peek">Whether to read without side effects.</param>
    /// <returns>The byte.</returns>
    internal byte Read(int select, bool data, bool peek)
    {
        int value = 0;
        for (int index = 0; index < Drivers; index++)
        {
            if ((select & (1 << index)) != 0)
            {
                value |= peek ? _drivers[index].Peek(data) : _drivers[index].Read(data);
            }
        }

        return (byte)value;
    }

    /// <summary>
    ///  Resets every driver, as power-on does.
    /// </summary>
    internal void Reset()
    {
        foreach (Lcd44102 driver in _drivers) { driver.Reset(); }
    }
}
