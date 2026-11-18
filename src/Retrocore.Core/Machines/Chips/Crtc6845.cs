// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A 6845 CRT controller: the character, raster and frame counters that address video memory and time the syncs,
///  stepped one character clock at a time.
/// </summary>
/// <remarks>
///  <para>
///   The registers: R0 horizontal total (characters per line, less one), R1 horizontal displayed, R2 horizontal sync
///   position, R3 sync widths (bits 0-3 horizontal in characters, bits 4-7 vertical in lines; 0 means 16), R4
///   vertical total (character rows, less one), R5 vertical total adjust (extra lines), R6 vertical displayed, R7
///   vertical sync position, R8 interlace mode (bits 0-1) with the Hitachi HD6845S's display and cursor skew (bits
///   4-5 and 6-7, in characters; 3 disables), R9 maximum raster address (lines per row, less one), R10 cursor start
///   line with its blink mode (bits 5-6: steady, off, blink every 16 fields, every 32), R11 cursor end line, R12 and
///   R13 the start address, R14 and R15 the cursor address, and R16 and R17 the light pen address.
///  </para>
///  <para>
///   Each <see cref="Tick"/> ends one character and starts the next; the properties then describe the new character:
///   its memory address (<see cref="Address"/>) and raster line (<see cref="RowAddress"/>), and the display enable,
///   cursor and sync outputs. In interlace sync and video mode (R8 = 3) the raster line counts by two, from 0 in the
///   even field and 1 in the odd one, so each field draws half the lines of a row.
///  </para>
/// </remarks>
public sealed class Crtc6845
{
    private static readonly byte[] s_writeMasks =
        [0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x1F, 0x7F, 0x7F, 0xF3, 0x1F, 0x7F, 0x1F, 0x3F, 0xFF, 0x3F, 0xFF, 0x3F, 0xFF];

    private readonly byte[] _registers = new byte[18];
    private int _select;
    private int _column;
    private int _row;
    private int _line;
    private int _adjustLine;
    private bool _adjusting;
    private ushort _address;
    private ushort _rowStart;
    private bool _columnDisplay = true;
    private bool _rowDisplay = true;
    private int _horizontalSyncLeft;
    private int _verticalSyncLeft;
    private int _fields;

    // The display enable and cursor of the last three characters, newest in bit 0, for the skews.
    private int _displayHistory;
    private int _cursorHistory;

    /// <summary>
    ///  Gets the memory address of the current character: 14 bits.
    /// </summary>
    public ushort Address => _address;

    /// <summary>
    ///  Gets the raster line within the current character row: 5 bits.
    /// </summary>
    public int RowAddress => _line;

    /// <summary>
    ///  Gets the display enable output, after the display skew: whether the current character is in the displayed area.
    /// </summary>
    public bool DisplayEnable => Skewed(_displayHistory, DisplaySkew);

    /// <summary>
    ///  Gets the cursor output, after the cursor skew.
    /// </summary>
    public bool Cursor => Skewed(_cursorHistory, CursorSkew);

    /// <summary>
    ///  Gets whether the current character is in the displayed area, before the display skew.
    /// </summary>
    public bool Displayed => (_displayHistory & 1) != 0;

    /// <summary>
    ///  Gets the characters the display enable output lags the address by: R8 bits 4-5, where 3 turns it off.
    /// </summary>
    public int DisplaySkew => (_registers[8] >> 4) & 3;

    /// <summary>
    ///  Gets the characters the cursor output lags the address by: R8 bits 6-7, where 3 turns it off.
    /// </summary>
    public int CursorSkew => (_registers[8] >> 6) & 3;

    /// <summary>
    ///  Gets the horizontal sync output.
    /// </summary>
    public bool HorizontalSync => _horizontalSyncLeft > 0;

    /// <summary>
    ///  Gets the vertical sync output.
    /// </summary>
    public bool VerticalSync => _verticalSyncLeft > 0;

    /// <summary>
    ///  Gets whether the frame being drawn is the odd field of an interlaced picture.
    /// </summary>
    public bool OddField => Interlaced && (_fields & 1) != 0;

    /// <summary>
    ///  Gets whether R8 selects an interlaced picture (interlace sync, or interlace sync and video).
    /// </summary>
    public bool Interlaced => (_registers[8] & 1) != 0;

    /// <summary>
    ///  Gets the number of fields begun since power-on, which times the cursor's blinking.
    /// </summary>
    public int Fields => _fields;

    /// <summary>
    ///  Gets a register's value, as last written (or latched, for the light pen).
    /// </summary>
    /// <param name="register">The register, 0-17.</param>
    /// <returns>The value.</returns>
    public byte this[int register] => _registers[register];

    /// <summary>
    ///  Gets the start address, from R12 and R13.
    /// </summary>
    public ushort StartAddress => (ushort)((_registers[12] << 8) | _registers[13]);

    /// <summary>
    ///  Gets the cursor address, from R14 and R15.
    /// </summary>
    public ushort CursorAddress => (ushort)((_registers[14] << 8) | _registers[15]);

    /// <summary>
    ///  Writes the address register (<paramref name="register"/> even) or the selected register (odd).
    /// </summary>
    /// <param name="register">The register select: bit 0 chooses the data register.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        if ((register & 1) == 0)
        {
            _select = value & 0x1F;
            return;
        }

