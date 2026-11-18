// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The 4040 DOS processor's memory map: its 6502 decodes 15 address lines.
/// </summary>
/// <remarks>
///  <para>
///   The two 6532s' RAM is at <c>$0000</c> and <c>$0080</c>, again at <c>$0100</c>; their I/O at <c>$0200</c> and
///   <c>$0280</c>, repeated through <c>$0FFF</c>. The four 1K buffers it shares with the controller are at
///   <c>$1000</c>, <c>$2000</c>, <c>$3000</c> and <c>$4000</c>, each repeated through its 4K, and the DOS fills
///   <c>$5000-$7FFF</c>.
///  </para>
/// </remarks>
public sealed class Cbm4040DosBus : IProcessorBus
{
    private readonly Cbm4040 _unit;

    /// <summary>
    ///  Builds the DOS processor's memory map.
    /// </summary>
    /// <param name="unit">The unit whose chips it reaches.</param>
    internal Cbm4040DosBus(Cbm4040 unit) => _unit = unit;

    /// <inheritdoc/>
    public byte Read(ushort address) => Access(address, write: false, value: 0, peek: false);

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Access(address, write: true, value, peek: false);

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte.</returns>
    public byte Peek(ushort address) => Access(address, write: false, value: 0, peek: true);

    private byte Access(ushort address, bool write, byte value, bool peek)
    {
        int a = address & 0x7FFF;
        if (a >= 0x5000) { return _unit.Dos[a - 0x5000]; }

        if (a >= 0x1000)
        {
            Span<byte> buffer = _unit.Buffer((a >> 12) - 1);
            if (write) { buffer[a & 0x3FF] = value; }
            return buffer[a & 0x3FF];
        }

        Riot6532 riot = (a & 0x80) == 0 ? _unit.Riot0 : _unit.Riot1;
        if ((a & 0x200) == 0)
        {
            if ((a & 0xC00) != 0) { return 0; }
            if (write) { riot.Ram[a & 0x7F] = value; }
            return riot.Ram[a & 0x7F];
        }

        _unit.UpdateInputs();
        if (write)
        {
            riot.Write(a & 0x1F, value);
            _unit.UpdateOutputs();
            return value;
        }

        return peek ? riot.Peek(a & 0x1F) : riot.Read(a & 0x1F);
    }
}
