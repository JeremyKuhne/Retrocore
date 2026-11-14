// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model III's and Model 4's 1500 baud tape signal: playing a tape's bytes as the signal, and turning a recorded
///  signal back into bytes.
/// </summary>
/// <remarks>
///  <para>
///   Each bit is one cycle of a square wave, high then low: a short cycle for a 1 and a long one for a 0, as the
///   ROM's <c>BITOUT</c> writes them, about 380 and 770 T-states a half at 2.03 MHz. A recording opens with a leader of
///   <c>$55</c> bytes and a <c>$7F</c> sync byte, written without start bits; each byte after them has a 0 start bit.
///   A tape image keeps the bytes only, the start bits implied, as the usual high-speed CAS images do; a tape holding
///   more than one recording has each one's leader and sync byte in turn. Playing one
///   ends with one more short cycle, so the reader has an edge after the last bit to time it by.
///  </para>
///  <para>
///   The ROM's reader times the cycles between edges of one kind, which interrupt it, and reads the level to tell a
///   real edge from a glitch.
///  </para>
/// </remarks>
internal sealed class Trs80HighSpeedTape
{
    /// <summary>
    ///  T-states of each half of a 1's cycle.
    /// </summary>
    internal const int OneHalf = 380;

    /// <summary>
    ///  T-states of each half of a 0's cycle.
    /// </summary>
    internal const int ZeroHalf = 768;

    /// <summary>
    ///  The leader's byte.
    /// </summary>
    internal const byte Leader = 0x55;

    /// <summary>
    ///  The sync byte after the leader.
    /// </summary>
    internal const byte Sync = 0x7F;

    // The leader bytes a later recording on the same tape opens with, at the least, to be taken for one rather than
    // for a file's bytes, and at the most, the ROM's 256: leader bytes before those end the file before it.
    private const int LaterLeader = 32;
    private const int LongestLeader = 256;

    // A high half shorter than this is a 1's; much shorter or longer is not a 1500 baud cycle at all.
    private const int Threshold = (OneHalf + ZeroHalf) / 2;
    private const int Shortest = OneHalf / 2;
    private const int Longest = ZeroHalf * 2;

    // Playback: the bytes, the byte and bit (-1 for a start bit) under the head, the half cycle's T-states left, and
    // whether the closing cycle after the last byte has played.
    private IReadOnlyList<byte> _bytes = [];
    private bool[] _unframed = [];
    private int _byte;
    private int _bit;
    private int _left;
    private bool _closed;

    // Recording: each bit heard, and when the signal last rose.
    private readonly List<bool> _bits = [];
    private long _rose = -1;

    /// <summary>
    ///  Gets whether a tape's bytes are a 1500 baud recording: they open with its leader, where a 500 baud one opens
    ///  with zeros.
    /// </summary>
    /// <param name="bytes">The tape's bytes.</param>
    /// <returns>Whether it plays at 1500 baud.</returns>
    internal static bool IsHighSpeed(IReadOnlyList<byte> bytes) => bytes.Count != 0 && bytes[0] == Leader;

    /// <summary>
    ///  Gets the signal's level: true while high.
    /// </summary>
    internal bool Level { get; private set; }

    /// <summary>
    ///  Gets whether the signal has risen since the last <see cref="TakeEdges"/>.
    /// </summary>
    internal bool Rose { get; private set; }

    /// <summary>
    ///  Gets whether the signal has fallen since the last <see cref="TakeEdges"/>.
    /// </summary>
    internal bool Fell { get; private set; }

    /// <summary>
    ///  Gets the bytes played.
    /// </summary>
    internal int Position => _byte;

    /// <summary>
    ///  Gets whether the tape has run out.
    /// </summary>
    internal bool AtEnd => _closed && _left == 0 && !Level;

    /// <summary>
    ///  Starts playing a tape from its beginning.
    /// </summary>
    /// <param name="bytes">The tape's bytes.</param>
    internal void Play(IReadOnlyList<byte> bytes)
    {
        _bytes = bytes;
        _byte = 0;
        _bit = 0;
        _left = 0;
        _closed = false;
        Level = false;
        TakeEdges();
        _unframed = Unframed(bytes);
        _bit = _unframed.Length == 0 || _unframed[0] ? 0 : -1;
    }

    /// <summary>
    ///  Clears the edges seen.
    /// </summary>
    internal void TakeEdges()
    {
        Rose = false;
        Fell = false;
    }

