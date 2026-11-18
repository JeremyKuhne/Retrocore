// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The 4040 controller's memory map: its 6504 decodes 13 address lines.
/// </summary>
/// <remarks>
///  <para>
///   The 6530's 64 bytes of RAM are at <c>$0000</c>, the VIA at <c>$0040</c> and the 6530's I/O at <c>$0080</c>,
///   each repeated through <c>$03FF</c>. The four shared 1K buffers follow at <c>$0400-$13FF</c>, and the 6530's ROM
///   is at <c>$1C00-$1FFF</c>.
///  </para>
/// </remarks>
public sealed class Cbm4040ControllerBus : IProcessorBus
{
    private readonly Cbm4040 _unit;

    /// <summary>
    ///  Builds the controller's memory map.
    /// </summary>
    /// <param name="unit">The unit whose chips it reaches.</param>
    internal Cbm4040ControllerBus(Cbm4040 unit) => _unit = unit;

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
        int a = address & 0x1FFF;
        if (a >= 0x1C00) { return _unit.Controller[a - 0x1C00]; }

        if (a >= 0x400)
        {
            if (a >= 0x1400) { return 0; }
            Span<byte> buffer = _unit.Buffer((a - 0x400) >> 10);
            if (write) { buffer[a & 0x3FF] = value; }
            return buffer[a & 0x3FF];
        }

        switch (a & 0xC0)
        {
            case 0x00:
                if (write) { _unit.Miot.Ram[a & 0x3F] = value; }
                return _unit.Miot.Ram[a & 0x3F];
            case 0x40:
                _unit.UpdateControllerInputs();
                if (write)
                {
                    _unit.Via.Write((byte)(a & 0x0F), value);
                    _unit.UpdateControllerOutputs();
                    return value;
                }

                return peek ? _unit.Via.Peek((byte)(a & 0x0F)) : _unit.Via.Read((byte)(a & 0x0F));
            case 0x80:
                _unit.UpdateControllerInputs();
                if (write)
                {
                    _unit.Miot.Write(a & 0x0F, value);
                    _unit.UpdateControllerOutputs();
                    return value;
                }

                return peek ? _unit.Miot.Peek(a & 0x0F) : _unit.Miot.Read(a & 0x0F);
            default:
                return 0;
        }
    }
}
