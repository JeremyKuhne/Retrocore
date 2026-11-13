// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model II family's keyboard, as the main board sees it: the keyboard's own processor sends each key's code,
///  which the board latches for port <c>$FC</c>, raising the keyboard interrupt until the program reads it.
/// </summary>
/// <remarks>
///  <para>
///   Keys send ASCII, with CTRL giving <c>$01</c>-<c>$1A</c>. The other keys are BREAK <c>$03</c>, BACKSPACE
///   <c>$08</c>, TAB <c>$09</c>, ENTER <c>$0D</c>, ESC <c>$1B</c>, the arrows <c>$1C</c>-<c>$1F</c> (left, right,
///   up, down), HOLD <c>$00</c>, and F1 and F2 <c>$01</c> and <c>$02</c>. The keyboard sends a key after the program
///   has taken the one before and about 10 ms have passed.
///  </para>
/// </remarks>
public sealed class Trs80Model2Keyboard
{
    private const int GapCycles = 10 * Trs80Model2Timing.CyclesPerMillisecond;

    private readonly Queue<byte> _typed = new();
    private int _wait;

    /// <summary>
    ///  Gets the latched code.
    /// </summary>
    public byte Data { get; private set; }

    /// <summary>
    ///  Gets whether a code waits in the latch, which requests the keyboard interrupt.
    /// </summary>
    public bool Ready { get; private set; }

    /// <summary>
    ///  Gets whether typed codes are still waiting to be sent.
    /// </summary>
    public bool IsTyping => Ready || _typed.Count != 0;

    /// <summary>
    ///  Queues a key's code.
    /// </summary>
    /// <param name="code">The code.</param>
    public void Type(byte code) => _typed.Enqueue(code);

    /// <summary>
    ///  Reads the latch, which clears the keyboard interrupt.
    /// </summary>
    /// <returns>The code.</returns>
    internal byte Read()
    {
        if (Ready)
        {
            Ready = false;
            _wait = GapCycles;
        }

        return Data;
    }

    /// <summary>
    ///  Advances one T-state, sending the next code when the latch is free.
    /// </summary>
    internal void Tick()
    {
        if (_wait > 0)
        {
            _wait--;
            return;
        }

        if (Ready || !_typed.TryDequeue(out byte code)) { return; }
        Data = code;
        Ready = true;
    }
}
