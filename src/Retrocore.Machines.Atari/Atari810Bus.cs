// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The 810's memory map, as its 6507 sees it through 13 address lines (Altirra Hardware Reference Manual, 10.10).
/// </summary>
/// <remarks>
///  <para>
///   A11 selects the 2 KB ROM, <c>$0800-$0FFF</c>. Below it, A8 selects the 6532: its RAM with A9 clear
///   (<c>$0180-$01FF</c>, where the stack is) and its registers with A9 set (<c>$0380-$039F</c>). With A8 clear, A7
///   selects the 6810's 128 bytes of RAM (<c>$0080-$00FF</c>) or, clear, the FD1771 (<c>$0000-$0003</c>). Each is
///   repeated through its range, and A12 isn't decoded, so the whole map repeats every 4 KB; the ROM's vectors are
///   read at <c>$FFFA-$FFFF</c>.
///  </para>
///  <para>
///   The FD1771's data bus is inverted: the 6507 reads and writes each of its registers inverted.
///  </para>
/// </remarks>
public sealed class Atari810Bus : IProcessorBus
{
    private readonly Atari810 _drive;

    /// <summary>
    ///  Builds the drive's memory map.
    /// </summary>
    /// <param name="drive">The drive whose chips it reaches.</param>
    internal Atari810Bus(Atari810 drive) => _drive = drive;

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
        if ((address & 0x0800) != 0) { return _drive.Rom[address & 0x07FF]; }

        if ((address & 0x0100) != 0)
        {
            if ((address & 0x0200) == 0)
            {
                Span<byte> ram = _drive.Riot.Ram;
                if (write) { ram[address & 0x7F] = value; }
                return ram[address & 0x7F];
            }

            _drive.UpdateInputs();
            if (write)
            {
                _drive.Riot.Write(address & 0x1F, value);
                _drive.UpdateOutputs();
                return value;
            }

            return peek ? _drive.Riot.Peek(address & 0x1F) : _drive.Riot.Read(address & 0x1F);
        }

        if ((address & 0x0080) != 0)
        {
            if (write) { _drive.Ram[address & 0x7F] = value; }
            return _drive.Ram[address & 0x7F];
        }

        int register = address & 3;
        if (write)
        {
            _drive.Fdc.Write(register, (byte)~value);
            return value;
        }

        return (byte)~(peek ? _drive.Fdc.Peek(register) : _drive.Fdc.Read(register));
    }
}
