// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II's detachable keyboard: a serial device on the SIO's channel B that sends each key's code and sounds
///  its bell for a <c>$04</c>.
/// </summary>
/// <remarks>
///  <para>
///   Typed codes wait in a queue and go to the SIO one at a time, each a short gap after the program reads the last,
///   so none is lost. The real keyboard sends at 300 baud, about 30 characters a second; the gap here is shorter,
///   as a program cannot tell. A Ctrl+C drops the codes queued ahead of it, and one the SIO holds unread.
///  </para>
/// </remarks>
public sealed class KayproKeyboard
{
    /// <summary>
    ///  The code that sounds the keyboard's bell.
    /// </summary>
    public const byte BellCode = 0x04;

    /// <summary>
    ///  The codes of the cursor keys (up, down, left, right).
    /// </summary>
    public static ReadOnlySpan<byte> CursorKeys => [0xF1, 0xF2, 0xF3, 0xF4];

    private const byte InterruptCode = 0x03;
    private const int Channel = 1;
    private const int GapCycles = 2 * KayproTiming.CyclesPerMillisecond;

    private readonly Queue<byte> _typed = new();
    private readonly Z80Sio _sio;
    private bool _delivered;
    private int _wait;

    /// <summary>
    ///  Creates the keyboard on the SIO.
    /// </summary>
    /// <param name="sio">The SIO, whose channel B the keyboard is on.</param>
    internal KayproKeyboard(Z80Sio sio)
    {
        _sio = sio;
    }

    /// <summary>
    ///  Gets whether codes are still on their way to the program.
    /// </summary>
    public bool IsTyping => _typed.Count != 0 || _sio.ReceiveFull(Channel);

    /// <summary>
    ///  Gets the times the bell has sounded.
    /// </summary>
    public int Bells { get; private set; }

    /// <summary>
    ///  Types a key's code. A Ctrl+C interrupts: it drops the codes still queued, such as the rest of a paste, and
    ///  takes the place of one the SIO holds unread, so it is the next key the program reads.
    /// </summary>
    /// <param name="code">The code, such as ASCII or one of <see cref="CursorKeys"/>.</param>
    public void Type(byte code)
    {
        if (code != InterruptCode)
        {
            _typed.Enqueue(code);
            return;
        }

        _typed.Clear();
        if (_sio.ReceiveFull(Channel)) { _sio.Receive(Channel, code); }
        else { _typed.Enqueue(code); }
    }

    /// <summary>
    ///  Takes a byte the SIO sends the keyboard.
    /// </summary>
    /// <param name="value">The byte: <see cref="BellCode"/> sounds the bell.</param>
    internal void Receive(byte value)
    {
        if (value == BellCode) { Bells++; }
    }

    /// <summary>
    ///  Runs for a T-state: hands the next code to the SIO once the last has been read and the gap has passed.
    /// </summary>
    internal void Tick()
    {
        if (_sio.ReceiveFull(Channel))
        {
            _delivered = true;
            return;
        }

        if (_delivered)
        {
            _delivered = false;
            _wait = GapCycles;
        }

        if (_wait > 0)
        {
            _wait--;
            return;
        }

        if (_typed.TryDequeue(out byte code)) { _sio.Receive(Channel, code); }
    }
}
