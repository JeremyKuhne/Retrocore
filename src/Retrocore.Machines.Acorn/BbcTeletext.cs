// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The SAA5050 teletext character generator behind mode 7: each character code becomes 12 half-dots of a row, in a
///  foreground and a background colour, with the teletext control codes interpreted as they arrive.
/// </summary>
/// <remarks>
///  <para>
///   A character is 6 dots wide and 10 lines high, drawn in 20 half-lines over the two fields of an interlaced
///   picture. The chip smooths diagonals: a half-line also lights a half-dot where the line above or below has a
///   diagonal step, which the field (CRS, the 6845's raster bit 0) chooses between.
///  </para>
///  <para>
///   Codes <c>$00-$1F</c> are spaces that change the attributes. Alphanumeric colours (<c>$01-$07</c>), graphics
///   colours (<c>$11-$17</c>), flash (<c>$08</c>), double height (<c>$0D</c>) and release graphics (<c>$1F</c>) take
///   effect from the next character; steady (<c>$09</c>), normal height (<c>$0C</c>), conceal (<c>$18</c>),
///   contiguous and separated graphics (<c>$19</c>, <c>$1A</c>), black and new background (<c>$1C</c>, <c>$1D</c>)
///   and hold graphics (<c>$1E</c>) from this one. Each line starts white alphanumerics on black, steady, normal
///   height. In graphics, codes with bit 5 set are 2 × 3 blocks (bits 0-4 and 6); the others are still capitals.
///   With hold graphics, a control code shows the last graphics character instead of a space.
///  </para>
///  <para>
///   The chip counts the lines of a row itself: the field's vertical sync (DEW) restarts the count, and each line's
///   display enable (LOSE) steps it. After a row with double height, the next row shows the bottom halves of its
///   double-height characters, and nothing else.
///  </para>
/// </remarks>
internal sealed class BbcTeletext
{
    private readonly ushort[] _rounded = new ushort[128 * 20];
    private int _line;
    private int _frames;
    private int _foreground;
    private int _background;
    private int _previousForeground;
    private bool _graphics;
    private bool _separated;
    private bool _flash;
    private bool _hold;
    private bool _doubleHeight;
    private bool _doubleHeightInRow;
    private bool _bottomRow;
    private byte _held;
    private bool _heldSeparated;
    private bool _nextGraphics;
    private bool _nextSeparated;
    private bool _currentGraphics;
    private bool _currentSeparated;

    /// <summary>
    ///  Creates the generator.
    /// </summary>
    /// <param name="characters">The 960-byte character ROM, characters <c>$20-$7F</c>.</param>
    internal BbcTeletext(ReadOnlySpan<byte> characters)
    {
        for (int code = 0; code < 128; code++)
        {
            for (int half = 0; half < 20; half++)
            {
                ushort here = Dots(characters, code, half);
                ushort next = Dots(characters, code, half + ((half & 1) != 0 ? 1 : -1));
                _rounded[(code * 20) + half] =
                    (ushort)(here | ((here >> 1) & next & ~(next >> 1)) | ((here << 1) & next & ~(next << 1)));
            }
        }

        StartLine();
    }

    /// <summary>
    ///  Gets the foreground colour of the last character: bit 0 red, bit 1 green, bit 2 blue.
    /// </summary>
    internal int Foreground => _previousForeground;

    /// <summary>
    ///  Gets the background colour of the last character.
    /// </summary>
    internal int Background => _background;

    /// <summary>
    ///  Starts a field, on the vertical sync: the line count starts again, the first row is a top row, and the flash
    ///  timer steps.
    /// </summary>
    internal void StartField()
    {
        _line = 9;
        _bottomRow = _doubleHeightInRow = false;
        _frames = (_frames + 1) & 0x3F;
    }

    /// <summary>
    ///  Starts a line, as the display enable rises: the attributes go back to white alphanumerics on black.
    /// </summary>
    internal void StartLine()
    {
        _line = (_line + 1) % 10;
        if (_line == 0) { _bottomRow = !_bottomRow && _doubleHeightInRow; }

        _foreground = 7;
        _background = 0;
        _graphics = _separated = _flash = _hold = _doubleHeight = false;
        _doubleHeightInRow = false;
        _held = 0x20;
        _heldSeparated = false;
        _nextGraphics = _nextSeparated = false;
    }