        if (_select < 16) { _registers[_select] = (byte)(value & s_writeMasks[_select]); }
    }

    /// <summary>
    ///  Reads the status (<paramref name="register"/> even), which reads as 0, or the selected register (odd). Only the
    ///  cursor and light pen registers, R14-R17, can be read; the others read as 0.
    /// </summary>
    /// <param name="register">The register select.</param>
    /// <returns>The value.</returns>
    public byte Read(int register) => (register & 1) != 0 && _select is >= 14 and < 18 ? _registers[_select] : (byte)0;

    /// <summary>
    ///  Latches the current address into the light pen registers, as a strobe on LPSTB does.
    /// </summary>
    public void StrobeLightPen()
    {
        _registers[16] = (byte)(_address >> 8 & 0x3F);
        _registers[17] = (byte)_address;
    }

    /// <summary>
    ///  Ends the current character and starts the next one.
    /// </summary>
    public void Tick()
    {
        if (_horizontalSyncLeft > 0) { _horizontalSyncLeft--; }

        if (_column == _registers[0])
        {
            EndLine();
        }
        else
        {
            _column++;
            _address = (ushort)((_address + 1) & 0x3FFF);
        }

        if (_column == _registers[1]) { _columnDisplay = false; }

        if (_column == _registers[2])
        {
            int width = _registers[3] & 0x0F;
            _horizontalSyncLeft = width == 0 ? 16 : width;
        }

        UpdateOutputs();
    }

    /// <summary>
    ///  Copies the counters and registers, so a frame can be drawn ahead without disturbing this one.
    /// </summary>
    /// <returns>The copy.</returns>
    public Crtc6845 Clone()
    {
        Crtc6845 copy = (Crtc6845)MemberwiseClone();
        _registers.CopyTo(copy._registers, 0);
        return copy;
    }

    /// <summary>
    ///  Resets the counters to the top of a frame, keeping the registers, as the RESET input does.
    /// </summary>
    public void Reset()
    {
        _column = 0;
        _row = 0;
        _line = 0;
        _adjusting = false;
        _adjustLine = 0;
        _rowStart = _address = StartAddress;
        _columnDisplay = _rowDisplay = true;
        _horizontalSyncLeft = _verticalSyncLeft = 0;
        _displayHistory = _cursorHistory = 0;
        UpdateOutputs();
    }

    private static bool Skewed(int history, int skew) => skew != 3 && (history & (1 << skew)) != 0;

    private bool SyncAndVideo => (_registers[8] & 3) == 3;

    // The last line of a row: the maximum raster address, which in interlace sync and video mode either field reaches
    // with its own parity.
    private bool LastLine => SyncAndVideo ? (_line | 1) >= (_registers[9] | 1) : _line >= _registers[9];

    private void EndLine()
    {
        _column = 0;
        _columnDisplay = true;
        if (_verticalSyncLeft > 0) { _verticalSyncLeft--; }

        if (_adjusting)
        {
            if (++_adjustLine >= _registers[5]) { StartFrame(); }
            else { _address = _rowStart; }

            return;
        }

        if (LastLine)
        {
            _rowStart = (ushort)((_rowStart + _registers[1]) & 0x3FFF);
            if (_row == _registers[4])
            {
                if (_registers[5] == 0)
                {
                    StartFrame();
                }
                else
                {
                    _adjusting = true;
                    _adjustLine = 0;
                    _line = 0;
                    _address = _rowStart;
                }

                return;
            }

            _row = (_row + 1) & 0x7F;
            _line = SyncAndVideo && OddField ? 1 : 0;
            StartRow();
        }
        else
        {
            _line = (_line + (SyncAndVideo ? 2 : 1)) & 0x1F;
        }

        _address = _rowStart;
    }

    private void StartFrame()
    {
        _adjusting = false;
        _fields++;
        _row = 0;
        _line = SyncAndVideo && OddField ? 1 : 0;
        _rowStart = _address = StartAddress;
        _rowDisplay = true;
        StartRow();
    }

    private void StartRow()
    {
        if (_row == _registers[6]) { _rowDisplay = false; }
        if (_row == _registers[7] && _verticalSyncLeft == 0)
        {
            int height = _registers[3] >> 4;
            _verticalSyncLeft = height == 0 ? 16 : height;
        }
    }

    private void UpdateOutputs()
    {
        bool display = _columnDisplay && _rowDisplay && !_adjusting;
        _displayHistory = ((_displayHistory << 1) | (display ? 1 : 0)) & 0x0F;

        bool cursor = false;
        if (display && _address == CursorAddress)
        {
            int start = _registers[10] & 0x1F;
            int end = _registers[11];
            bool lines = start <= end ? _line >= start && _line <= end : _line >= start || _line <= end;
            cursor = lines && (((_registers[10] >> 5) & 3) switch
            {
                0 => true,
                1 => false,
                2 => (_fields & 8) != 0,
                _ => (_fields & 16) != 0
            });
        }

        _cursorHistory = ((_cursorHistory << 1) | (cursor ? 1 : 0)) & 0x0F;
    }
}
