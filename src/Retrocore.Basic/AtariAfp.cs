// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The floating point package's AFP, step for step: its page-zero registers and its reading of a number.
/// </summary>
internal ref struct AtariAfp
{
    private readonly ReadOnlySpan<byte> _text;
    private readonly byte[] _fr0 = new byte[AtariNumbers.Size];
    private byte _frx;
    private byte _eexp;
    private byte _nsign;
    private byte _esign;
    private byte _fchrflg;
    private byte _digrt;

    /// <summary>
    ///  Starts reading a number.
    /// </summary>
    /// <param name="text">The text, ending in an end of line.</param>
    /// <param name="cix">Where to start, CIX.</param>
    internal AtariAfp(ReadOnlySpan<byte> text, int cix)
    {
        _text = text;
        Cix = cix;
    }

    /// <summary>
    ///  Gets CIX: where the next character to read is.
    /// </summary>
    internal int Cix { get; private set; }

    /// <summary>
    ///  Reads the number, as AFP does.
    /// </summary>
    /// <returns>The number, or null when the text holds none or it is too large.</returns>
    internal byte[]? Run()
    {
        SkipSpaces();
        if (!CheckNumber()) { return null; }
        _eexp = _nsign = _esign = _fchrflg = 0;
        _digrt = 0xFF;
        Array.Clear(_fr0);
        bool first = true;
        while (true)
        {
            if (!first) { _fchrflg = 0xFF; }
            first = false;
            (bool digit, byte value) = ReadCharacter();
            if (digit)
            {
                if (_fr0[1] != 0)
                {
                    if ((_digrt & 0x80) != 0) { _eexp++; }
                    continue;
                }

                ShiftDigit();
                _fr0[5] |= value;
                if ((_digrt & 0x80) == 0) { _digrt++; }
                continue;
            }

            if (value == '.')
            {
                if ((_digrt & 0x80) == 0) { break; }
                _digrt = 0;
                continue;
            }

            if (value == 'E')
            {
                Exponent();
                break;
            }

            if (_fchrflg != 0) { break; }
            if (value == '-') { _nsign = value; }
        }

        return End();
    }

    private void Exponent()
    {
        byte frx = (byte)Cix;
        (bool digit, byte value) = ReadCharacter();
        if (!digit)
        {
            if (value is (byte)'+' or (byte)'-')
            {
                if (value == '-') { _esign = value; }
                (digit, value) = ReadCharacter();
            }

            if (!digit)
            {
                Cix = frx;
                return;
            }
        }

        byte dropped = _eexp;
        _eexp = value;
        (bool second, byte next) = ReadCharacter();
        if (second)
        {
            _eexp = (byte)((_eexp * 10) + next);
            Cix++;
        }

        if (_esign != 0) { _eexp = (byte)-_eexp; }
        _eexp = (byte)(dropped + _eexp);

        // An exponent that comes to zero leaves CIX on the E.
        if (_eexp == 0) { Cix = frx; }
    }

    private byte[]? End()
    {
        Cix--;
        byte power = _eexp;
        if ((_digrt & 0x80) == 0 && _digrt != 0) { power = (byte)(power - _digrt); }
        bool odd = (power & 1) != 0;
        _eexp = (byte)((power >> 1) | (power & 0x80));
        if (odd) { ShiftDigit(); }
        _fr0[0] = (byte)(_eexp + AtariNumbers.Bias + 4);
        if (!Normalize()) { return null; }
        if (_nsign != 0) { _fr0[0] |= AtariNumbers.Sign; }
        return _fr0;
    }

    // FP_NORMALIZE: shifts out leading zero bytes, and checks the range.
    private readonly bool Normalize()
    {
        if (_fr0[0] == 0) { return true; }
        for (int shift = 0; shift < 4 && _fr0[1] == 0; shift++)
        {
            for (int index = 1; index < AtariNumbers.Size - 1; index++) { _fr0[index] = _fr0[index + 1]; }
            _fr0[AtariNumbers.Size - 1] = 0;
            _fr0[0]--;
        }

        if (_fr0[1] == 0)
        {
            _fr0[0] = 0;
            return true;
        }

        int bare = _fr0[0] & 0x7F;
        if (bare >= AtariNumbers.TooLarge) { return false; }
        if (bare < AtariNumbers.Smallest) { Array.Clear(_fr0); }
        return true;
    }

    // FP_SHIFT_FR0_DIGIT: the mantissa a digit left, its top digit into FRX.
    private void ShiftDigit()
    {
        _frx = (byte)((_frx << 4) | (_fr0[1] >> 4));
        for (int index = 1; index < AtariNumbers.Size - 1; index++)
        {
            _fr0[index] = (byte)((_fr0[index] << 4) | (_fr0[index + 1] >> 4));
        }

        _fr0[AtariNumbers.Size - 1] = (byte)(_fr0[AtariNumbers.Size - 1] << 4);
    }

    // FP_READ_CHARACTER: a digit's value, or the character; either way CIX moves past it.
    private (bool Digit, byte Value) ReadCharacter()
    {
        byte character = At(Cix);
        Cix++;
        return character is >= (byte)'0' and <= (byte)'9' ? (true, (byte)(character - '0')) : (false, character);
    }

    private void SkipSpaces()
    {
        while (At(Cix) == ' ') { Cix++; }
    }

    // FP_CHECK_NUMBER: a digit, a point and a digit, or a sign and either; CIX goes back only when it is one.
    private bool CheckNumber()
    {
        int saved = Cix;
        (bool digit, byte value) = ReadCharacter();
        if (!digit)
        {
            if (value is (byte)'+' or (byte)'-')
            {
                (digit, value) = ReadCharacter();
                if (!digit && value != '.') { return false; }
            }

            if (!digit)
            {
                if (value != '.') { return false; }
                (digit, _) = ReadCharacter();
                if (!digit) { return false; }
            }
        }

        Cix = saved;
        return true;
    }

    private readonly byte At(int index) => index < _text.Length ? _text[index] : AtariNumbers.EndOfLine;
}
