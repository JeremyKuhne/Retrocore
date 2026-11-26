// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  The 1541's memory map: its decoding uses A15, A12, A11 and A10, and A0-A3 within the VIAs.
/// </summary>
/// <remarks>
///  <para>
///   The 2K of RAM is at <c>$0000-$07FF</c>, VIA 1 at <c>$1800</c> and VIA 2 at <c>$1C00</c>, each VIA's 16
///   registers repeating through its 1K, and all of it again at <c>$2000</c>, <c>$4000</c> and <c>$6000</c>. The
///   16K of DOS is at <c>$C000</c> and again at <c>$8000</c>. Nothing answers the rest, which reads 0, as in MAME.
///  </para>
/// </remarks>
public sealed class Cbm1541Bus : IProcessorBus
{
    private readonly Cbm1541 _drive;

    /// <summary>
    ///  Builds the drive's memory map.
    /// </summary>
    /// <param name="drive">The drive whose chips it reaches.</param>
    internal Cbm1541Bus(Cbm1541 drive) => _drive = drive;

    /// <inheritdoc/>
    public byte Read(ushort address) => Access(address, write: false, value: 0, peek: false);

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Access(address, write: true, value, peek: false);

    /// <summary>
    ///  Reads without side effects, for the debugger: a VIA shows its inputs as the last cycle left them.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte.</returns>
    public byte Peek(ushort address) => Access(address, write: false, value: 0, peek: true);

    private byte Access(ushort address, bool write, byte value, bool peek)
    {
        if (address >= 0x8000) { return _drive.Rom[address & 0x3FFF]; }

        int a = address & 0x1FFF;
        if (a < 0x0800)
        {
            if (write) { _drive.Ram[a] = value; }
            return _drive.Ram[a];
        }

        if (a < 0x1800) { return 0; }

        Via6522 via = a < 0x1C00 ? _drive.Via1 : _drive.Via2;
        byte register = (byte)(a & 0x0F);
        // Bringing the inputs up to date can set VIA 1's ATN flag and pull the bus, so a peek leaves them.
        if (!peek) { _drive.UpdateInputs(); }
        if (write)
        {
            via.Write(register, value);
            _drive.UpdateOutputs();
            return value;
        }

        return peek ? via.Peek(register) : via.Read(register);
    }
}
