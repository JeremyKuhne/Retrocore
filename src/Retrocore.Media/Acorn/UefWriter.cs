// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Acorn;

/// <summary>
///  Writes an Acorn tape's tones as UEF chunks, merging neighbours of a kind: characters as <c>&amp;0100</c>,
///  carrier as <c>&amp;0110</c>, other bits as <c>&amp;0102</c>, a lone half-cycle as <c>&amp;0114</c>, and
///  silence as <c>&amp;0112</c> or <c>&amp;0116</c>.
/// </summary>
internal sealed class UefWriter
{
    private readonly MemoryStream _file = new();
    private readonly List<byte> _bytes = [];
    private readonly List<bool> _bits = [];
    private int _carrier;
    private int _gap;
    private int _baud = 1200;
    private int _bytesBaud = 1200;

    /// <summary>
    ///  Starts a file: the header, version 0.10.
    /// </summary>
    public UefWriter()
    {
        _file.Write("UEF File!\0"u8);
        _file.Write([10, 0]);
    }

    /// <summary>
    ///  Adds silence.
    /// </summary>
    /// <param name="units">Its length in units of 1/4,800 second.</param>
    public void Gap(int units)
    {
        FlushTones();
        _gap += units;
    }

    /// <summary>
    ///  Adds a half-cycle that is not half of a whole cycle.
    /// </summary>
    /// <param name="high">Whether it is a 2400 Hz half-cycle rather than a 1200 Hz one.</param>
    public void LoneHalf(bool high)
    {
        FlushAll();

        // One wave, its first and last a half: a single half-cycle.
        Chunk(0x0114, [1, 0, 0, (byte)'P', (byte)'P', (byte)(high ? 0 : 1)]);
    }

    /// <summary>
    ///  Adds whole cycles: characters at either rate, carrier, and explicit bits for the rest.
    /// </summary>
    /// <param name="cycles">The cycles, true for 2400 Hz and false for 1200 Hz.</param>
    public void Cycles(List<bool> cycles)
    {
        FlushGap();
        int index = 0;
        while (index < cycles.Count)
        {
            // Either rate's reading gives the same cycles back; the rate of the bytes before reads better.
            int first = _bytesBaud == 300 ? 4 : 1;
            if (TryByte(cycles, index, first, out byte value, out int used)
                || TryByte(cycles, index, 5 - first, out value, out used))
            {
                int baud = used > 40 ? 300 : 1200;
                if (_bytes.Count != 0 && baud != _bytesBaud) { FlushBytes(); }
                FlushCarrier();
                FlushBits();
                _bytesBaud = baud;
                _bytes.Add(value);
                index += used;
            }
            else if (cycles[index])
            {
                FlushBytes();
                FlushBits();
                _carrier++;
                index++;
            }
            else
            {
                FlushBytes();
                FlushCarrier();
                _bits.Add(item: false);
                index++;
            }
        }
    }

    /// <summary>
    ///  Ends the file.
    /// </summary>
    /// <returns>The file's bytes.</returns>
    public byte[] Finish()
    {
        FlushAll();
        return _file.ToArray();
    }

    // A character at a rate: a start bit, 8 data bits from bit 0 and a stop bit, where a bit at 1200 baud is one
    // 1200 Hz cycle (0) or two 2400 Hz ones (1), and at 300 baud four times as many.
    private static bool TryByte(List<bool> cycles, int index, int scale, out byte value, out int used)
    {
        value = 0;
        used = 0;
        int position = index;
        for (int bit = 0; bit < 10; bit++)
        {
            if (position >= cycles.Count) { return false; }
            bool one = cycles[position];
            if ((bit == 0 && one) || (bit == 9 && !one)) { return false; }
            int length = scale * (one ? 2 : 1);
            for (int cycle = 0; cycle < length; cycle++)
            {
                if (position + cycle >= cycles.Count || cycles[position + cycle] != one) { return false; }
            }

            if (bit is > 0 and < 9 && one) { value |= (byte)(1 << (bit - 1)); }
            position += length;
        }

        used = position - index;
        return true;
    }

    private void FlushAll()
    {
        FlushTones();
        FlushGap();
    }

    private void FlushTones()
    {
        FlushBytes();
        FlushCarrier();
        FlushBits();
    }

    private void FlushBytes()
    {
        if (_bytes.Count == 0) { return; }
        SetBaud(_bytesBaud);
        Chunk(0x0100, [.. _bytes]);
        _bytes.Clear();
    }

    private void FlushCarrier()
    {
        while (_carrier > 0)
        {
            int count = Math.Min(_carrier, ushort.MaxValue);
            Chunk(0x0110, [(byte)count, (byte)(count >> 8)]);
            _carrier -= count;
        }
    }

    // Explicit bits are 1200 baud bits: the first byte counts the unused bits in the last.
    private void FlushBits()
    {
        if (_bits.Count == 0) { return; }
        SetBaud(1200);
        int bytes = (_bits.Count + 7) / 8;
        byte[] data = new byte[1 + bytes];
        data[0] = (byte)((bytes * 8) - _bits.Count);
        for (int bit = 0; bit < _bits.Count; bit++)
        {
            if (_bits[bit]) { data[1 + (bit >> 3)] |= (byte)(1 << (bit & 7)); }
        }

        Chunk(0x0102, data);
        _bits.Clear();
    }

    private void FlushGap()
    {
        if (_gap == 0) { return; }
        if (_gap % 2 == 0 && _gap / 2 <= ushort.MaxValue)
        {
            Chunk(0x0112, [(byte)(_gap / 2), (byte)(_gap / 2 >> 8)]);
        }
        else
        {
            byte[] seconds = new byte[4];
            BinaryPrimitives.WriteSingleLittleEndian(seconds, (float)_gap / AcornTape.UnitsPerSecond);
            Chunk(0x0116, seconds);
        }

        _gap = 0;
    }

    private void SetBaud(int baud)
    {
        if (baud == _baud) { return; }
        _baud = baud;
        Chunk(0x0117, [(byte)baud, (byte)(baud >> 8)]);
    }

    private void Chunk(int id, ReadOnlySpan<byte> data)
    {
        Span<byte> header = stackalloc byte[6];
        BinaryPrimitives.WriteUInt16LittleEndian(header, (ushort)id);
        BinaryPrimitives.WriteInt32LittleEndian(header[2..], data.Length);
        _file.Write(header);
        _file.Write(data);
    }
}
