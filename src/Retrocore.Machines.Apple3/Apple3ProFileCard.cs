// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Machines.Apple3;

/// <summary>
///  Apple's ProFile interface card for the Apple III, in one of slots 1-4, and the ProFile cabled to it.
/// </summary>
/// <remarks>
///  <para>
///   The card's ports are at <c>$C080</c> plus 16 times the slot, as Apple's SOS driver names them: <c>+0</c> writes a
///   byte to the ProFile, <c>+1</c> reads one, <c>+2</c> reads the status (bit 7 set while BSY is low, the ProFile
///   ready; bit 6 a parity error, never set here; bit 0 set when no ProFile answers), and a write to <c>+3</c> clears
///   the parity error.
///  </para>
///  <para>
///   The card's lines are an addressable latch that any access to its <c>$CN00</c> page sets, from the address's low
///   four bits: bits 0, 1 and 3 pick the line and bit 2 is its level. Line 0 is CMD, 1 the direction (high to read
///   from the ProFile), 2 the interrupt enable, 3 the port's read/write line and 4 the ProFile's reset. So
///   <c>$CN00</c> drops CMD and <c>$CN04</c> raises it, <c>$CN0C</c> resets the ProFile and <c>$CN08</c> lets it go.
///  </para>
///  <para>
///   The card moves whole pages by the III's pseudo-DMA, as the Service Reference Manual describes it: while the CPU
///   runs the boot ROM's chain of <c>SBC #$01</c> and <c>BEQ</c> at <c>$F800-$F8FF</c>, the board lowers DMA OK on
///   each of those fetches, and the card answers by moving one byte between the ProFile and RAM, at the page the
///   zero-page register names and the fetch's low byte, in the direction its direction line says. The CPU still
///   sees the ROM. Every fetch in the page counts, the dummy reads of a taken branch among them, which is why Apple's
///   driver enters the chain where it does and keeps two bytes of a short page aside. The card that answers is the one
///   whose ports or page the CPU last reached.
///  </para>
///  <para>
///   The card's interrupt, when BSY drops with interrupts enabled, is not raised: Apple's driver turns it off.
///  </para>
/// </remarks>
public sealed class Apple3ProFileCard : IApple3Card
{
    // The latch's lines.
    private const int CommandLine = 0;
    private const int DirectionLine = 1;
    private const int InterruptLine = 2;
    private const int ReadWriteLine = 3;
    private const int ResetLine = 4;

    private const byte Ready = 0x80;
    private const byte NoDrive = 0x01;

    private byte _lines;

    /// <summary>
    ///  Creates a card in a slot, with a ProFile with no image cabled to it.
    /// </summary>
    /// <param name="slot">The slot, 1 to 4.</param>
    /// <param name="clock">The machine's time, for the drive's activity.</param>
    /// <param name="activityTime">How long a block shows as moving, in the clock's unit.</param>
    internal Apple3ProFileCard(int slot, Func<long> clock, long activityTime)
    {
        Slot = slot;
        Drive = new($"slot{slot}profile", $"ProFile (slot {slot})", $"ProFile interface card in slot {slot}", clock, activityTime);
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
    ///  Gets whether the direction line says the card reads from the ProFile, for its pseudo-DMA.
    /// </summary>
    public bool Reading => Line(DirectionLine);

    /// <summary>
    ///  Gets whether the card's interrupt is enabled.
    /// </summary>
    public bool InterruptEnabled => Line(InterruptLine);

    /// <summary>
    ///  Drops every line, as RESET does, and resets the ProFile's controller.
    /// </summary>
    internal void Reset()
    {
        _lines = 0;
        Drive.SetCommand(high: false);
        Drive.Reset();
    }

    /// <summary>
    ///  Reads one of the card's ports.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <returns>The byte.</returns>
    internal byte Read(int offset) => offset switch
    {
        1 => Drive.ReadData(),
        _ => Peek(offset)
    };

    /// <summary>
    ///  Reads one of the card's ports without side effects.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <returns>The byte.</returns>
    internal byte Peek(int offset) => offset switch
    {
        2 => (byte)((Drive.Busy ? 0 : Ready) | (Drive.Connected ? 0 : NoDrive)),
        _ => 0xFF
    };

    /// <summary>
    ///  Writes one of the card's ports.
    /// </summary>
    /// <param name="offset">The port, the address's low four bits.</param>
    /// <param name="value">The byte.</param>
    internal void Write(int offset, byte value)
    {
        if (offset == 0) { Drive.WriteData(value); }
    }

    /// <summary>
    ///  Sets a line, as an access to the card's <c>$CN00</c> page does.
    /// </summary>
    /// <param name="offset">The address's low byte; its low four bits pick the line and its level.</param>
    internal void Switch(int offset)
    {
        int line = (offset & 3) | ((offset & 8) >> 1);
        bool high = (offset & 4) != 0;
        _lines = high ? (byte)(_lines | (1 << line)) : (byte)(_lines & ~(1 << line));
        switch (line)
        {
            case CommandLine:
                Drive.SetCommand(high);
                break;
            case ResetLine when high:
                Drive.Reset();
                break;
        }
    }

    /// <summary>
    ///  Moves one byte by pseudo-DMA, between the ProFile and RAM, in the direction the direction line says.
    /// </summary>
    /// <param name="ram">The RAM.</param>
    /// <param name="offset">The byte's offset in it.</param>
    internal void Transfer(byte[] ram, int offset)
    {
        if (Reading)
        {
            ram[offset] = Drive.ReadData();
        }
        else
        {
            Drive.WriteData(ram[offset]);
        }
    }

    /// <inheritdoc/>
    byte IApple3Card.ReadIo(int offset) => Read(offset);

    /// <inheritdoc/>
    void IApple3Card.WriteIo(int offset, byte value) => Write(offset, value);

    /// <inheritdoc/>
    byte IApple3Card.PeekIo(int offset) => Peek(offset);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The page has no ROM; a read sets a line, as a write does, and nothing drives the bus.
    ///  </para>
    /// </remarks>
    byte IApple3Card.ReadRom(int offset)
    {
        Switch(offset);
        return 0xFF;
    }

    /// <inheritdoc/>
    void IApple3Card.WriteRom(int offset, byte value) => Switch(offset);

    /// <inheritdoc/>
    void IApple3Card.Reset() => Reset();

    private bool Line(int line) => (_lines & (1 << line)) != 0;

    /// <summary>
    ///  Gets whether the read/write line is high, the port reading.
    /// </summary>
    public bool PortReading => Line(ReadWriteLine);
}
