// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  Turns tape bits, bytes and tones into an Acorn tape's half-cycles (see <see cref="AcornTape"/>).
/// </summary>
internal sealed class AcornTones
{
    /// <summary>
    ///  The shortest silence, in units: anything shorter is a tone's half-cycle.
    /// </summary>
    internal const int Silence = 3;

    /// <summary>
    ///  Gets the half-cycles so far.
    /// </summary>
    public List<int> HalfCycles { get; } = [];

    /// <summary>
    ///  Gets or sets the baud rate the bits go at, 1200 or 300.
    /// </summary>
    public int Baud { get; set; } = 1200;

    /// <summary>
    ///  Adds a bit: a 1 is two cycles of 2400 Hz and a 0 one of 1200 Hz at 1200 baud, four times as many at 300.
    /// </summary>
    /// <param name="one">The bit.</param>
    public void Bit(bool one)
    {
        int cycles = (Baud == 300 ? 4 : 1) * (one ? 2 : 1);
        for (int cycle = 0; cycle < cycles; cycle++) { Cycle(one); }
    }

    /// <summary>
    ///  Adds a byte as a character: a start bit, 8 data bits from bit 0, and a stop bit.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Byte(byte value)
    {
        Bit(one: false);
        for (int bit = 0; bit < 8; bit++) { Bit((value & (1 << bit)) != 0); }
        Bit(one: true);
    }

    /// <summary>
    ///  Adds bytes as characters in a format: a start bit, the data bits from bit 0, the parity, and the stop bits, or
    ///  for a negative count that many cycles of 2400 Hz.
    /// </summary>
    /// <param name="dataBits">The data bits.</param>
    /// <param name="parity"><c>N</c>, <c>E</c> or <c>O</c>.</param>
    /// <param name="stops">The stop bits, or minus the cycles.</param>
    /// <param name="bytes">The bytes.</param>
    public void Defined(int dataBits, char parity, int stops, ReadOnlySpan<byte> bytes)
    {
        foreach (byte value in bytes)
        {
            Bit(one: false);
            int ones = 0;
            for (int bit = 0; bit < dataBits; bit++)
            {
                bool one = (value & (1 << bit)) != 0;
                Bit(one);
                if (one) { ones++; }
            }

            if (parity is 'E' or 'O') { Bit(((ones & 1) != 0) ^ (parity == 'O')); }
            if (stops >= 0)
            {
                for (int stop = 0; stop < stops; stop++) { Bit(one: true); }
            }
            else
            {
                for (int cycle = 0; cycle < -stops; cycle++) { Cycle(high: true); }
            }
        }
    }

    /// <summary>
    ///  Adds carrier: cycles of 2400 Hz.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Carrier(int cycles)
    {
        for (int cycle = 0; cycle < cycles; cycle++) { Cycle(high: true); }
    }

    /// <summary>
    ///  Adds silence. It runs on from silence before it; one too short to tell from a tone is lengthened to
    ///  <see cref="Silence"/>.
    /// </summary>
    /// <param name="units">Its length in units of 1/4,800 second.</param>
    public void Gap(int units)
    {
        if (units <= 0) { return; }
        if (HalfCycles.Count != 0 && HalfCycles[^1] >= Silence)
        {
            HalfCycles[^1] += units;
            return;
        }

        HalfCycles.Add(Math.Max(units, Silence));
    }

    /// <summary>
    ///  Adds UEF security cycles: a 24-bit count, then whether the first and last are a whole cycle (<c>W</c>) or a
    ///  half (<c>P</c>), then the cycles as bits from bit 0, 1 for 1200 Hz and 0 for 2400 Hz.
    /// </summary>
    /// <param name="data">The chunk's data.</param>
    public void Security(ReadOnlySpan<byte> data)
    {
        int count = data[0] | (data[1] << 8) | (data[2] << 16);
        bool firstHalf = data[3] == (byte)'P';
        bool lastHalf = data[4] == (byte)'P';
        for (int cycle = 0; cycle < count && 5 + (cycle >> 3) < data.Length; cycle++)
        {
            int length = (data[5 + (cycle >> 3)] & (1 << (cycle & 7))) != 0 ? 2 : 1;
            bool first = cycle == 0 && firstHalf;
            bool last = cycle == count - 1 && lastHalf;
            HalfCycles.Add(length);
            if (!first && !last) { HalfCycles.Add(length); }
        }
    }

    private void Cycle(bool high)
    {
        int length = high ? 1 : 2;
        HalfCycles.Add(length);
        HalfCycles.Add(length);
    }
}
