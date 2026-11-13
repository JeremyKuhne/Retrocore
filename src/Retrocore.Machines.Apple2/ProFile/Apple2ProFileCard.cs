// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A ProFile interface card for the Apple II, and the ProFile cabled to it: a ProDOS block device whose firmware
///  (<see cref="ProFileRom"/>) talks to the ProFile with its own handshakes.
/// </summary>
/// <remarks>
///  <para>
///   The ports, at <c>$C080</c> plus 16 times the slot, are the Apple III card's for the first four: <c>+0</c> writes
///   a byte to the ProFile, <c>+1</c> reads one, <c>+2</c> reads the status (bit 7 set while BSY is low, bit 0 set
///   when no ProFile answers) and <c>+3</c> clears a parity error, of which there are none. The Apple III card's lines,
///   which its <c>$CN00</c> page sets, are ports here, since this card's page is its ROM: any access to <c>+4</c>
///   drops CMD and <c>+5</c> raises it, <c>+6</c> resets the ProFile and <c>+7</c> lets it go. <c>+8</c> and
///   <c>+9</c> read the ProFile's size in blocks, at most 65535, for the firmware's STATUS.
///  </para>
/// </remarks>
public sealed class Apple2ProFileCard
{
    // A block shows as moving for a thirtieth of a second.
    private const long ActivityCycles = 1_020_484 / 30;

    private const byte Ready = 0x80;
    private const byte NoDrive = 0x01;

    /// <summary>
    ///  Creates a card in a slot, with a ProFile with no image cabled to it.
    /// </summary>
    /// <param name="slot">The slot, 1 to 7.</param>
    /// <param name="bus">The bus, whose cycles time the drive's activity.</param>
    internal Apple2ProFileCard(int slot, Apple2Bus bus)
    {
        Slot = slot;
        Drive = new(
            $"slot{slot}profile",
            $"ProFile (slot {slot})",
            $"ProFile interface card in slot {slot}, with Retrocore's firmware",
            () => (long)bus.CycleCount,
            ActivityCycles);
    }

    /// <summary>
    ///  Gets the card's slot.
    /// </summary>
    public int Slot { get; }

    /// <summary>
    ///  Gets the ProFile cabled to the card.
    /// </summary>
    public ProFileDrive Drive { get; }

    /// <summary>
    ///  Drops CMD and resets the ProFile's controller, as RESET does.
    /// </summary>
    internal void Reset()
    {
        Drive.SetCommand(high: false);
        Drive.Reset();
    }

    /// <summary>
    ///  Reads a port.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <param name="floatingBus">What a port with nothing to say reads.</param>
    /// <returns>The byte.</returns>
    internal byte Read(int offset, byte floatingBus)
    {
        if (offset == 1) { return Drive.ReadData(); }
        Switch(offset);
        return Peek(offset, floatingBus);
    }

    /// <summary>
    ///  Reads a port without side effects.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <param name="floatingBus">What a port with nothing to say reads.</param>
    /// <returns>The byte.</returns>
    internal byte Peek(int offset, byte floatingBus)
    {
        uint blocks = Math.Min((uint)Drive.BlockCount, 0xFFFF);
        return offset switch
        {
            2 => (byte)((Drive.Busy ? 0 : Ready) | (Drive.Connected ? 0 : NoDrive)),
            8 => (byte)blocks,
            9 => (byte)(blocks >> 8),
            _ => floatingBus
        };
    }

    /// <summary>
    ///  Writes a port.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <param name="value">The byte.</param>
    internal void Write(int offset, byte value)
    {
        if (offset == 0)
        {
            Drive.WriteData(value);
            return;
        }

        Switch(offset);
    }

    // Any access to ports 4-7 sets a line: CMD low or high, the reset on or off.
    private void Switch(int offset)
    {
        switch (offset)
        {
            case 4 or 5:
                Drive.SetCommand(offset == 5);
                break;
            case 6:
                Drive.Reset();
                break;
        }
    }
}
