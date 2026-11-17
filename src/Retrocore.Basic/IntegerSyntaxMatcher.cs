// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  One run of Integer BASIC's tokenizer over a line: page zero, the input buffer and the 6502's registers, as the
///  ROM's routine uses them.
/// </summary>
internal sealed class IntegerSyntaxMatcher
{
    // The page-zero locations the tokenizer uses (Equates.asm).
    private const int SynStkH = 0x58;
    private const int SynStkL = 0x80;
    private const int TxtNdxStk = 0xA8;
    private const int TxtNdx = 0xC8;
    private const int LeadBl = 0xC9;
    private const int TokNdxStk = 0xD1;
    private const int TokNdx = 0xF1;
    private const int PCon = 0xF2;
    private const int Char = 0xF9;
    private const int SynStkDx = 0xFD;
    private const int SynPag = 0xFE;

    private const int TableStart = 0xEC00;
    private const int TableEnd = 0xEE00;

    private const byte EndMark = 0xDF;
    private const byte Quote = 0xA2;
    private const byte Blank = 0xA0;

    private readonly IntegerSyntaxTables _tables;
    private readonly byte[] _zeroPage = new byte[0x100];
    private readonly byte[] _input = new byte[0x100];
    private readonly bool[] _literal = new bool[0x100];
    private readonly int[] _source = new int[0x100];
    private readonly Stack<byte> _stack = new();
    private readonly int _length;
    private int _furthest;

    /// <summary>
    ///  Puts a line in the input buffer as GETCMD does.
    /// </summary>
    /// <param name="text">The line's units.</param>
    /// <param name="tables">The BASIC's syntax tables.</param>
    internal IntegerSyntaxMatcher(ReadOnlySpan<int> text, IntegerSyntaxTables tables)
    {
        _tables = tables;
        // GETCMD: the line from index 0, its end marked by an underline where the return was.
        _length = text.Length;
        for (int index = 0; index < text.Length; index++)
        {
            int unit = text[index];
            // A typed character has bit 7 set, a control character too; an escaped byte is stored as it is.
            int value = unit & 0xFF;
            _input[index] = (unit & BasicText.Raw) != 0 && value >= 0x20 ? (byte)value : (byte)(value | 0x80);
        }

        _input[text.Length] = EndMark;
        MarkLiterals();
    }