    /// <summary>
    ///  Advances the playing tape one T-state.
    /// </summary>
    internal void Tick()
    {
        if (_left > 0)
        {
            _left--;
            return;
        }

        if (Level)
        {
            Level = false;
            Fell = true;
            _left = _closed ? 0 : HalfOf(CurrentBit()) - 1;
            if (!_closed) { Advance(); }
            return;
        }

        // After the last byte, one more cycle: the reader times a bit from one edge to the next of its kind, so the
        // last bit needs an edge after it, as a real tape's signal gives it when the writer stops.
        if (_byte >= _bytes.Count)
        {
            if (_closed) { return; }
            _closed = true;
            Level = true;
            Rose = true;
            _left = OneHalf - 1;
            return;
        }

        Level = true;
        Rose = true;
        _left = HalfOf(CurrentBit()) - 1;
    }

    /// <summary>
    ///  Notes the recorded signal rising.
    /// </summary>
    /// <param name="time">The T-state.</param>
    internal void RecordRise(long time) => _rose = time;

    /// <summary>
    ///  Notes the recorded signal falling, which ends a bit's high half.
    /// </summary>
    /// <param name="time">The T-state.</param>
    internal void RecordFall(long time)
    {
        if (_rose < 0) { return; }
        long high = time - _rose;
        _rose = -1;
        if (high >= Shortest && high <= Longest) { _bits.Add(high < Threshold); }
    }

    /// <summary>
    ///  Turns the recorded signal into a tape's bytes, and forgets it.
    /// </summary>
    /// <returns>The bytes, or null when the signal holds no 1500 baud leader and sync byte.</returns>
    internal List<byte>? TakeRecording()
    {
        List<bool> bits = [.. _bits];
        _bits.Clear();
        _rose = -1;

        // The sync byte, after at least two of the leader's: the leader's alternating bits fix where bytes start.
        int sync = -1;
        for (int index = 16; index + 8 <= bits.Count && sync < 0; index++)
        {
            if (ByteAt(bits, index) == Sync && ByteAt(bits, index - 8) == Leader && ByteAt(bits, index - 16) == Leader)
            {
                sync = index;
            }
        }

        if (sync < 0) { return null; }
        List<byte> bytes = [.. Enumerable.Repeat(Leader, sync / 8), Sync];
        for (int index = sync + 8; index + 9 <= bits.Count; index += 9)
        {
            bytes.Add(ByteAt(bits, index + 1));
        }

        return bytes;
    }

    // Which bytes are a leader or its sync byte, which have no start bits: the tape's first recording opens with its
    // leader, and each later one, appended by another CSAVE, opens with a run of leader bytes (the last 256 of a longer
    // run, as the ROM writes) and then the sync.
    // A tape whose opening leader has no sync byte after it is played without start bits throughout.
    private static bool[] Unframed(IReadOnlyList<byte> bytes)
    {
        bool[] unframed = new bool[bytes.Count];
        int index = 0;
        while (index < bytes.Count && bytes[index] == Leader) { index++; }
        if (index == bytes.Count || bytes[index] != Sync)
        {
            Array.Fill(unframed, value: true);
            return unframed;
        }

        Array.Fill(unframed, value: true, 0, index + 1);

        int run = 0;
        for (int at = index + 1; at < bytes.Count; at++)
        {
            if (bytes[at] == Leader)
            {
                run++;
                continue;
            }

            if (bytes[at] == Sync && run >= LaterLeader)
            {
                int leader = Math.Min(run, LongestLeader);
                Array.Fill(unframed, value: true, at - leader, leader + 1);
            }

            run = 0;
        }

        return unframed;
    }

    private static int HalfOf(bool one) => one ? OneHalf : ZeroHalf;

    private static byte ByteAt(List<bool> bits, int index)
    {
        int value = 0;
        for (int bit = 0; bit < 8; bit++) { value = (value << 1) | (bits[index + bit] ? 1 : 0); }
        return (byte)value;
    }

    // The bit under the head: a data byte's start bit is 0.
    private bool CurrentBit() => _bit >= 0 && ((_bytes[_byte] >> (7 - _bit)) & 1) != 0;

    // Moves to the next bit once a cycle ends.
    private void Advance()
    {
        if (++_bit < 8) { return; }
        _byte++;
        _bit = _byte < _unframed.Length && _unframed[_byte] ? 0 : -1;
    }
}
