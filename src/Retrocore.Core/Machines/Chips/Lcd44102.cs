// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Hitachi HD44102 dot-matrix LCD column driver: 50 columns of 32 dots, held as four pages of 50 bytes, each byte
///  a column of eight dots.
/// </summary>
/// <remarks>
///  <para>
///   From Hitachi's 1983 <i>MOS LSI Data Book: LCD Driver LSI</i>. The D/I line picks an instruction (low) or display
///   data (high). Instructions: <c>$39</c> display on and <c>$38</c> off; <c>$3B</c> count up and <c>$3A</c> down;
///   <c>pp111110</c> sets the display start page; otherwise <c>ppyyyyyy</c> sets the page (X) and the column (Y, 0 to
///   49). Each data read or write moves the column on by one, up or down, wrapping between 0 and 49; the page does
///   not change. A read returns the output register, then loads it from the current address, so the first read after
///   setting an address is a dummy. Status: bit 7 busy, bit 6 counting up, bit 5 display off, bit 4 in reset (0
///   here, as reset is taken at once).
///  </para>
///  <para>
///   Instructions are taken at once, so busy always reads 0; the chip's few microseconds of busy time are shorter
///   than any 8085 instruction between two accesses. Power-on leaves it as its RST line does: the display off and
///   counting up.
///  </para>
/// </remarks>
public sealed class Lcd44102
{
    /// <summary>
    ///  The columns one driver has.
    /// </summary>
    public const int Columns = 50;

    /// <summary>
    ///  The pages of eight dots one driver has.
    /// </summary>
    public const int Pages = 4;

    private readonly byte[] _ram = new byte[Pages * Columns];
    private int _page;
    private int _column;
    private byte _output;

    /// <summary>
    ///  Creates a driver as its RST line leaves it.
    /// </summary>
    public Lcd44102() => Reset();

    /// <summary>
    ///  Gets whether the display is on.
    /// </summary>
    public bool DisplayOn { get; private set; }

    /// <summary>
    ///  Gets whether the column counts up after each access.
    /// </summary>
    public bool CountUp { get; private set; }

    /// <summary>
    ///  Gets the page shown at the top of the display.
    /// </summary>
    public int StartPage { get; private set; }

    /// <summary>
    ///  Gets the page that reads and writes reach.
    /// </summary>
    public int Page => _page;

    /// <summary>
    ///  Gets the column that the next read or write reaches.
    /// </summary>
    public int Column => _column;

    /// <summary>
    ///  Resets the driver, as its RST line does: the display goes off and the column counts up. The RAM keeps its
    ///  contents.
    /// </summary>
    public void Reset()
    {
        DisplayOn = false;
        CountUp = true;
    }

    /// <summary>
    ///  Gets a column of the display RAM: eight dots, bit 0 the top one.
    /// </summary>
    /// <param name="page">The page, 0 to 3.</param>
    /// <param name="column">The column, 0 to 49.</param>
    /// <returns>The byte.</returns>
    public byte this[int page, int column] => _ram[(page & 3) * Columns + column];

    /// <summary>
    ///  Gets whether a dot is lit, counting rows from the top of the display, after the start page's scrolling.
    /// </summary>
    /// <param name="row">The row, 0 to 31.</param>
    /// <param name="column">The column, 0 to 49.</param>
    /// <returns>Whether the dot is lit; always false with the display off.</returns>
    public bool Dot(int row, int column)
    {
        if (!DisplayOn) { return false; }
        int line = (row + StartPage * 8) & 31;
        return (_ram[(line >> 3) * Columns + column] & (1 << (line & 7))) != 0;
    }

    /// <summary>
    ///  Writes an instruction (D/I low) or display data (D/I high).
    /// </summary>
    /// <param name="data">The D/I line: true for display data.</param>
    /// <param name="value">The byte.</param>
    public void Write(bool data, byte value)
    {
        if (data)
        {
            _ram[_page * Columns + _column] = value;
            Advance();
            return;
        }

        switch (value & 0x3F)
        {
            case 0x38:
                DisplayOn = false;
                break;
            case 0x39:
                DisplayOn = true;
                break;
            case 0x3A:
                CountUp = false;
                break;
            case 0x3B:
                CountUp = true;
                break;
            case 0x3E:
                StartPage = value >> 6;
                break;
            case < Columns:
                _page = value >> 6;
                _column = value & 0x3F;
                break;
        }
    }

    /// <summary>
    ///  Reads the status (D/I low) or display data (D/I high).
    /// </summary>
    /// <param name="data">The D/I line: true for display data.</param>
    /// <returns>The byte.</returns>
    public byte Read(bool data)
    {
        if (!data) { return Status; }
        byte value = _output;
        _output = _ram[_page * Columns + _column];
        Advance();
        return value;
    }

    /// <summary>
    ///  Reads as <see cref="Read"/> would, without side effects.
    /// </summary>
    /// <param name="data">The D/I line: true for display data.</param>
    /// <returns>The byte.</returns>
    public byte Peek(bool data) => data ? _output : Status;

    private byte Status => (byte)((CountUp ? 0x40 : 0) | (DisplayOn ? 0 : 0x20));

    private void Advance() => _column = CountUp
        ? (_column + 1) % Columns
        : (_column + Columns - 1) % Columns;
}