    /// <summary>
    ///  Tokenizes the line.
    /// </summary>
    /// <returns>The tokens, or the error.</returns>
    internal IntegerSyntaxResult Run()
    {
        // CMDLINE: TOKNDX at the end of the text, TXTNDX before its first character, an empty syntax stack, and the
        // rule at $EDFF, a whole line.
        _zeroPage[TokNdx] = (byte)_length;
        _zeroPage[TxtNdx] = 0xFF;
        _zeroPage[SynPag] = 0;
        IntegerSyntaxError? error = Match();
        if (error is { } failed) { return new([], [], failed, Column: Math.Min(_furthest, _length)); }

        int first = _zeroPage[TxtNdx] + 1;
        int last = _zeroPage[TokNdx];
        byte[] tokens = _input[first..(last + 1)];
        int[] sources = _source[first..(last + 1)];
        return new(tokens, sources, Error: null, Column: 0);
    }

#pragma warning disable TOUKI0027 // The labels are the ROM's, so the port reads beside its source.
    // The tokenizer, from STARTRULE with A = $FF and X = $20, to the end of the line (null) or an error.
    private IntegerSyntaxError? Match()
    {
        int a = 0xFF;
        int x = 0x20;
        int y = 0;
        bool carry = false;
        bool zero = false;

    STARTRULE:
        carry = (a & 0x80) != 0;
        a = (a << 1) & 0xFF;
        y = a;
        a = (0xEC >> 1 << 1) | (carry ? 1 : 0);
        carry = false;
        _zeroPage[SynPag + 1] = (byte)a;
        zero = a == 0;

    REPEATITEM:
        if (!zero) { goto REPEATITEM_1; }
        y = (y + 1) & 0xFF;

    REPEATITEM_1:
        y = (y + 1) & 0xFF;

    MATCHITEM:
        _zeroPage[SynStkDx] = (byte)x;
        a = Table(y);
        if ((a & 0x80) != 0) { goto CHARITEM; }
        if (a != 0) { goto MATCHITEM_1; }
        return IntegerSyntaxError.Syntax;

    MATCHITEM_1:
        if (a >= 0x03)
        {
            carry = true;
            zero = a == 0x03;
            goto RULEITEM;
        }

        carry = (a & 1) != 0;
        a >>= 1;
        x = (_zeroPage[TxtNdx] + 1) & 0xFF;

    // COPYCHAR
        a = _input[x];
        Reach(x);
        if (!carry) { goto COPYCHAR_1; }
        if (a == Quote) { goto NEXTITEM; }

    COPYCHAR_1:
        if (a == EndMark) { goto NEXTITEM; }
        carry = a >= EndMark;
        _zeroPage[TxtNdx] = (byte)x;

    PUTTOKNEXT:
        if (WriteToken(a, out x) is { } tooLong) { return tooLong; }
        y = (y + 1) & 0xFF;

    NEXTITEM:
        y = (y - 1) & 0xFF;
        x = _zeroPage[SynStkDx];

    NEXTITEMX:
        a = Table(y);
        y = (y - 1) & 0xFF;
        carry = (a & 0x80) != 0;
        a = (a << 1) & 0xFF;
        if ((a & 0x80) == 0) { goto MATCHITEM; }

    RULEMATCHED:
        y = _zeroPage[SynStkH + x];
        _zeroPage[SynPag + 1] = (byte)y;
        y = _zeroPage[SynStkL + x];
        x = (x + 1) & 0xFF;
        a = Table(y) & 0b1001_1111;
        if (a != 0) { goto NEXTITEMX; }

        // A numeric constant: its digits become its value, after the first digit.
        _zeroPage[PCon] = 0;
        _zeroPage[PCon + 1] = 0;
        _stack.Push((byte)y);
        _zeroPage[SynStkDx] = (byte)x;
        y = _zeroPage[(TokNdxStk - 1 + x) & 0xFF];
        _zeroPage[LeadBl] = (byte)y;
        carry = false;
        do
        {
            _zeroPage[Char] = 0x0A;
            x = 0;
            y = (y + 1) & 0xFF;
            a = _input[y] & 0x0F;
            do
            {
                int sum = a + _zeroPage[PCon] + (carry ? 1 : 0);
                carry = sum > 0xFF;
                _stack.Push((byte)sum);
                sum = x + _zeroPage[PCon + 1] + (carry ? 1 : 0);
                carry = sum > 0xFF;
                a = sum & 0xFF;
                if ((a & 0x80) != 0) { return IntegerSyntaxError.TooLarge; }
                x = a;
                a = _stack.Pop();
                _zeroPage[Char]--;
            }
            while (_zeroPage[Char] != 0);

            _zeroPage[PCon] = (byte)a;
            _zeroPage[PCon + 1] = (byte)x;
            carry = y >= _zeroPage[TokNdx];
        }
        while (y != _zeroPage[TokNdx]);

        y = (_zeroPage[LeadBl] + 1) & 0xFF;
        _zeroPage[TokNdx] = (byte)y;
        if (WriteToken(a, out x) is { } tooLongLow) { return tooLongLow; }
        y = _stack.Pop();
        a = _zeroPage[PCon + 1];
        goto PUTTOKNEXT;

    CHARITEM:
        x = _zeroPage[TxtNdx];

    NEXTKEYCHAR:
        a = Blank;

    CHARITEM_1:
        x = (x + 1) & 0xFF;
        Reach(x);
        if (a >= Folded(x)) { goto CHARITEM_1; }
        a = Table(y) & 0x3F;
        carry = (a & 1) != 0;
        a >>= 1;
        if (a != 0) { goto MATCHCHAR; }
        a = Folded(x);
        if (carry) { goto CHARITEM_2; }
        a += 0x3F;
        carry = a > 0xFF;
        a &= 0xFF;
        carry = a >= 0x1A;
        if (!carry) { goto LE4B1Letter; }

    CHARITEM_2:
        a += 0x4F + (carry ? 1 : 0);
        carry = a > 0xFF;
        a &= 0xFF;
        carry = a >= 0x0A;
        if (!carry) { goto LE4B1Letter; }

    ITEMFAILED:
        x = _zeroPage[SynStkDx];
        while (true)
        {
            y = (y + 1) & 0xFF;
            a = Table(y) & 0xE0;
            if (a == 0x20) { goto RULEMATCHED; }
            _zeroPage[TxtNdx] = _zeroPage[(TxtNdxStk + x) & 0xFF];
            _zeroPage[TokNdx] = _zeroPage[(TokNdxStk + x) & 0xFF];
            do
            {
                y = (y - 1) & 0xFF;
                a = Table(y);
                carry = (a & 0x80) != 0;
                a = (a << 1) & 0xFF;
            }
            while ((a & 0x80) == 0);

            y = (y - 1) & 0xFF;
            if (carry) { goto MATCHITEM; }
            carry = (a & 0x80) != 0;
            a = (a << 1) & 0xFF;
            if ((a & 0x80) != 0) { goto MATCHITEM; }
            y = _zeroPage[SynStkH + x];
            _zeroPage[SynPag + 1] = (byte)y;
            y = _zeroPage[SynStkL + x];
            x = (x + 1) & 0xFF;
            if ((x & 0x80) != 0) { return IntegerSyntaxError.Syntax; }
        }

    RULEITEM:
        if (zero) { return null; }
        if (a >= 0x7E)
        {
            zero = a == 0x7E;
            goto REPEATITEM;
        }

        x = (x - 1) & 0xFF;
        if ((x & 0x80) != 0) { return IntegerSyntaxError.TooLong; }

        _zeroPage[SynStkL + x] = (byte)y;
        _zeroPage[SynStkH + x] = _zeroPage[SynPag + 1];
        _zeroPage[TxtNdxStk + x] = _zeroPage[TxtNdx];
        _zeroPage[(TokNdxStk + x) & 0xFF] = _zeroPage[TokNdx];
        y = a & 0x1F;
        a = _tables.Index[y];
        goto STARTRULE;

    LE4B1Letter:
        // A letter or digit matched by a class item: copied as a capital, with the carry clear.
        a = Folded(x);
        carry = false;
        goto COPYCHAR_1;

    MATCHCHAR:
        a = (a << 1) | (carry ? 1 : 0);
        a += 0xA0;
        carry = a > 0xFF;
        a &= 0xFF;
        if (a != Folded(x)) { goto ITEMFAILED; }
        if ((Table(y) & 0x40) != 0) { goto GOTKEYWORD; }
        y = (y - 1) & 0xFF;
        if ((Table(y) & 0x80) != 0) { goto NEXTKEYCHAR; }
        y = (y + 1) & 0xFF;

    GOTKEYWORD:
        // A keyword matched: its token is the count of keywords from here to the top of the page, plus the page's
        // first byte.
        _zeroPage[TxtNdx] = (byte)x;
        _stack.Push((byte)y);
        a = Table(0, page: true);
        x = a;
        do
        {
            a >>= 1;
            a ^= 0x40;
            a |= Table(y);
            if (a >= 0xC0) { x = (x + 1) & 0xFF; }
            y = (y + 1) & 0xFF;
        }
        while (y != 0);

        y = _stack.Pop();
        a = x;

        // KEYMATCHED: a reserved word ($85 and up) ends a name instead, in Integer BASIC.
        if (_tables.ReservedWords && a >= 0x85)
        {
            y = 0x02;
            goto ITEMFAILED;
        }

        goto PUTTOKNEXT;
    }

#pragma warning restore TOUKI0027

