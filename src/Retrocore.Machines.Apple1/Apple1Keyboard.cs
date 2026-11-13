// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The Apple-1's ASCII keyboard on the PIA's port A: seven data lines, with PA7 held high, and a strobe on CA1.
/// </summary>
/// <remarks>
///  <para>
///   Typed characters wait in a queue. Each is put on port A and strobed once the program has read the one
///   before (control register A's bit 7 is clear) and a millisecond has passed, so a program that polls the
///   keyboard sees every key.
///  </para>
/// </remarks>
public sealed class Apple1Keyboard
{
    // Cycles between one key being read and the next being strobed.
    private const int GapCycles = Apple1Timing.CyclesPerMillisecond;

    // Cycles the strobe is held high.
    private const int StrobeCycles = 4;

    private readonly Queue<byte> _keys = new();
    private readonly Pia6821 _pia;
    private int _gap;
    private int _strobe;

    /// <summary>
    ///  Creates the keyboard on the PIA's port A.
    /// </summary>
    /// <param name="pia">The PIA.</param>
    internal Apple1Keyboard(Pia6821 pia) => _pia = pia;

    /// <summary>
    ///  Gets the number of typed characters not yet strobed.
    /// </summary>
    public int Pending => _keys.Count;

    /// <summary>
    ///  Types a character. The keyboard has no lowercase, so a lowercase letter types its uppercase.
    /// </summary>
    /// <param name="ascii">The ASCII code; bit 7 is ignored.</param>
    public void Type(byte ascii)
    {
        ascii &= 0x7F;
        if (ascii is >= (byte)'a' and <= (byte)'z') { ascii -= 0x20; }
        _keys.Enqueue(ascii);
    }

    /// <summary>
    ///  Types each character of a string.
    /// </summary>
    /// <param name="text">The text; a newline types Return.</param>
    public void Type(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        foreach (char character in text)
        {
            if (character == '\r') { continue; }
            Type(character == '\n' ? (byte)0x0D : (byte)character);
        }
    }

    /// <summary>
    ///  Drops the characters not yet strobed.
    /// </summary>
    public void Clear() => _keys.Clear();

    /// <summary>
    ///  Advances one cycle: ends a strobe, and strobes the next key once the last has been read.
    /// </summary>
    internal void Tick()
    {
        if (_strobe > 0)
        {
            if (--_strobe == 0) { _pia.SetCA1(false); }
            return;
        }

        if (_keys.Count == 0 || (_pia.ControlA & 0x80) != 0)
        {
            _gap = 0;
            return;
        }

        if (++_gap < GapCycles) { return; }
        _gap = 0;
        _pia.InputA = (byte)(_keys.Dequeue() | 0x80);
        _pia.SetCA1(true);
        _strobe = StrobeCycles;
    }
}
