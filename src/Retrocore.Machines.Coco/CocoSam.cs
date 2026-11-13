// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The MC6883 Synchronous Address Multiplexer of the CoCo 1 and 2: the memory map, the RAM size and page, the CPU
///  rate and the video address generator's mode and start.
/// </summary>
/// <remarks>
///  <para>
///   Its sixteen state bits are written, never read, through <c>$FFC0-$FFDF</c>: an even address clears a bit and
///   the odd one above sets it. In order: V0-V2 (the video mode), F0-F6 (the display offset in 512-byte steps),
///   P1 (the page), R0-R1 (the rate), M0-M1 (the memory size) and TY (the map type). Reset clears them all.
///  </para>
/// </remarks>
public sealed class CocoSam
{
    /// <summary>
    ///  Gets the sixteen state bits, V0 in bit 0 and TY in bit 15.
    /// </summary>
    public ushort State { get; private set; }

    /// <summary>
    ///  Gets the video address generator's mode, V0-V2.
    /// </summary>
    public int VideoMode => State & 7;

    /// <summary>
    ///  Gets the address the display starts at, F0-F6 times 512.
    /// </summary>
    public int DisplayOffset => ((State >> 3) & 0x7F) << 9;

    /// <summary>
    ///  Gets P1, which in map type 0 with 64 KB puts the upper 32 KB of RAM at <c>$0000-$7FFF</c>.
    /// </summary>
    public bool Page1 => (State & 0x0400) != 0;

    /// <summary>
    ///  Gets the CPU rate, R0-R1: 0 slow, 1 fast outside RAM and PIA 0 (address-dependent), 2 or 3 fast.
    /// </summary>
    public int Rate => (State >> 11) & 3;

    /// <summary>
    ///  Gets the memory size, M0-M1: 0 4 KB chips, 1 16 KB, 2 64 KB (dynamic), 3 64 KB (static).
    /// </summary>
    public int MemorySize => (State >> 13) & 3;

    /// <summary>
    ///  Gets TY: map type 1, where 64 KB of RAM also fills <c>$8000-$FEFF</c>.
    /// </summary>
    public bool MapType1 => (State & 0x8000) != 0;

    /// <summary>
    ///  Writes a state bit through its address.
    /// </summary>
    /// <param name="address">An address in <c>$FFC0-$FFDF</c>.</param>
    public void Write(ushort address)
    {
        int offset = address & 0x1F;
        ushort bit = (ushort)(1 << (offset >> 1));
        State = (offset & 1) != 0 ? (ushort)(State | bit) : (ushort)(State & ~bit);
    }

    /// <summary>
    ///  Clears every state bit, as RESET does.
    /// </summary>
    public void Reset() => State = 0;

    /// <summary>
    ///  Restores state bits, as a snapshot does.
    /// </summary>
    /// <param name="state">The bits.</param>
    internal void Restore(ushort state) => State = state;
}