    // Writes a token (PUTTOKEN), recording the character it came from; fails with TOO LONG when the buffer is full.
    private IntegerSyntaxError? WriteToken(int value, out int index)
    {
        _zeroPage[TokNdx]++;
        index = _zeroPage[TokNdx];
        if (index == 0) { return IntegerSyntaxError.TooLong; }
        _input[index] = (byte)value;
        _source[index] = Math.Min(_zeroPage[TxtNdx], _length);
        return null;
    }

    // A byte of the syntax table at (SYNPAG),Y, or the page's first byte.
    private byte Table(int y, bool page = false)
    {
        int address = (_zeroPage[SynPag + 1] << 8) | _zeroPage[SynPag];
        address = page ? address : address + y;
        if (address is >= TableStart and < TableEnd) { return _tables.Table[address - TableStart]; }
        int index = _tables.IndexStart;
        return address >= index && address < index + 32 ? _tables.Index[address - index] : (byte)0;
    }

    // A character of the line as the matcher compares it: letters outside strings and remarks as capitals.
    private int Folded(int x)
    {
        byte value = _input[x];
        return value is >= 0xE1 and <= 0xFA && !_literal[x] ? value & 0xDF : value;
    }

    // Notes how far into the line the matcher has looked, which is where a refused line is wrong.
    private void Reach(int x)
    {
        if (x < _length && x > _furthest) { _furthest = x; }
    }

    // Marks the characters inside double quotes, which keep their case.
    private void MarkLiterals()
    {
        bool quoted = false;
        for (int index = 0; index < _length; index++)
        {
            if (_input[index] == Quote) { quoted = !quoted; }
            else { _literal[index] = quoted; }
        }
    }
}