    /// <summary>
    ///  Generates one character's half-line.
    /// </summary>
    /// <param name="code">The 7-bit code.</param>
    /// <param name="oddField">CRS: the odd field's half-lines.</param>
    /// <returns>12 half-dots, the leftmost in bit 11, lit in <see cref="Foreground"/>.</returns>
    internal ushort Character(int code, bool oddField)
    {
        bool doubleBefore = _doubleHeight;
        // Flash is set-after, but steady is set-at: its own cell is already steady.
        bool flashBefore = _flash && code != 0x09;
        bool graphicsBefore = _graphics;
        bool holdBefore = _hold;

        _previousForeground = _foreground;
        _currentGraphics = _nextGraphics;
        _currentSeparated = _nextSeparated;

        if (code < 0x20)
        {
            Control(code);
            if (graphicsBefore && (holdBefore || _hold) && _doubleHeight == doubleBefore)
            {
                code = _held is >= 0x40 and < 0x60 ? 0x20 : _held;
                _currentGraphics = true;
                _currentSeparated = _heldSeparated;
            }
            else
            {
                _held = 0x20;
                code = 0x20;
            }
        }
        else if (_graphics)
        {
            if ((code & 0x20) != 0)
            {
                _held = (byte)code;
                _heldSeparated = _currentSeparated;
            }
        }
        else
        {
            _held = 0x20;
        }

        int half = (_line * 2) + (oddField ? 1 : 0);
        if (doubleBefore)
        {
            half >>= 1;
            if (_bottomRow) { half += 10; }
        }

        if ((flashBefore && (_frames & 0x30) == 0) || (_bottomRow && !_doubleHeight)) { code = 0x20; }

        return _currentGraphics && (code & 0x20) != 0
            ? Mosaic(code, half, _currentSeparated)
            : _rounded[(code * 20) + half];
    }

    // A character's dots on a half-line, 12 half-dots wide: each of the 5 dots becomes two half-dots, with two blank
    // ones on the left.
    private static ushort Dots(ReadOnlySpan<byte> characters, int code, int half)
    {
        if (half is < 0 or >= 20 || code < 0x20) { return 0; }
        int dots = characters[((code - 0x20) * 10) + (half >> 1)];
        int result = 0;
        for (int bit = 0; bit < 5; bit++)
        {
            if ((dots & (1 << bit)) != 0) { result |= 3 << (bit * 2); }
        }

        return (ushort)result;
    }

    // A 2 × 3 block graphic: the top blocks take lines 0-2, the middle 3-6, the bottom 7-9. Separated blocks leave a
    // gap on the right of each and below it.
    private static ushort Mosaic(int code, int half, bool separated)
    {
        int line = half >> 1;
        (int left, int right, bool gap) = line switch
        {
            0 or 1 => (0x01, 0x02, false),
            2 => (0x01, 0x02, true),
            3 or 4 or 5 => (0x04, 0x08, false),
            6 => (0x04, 0x08, true),
            7 or 8 => (0x10, 0x40, false),
            _ => (0x10, 0x40, true)
        };

        if (separated && gap) { return 0; }
        int dots = ((code & left) != 0 ? 0xFC0 : 0) | ((code & right) != 0 ? 0x03F : 0);
        return (ushort)(separated ? dots & 0x3CF : dots);
    }

    private void Control(int code)
    {
        switch (code)
        {
            case >= 0x01 and <= 0x07:
                _graphics = false;
                _foreground = code;
                SetNextType();
                break;
            case 0x08:
                _flash = true;
                break;
            case 0x09:
                _flash = false;
                break;
            case 0x0C:
                _doubleHeight = false;
                break;
            case 0x0D:
                _doubleHeight = true;
                _doubleHeightInRow = true;
                break;
            case >= 0x11 and <= 0x17:
                _graphics = true;
                _foreground = code & 7;
                SetNextType();
                break;
            case 0x18:
                _foreground = _previousForeground = _background;
                break;
            case 0x19:
                _separated = false;
                SetNextType();
                break;
            case 0x1A:
                _separated = true;
                SetNextType();
                break;
            case 0x1C:
                _background = 0;
                break;
            case 0x1D:
                _background = _foreground;
                break;
            case 0x1E:
                _hold = true;
                break;
            case 0x1F:
                _hold = false;
                break;
        }
    }

    private void SetNextType()
    {
        _nextGraphics = _graphics;
        _nextSeparated = _graphics && _separated;
    }

    /// <summary>
    ///  Copies the generator's state, for drawing a frame ahead.
    /// </summary>
    /// <returns>The copy.</returns>
    internal BbcTeletext Clone() => (BbcTeletext)MemberwiseClone();
}
