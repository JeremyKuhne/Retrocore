// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Circular bitstream, quarter-track head and deterministic MC3470 weak-bit window.
/// </summary>
internal sealed class DiskIIDrive
{
    private ulong _fraction;
    private uint _random = 0x6502D15C;
    private int _headWindow;
    private bool _writeFlux;
    private bool _writing;

    /// <summary>
    ///  Gets caller-owned media.
    /// </summary>
    internal WozDisk? Media { get; private set; }

    /// <summary>
    ///  Changes media while retaining its angular position across differing track lengths.
    /// </summary>
    /// <param name="media">The new disk, or null for eject.</param>
    internal void SetMedia(WozDisk? media)
    {
        int oldLength = BitCount;
        Media = media;
        BitPosition = (int)((long)BitPosition * BitCount / oldLength);
        _headWindow = 0;
        _writeFlux = false;
        _writing = false;
    }

    /// <summary>
    ///  Gets the radial position.
    /// </summary>
    internal int QuarterTrack { get; private set; }

    /// <summary>
    ///  Gets the current angular bit position.
    /// </summary>
    internal int BitPosition { get; private set; }

    /// <summary>
    ///  Gets or sets the rotor's eight magnetic positions.
    /// </summary>
    internal int Rotor { get; set; }

    /// <summary>
    ///  Gets the current track length; empty space has a stable angular reference.
    /// </summary>
    internal int BitCount => Media?.Track(QuarterTrack)?.BitCount ?? 51024;

    /// <summary>
    ///  Moves the head while retaining angular alignment across unequal track lengths.
    /// </summary>
    /// <param name="delta">Quarter-track motion.</param>
    internal void Step(int delta)
    {
        int oldLength = BitCount;
        QuarterTrack = Math.Clamp(QuarterTrack + delta, 0, 159);
        BitPosition = (int)((long)BitPosition * BitCount / oldLength);
    }

    /// <summary>
    ///  Advances one half CPU clock and returns a delayed read pulse at a bit-cell boundary.
    /// </summary>
    /// <param name="writing">Whether the controller is writing.</param>
    /// <param name="transition">A write-head level transition during this half clock.</param>
    /// <returns>A MC3470 read pulse.</returns>
    internal bool Tick(bool writing, bool transition)
    {
        _writeFlux |= writing && transition;
        _writing |= writing;
        ulong interval = (ulong)(Media?.OptimalBitTiming ?? 32) * 125 * 2_041_000;
        _fraction += 1_000_000_000;
        bool pulse = false;
        while (_fraction >= interval)
        {
            _fraction -= interval;
            DiskTrack? track = Media?.Track(QuarterTrack);
            bool raw = track?.ReadBit(BitPosition) ?? false;
            if (writing && Media is { IsReadOnly: false } media)
            {
                media.WriteBit(QuarterTrack, BitPosition, _writeFlux);
            }

            _writeFlux = _writing = false;
            BitPosition = (BitPosition + 1) % BitCount;
            _headWindow = ((_headWindow << 1) | (raw ? 1 : 0)) & 15;
            if (_headWindow != 0)
            {
                pulse |= (_headWindow & 2) != 0;
            }
            else
            {
                _random ^= _random << 13;
                _random ^= _random >> 17;
                _random ^= _random << 5;
                pulse |= _random % 10 < 3;
            }
        }

        return pulse;
    }

    /// <summary>
    ///  Completes a partial write cell when write mode ends.
    /// </summary>
    internal void EndWrite()
    {
        if (_writing && Media is { IsReadOnly: false } media) { media.WriteBit(QuarterTrack, BitPosition, _writeFlux); }
        _writeFlux = _writing = false;
    }
}
