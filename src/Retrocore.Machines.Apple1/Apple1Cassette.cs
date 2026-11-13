// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The Apple Cassette Interface's hardware: a flip-flop that drives the tape output and the PROM that reads the
///  tape input.
/// </summary>
/// <remarks>
///  <para>
///   Any access to <c>$C000</c>-<c>$C0FF</c> flips the output. A read there returns the PROM's byte with address
///   bit 0 taken from the tape input, so <c>$C081</c> reads <c>$A9</c> or <c>$AA</c> as the input is low or high.
///   <c>$C100</c>-<c>$C1FF</c> reads the PROM itself.
///  </para>
///  <para>
///   The interface has no motor control: a tape plays from the moment it is loaded, as if PLAY were pressed, and
///   records each change of the output once it is loaded to record.
///  </para>
/// </remarks>
public sealed class Apple1Cassette
{
    private readonly byte[] _rom;
    private Apple1Tape? _tape;
    private long _cycle;
    private long _lastChange;
    private int _position;
    private long _nextChange;

    /// <summary>
    ///  Creates the interface.
    /// </summary>
    /// <param name="rom">The 256-byte PROM.</param>
    internal Apple1Cassette(ReadOnlyMemory<byte> rom) => _rom = rom.ToArray();

    /// <summary>
    ///  Gets the level the interface drives on the tape output.
    /// </summary>
    public bool Output { get; private set; }

    /// <summary>
    ///  Gets the level of the tape input.
    /// </summary>
    public bool Input { get; private set; }

    /// <summary>
    ///  Gets what the deck is doing.
    /// </summary>
    public TapeMode Mode { get; private set; }

    /// <summary>
    ///  Gets the half cycles played or recorded.
    /// </summary>
    public int Position => Mode == TapeMode.Recording ? _tape?.HalfCycles.Count ?? 0 : _position;

    /// <summary>
    ///  Gets the half cycles on the tape.
    /// </summary>
    public int Length => _tape?.HalfCycles.Count ?? 0;

    /// <summary>
    ///  Gets whether the tape has played to its end.
    /// </summary>
    public bool AtEnd => Mode == TapeMode.Playing && _position >= Length;

    /// <summary>
    ///  Starts playing a tape from its beginning.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Play(Apple1Tape tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        _tape = tape;
        Mode = TapeMode.Playing;
        _position = 0;
        Input = false;
        _nextChange = tape.HalfCycles.Count > 0 ? _cycle + tape.HalfCycles[0] : long.MaxValue;
    }

    /// <summary>
    ///  Starts recording onto a tape, after what it holds.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Record(Apple1Tape tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        _tape = tape;
        Mode = TapeMode.Recording;
        _lastChange = _cycle;
    }

    /// <summary>
    ///  Stops the deck.
    /// </summary>
    public void Stop()
    {
        _tape = null;
        Mode = TapeMode.Stopped;
        Input = false;
    }

    /// <summary>
    ///  Reads <c>$C000</c>-<c>$C1FF</c> for the CPU.
    /// </summary>
    /// <param name="offset">The offset from <c>$C000</c>.</param>
    /// <returns>The byte.</returns>
    internal byte Read(int offset)
    {
        if (offset >= 0x100) { return _rom[offset & 0xFF]; }
        byte value = Peek(offset);
        Flip();
        return value;
    }

    /// <summary>
    ///  Writes <c>$C000</c>-<c>$C1FF</c> for the CPU: <c>$C000</c>-<c>$C0FF</c> flips the output.
    /// </summary>
    /// <param name="offset">The offset from <c>$C000</c>.</param>
    internal void Write(int offset)
    {
        if (offset < 0x100) { Flip(); }
    }

    /// <summary>
    ///  Reads <c>$C000</c>-<c>$C1FF</c> without flipping the output.
    /// </summary>
    /// <param name="offset">The offset from <c>$C000</c>.</param>
    /// <returns>The byte a read would return.</returns>
    internal byte Peek(int offset) =>
        offset >= 0x100 ? _rom[offset & 0xFF] : _rom[(offset & 0xFE) | (Input ? 1 : 0)];

    /// <summary>
    ///  Advances one cycle, playing the tape.
    /// </summary>
    internal void Tick()
    {
        _cycle++;
        if (Mode != TapeMode.Playing || _tape is null || _cycle < _nextChange) { return; }
        Input = !Input;
        _position++;
        _nextChange = _position < Length ? _nextChange + _tape.HalfCycles[_position] : long.MaxValue;
    }

    private void Flip()
    {
        Output = !Output;
        if (Mode != TapeMode.Recording || _tape is null) { return; }
        _tape.Add((int)Math.Min(int.MaxValue, _cycle - _lastChange));
        _lastChange = _cycle;
    }
}
