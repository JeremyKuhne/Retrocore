// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  A card in one of the Apple III's four slots.
/// </summary>
/// <remarks>
///  <para>
///   Each slot has sixteen I/O addresses at <c>$C080 + slot * 16</c> (<c>$C090-$C0CF</c>), a 256-byte ROM page at
///   <c>$Cn00</c> and a share of the <c>$C800-$CFFF</c> expansion ROM, all while the environment register enables
///   I/O. A card can also inhibit the motherboard's memory for reads at chosen addresses in <c>$F000-$FFFF</c> and
///   answer them itself. The
///   members have defaults for a card that leaves a space alone: nothing drives the bus, so it reads <c>$FF</c>.
///  </para>
/// </remarks>
public interface IApple3Card
{
    /// <summary>
    ///  Gets the slot, 1 to 4.
    /// </summary>
    int Slot { get; }

    /// <summary>
    ///  Reads one of the card's I/O addresses, with side effects.
    /// </summary>
    /// <param name="offset">The offset, 0-15.</param>
    /// <returns>The value.</returns>
    byte ReadIo(int offset) => 0xFF;

    /// <summary>
    ///  Writes one of the card's I/O addresses.
    /// </summary>
    /// <param name="offset">The offset, 0-15.</param>
    /// <param name="value">The value.</param>
    void WriteIo(int offset, byte value)
    {
    }

    /// <summary>
    ///  Reads one of the card's I/O addresses without side effects.
    /// </summary>
    /// <param name="offset">The offset, 0-15.</param>
    /// <returns>The value.</returns>
    byte PeekIo(int offset) => 0xFF;

    /// <summary>
    ///  Reads the card's ROM page, <c>$Cn00-$CnFF</c>.
    /// </summary>
    /// <param name="offset">The offset in the page.</param>
    /// <returns>The value.</returns>
    byte ReadRom(int offset) => 0xFF;

    /// <summary>
    ///  Writes the card's ROM page, which a card may decode as switches.
    /// </summary>
    /// <param name="offset">The offset in the page.</param>
    /// <param name="value">The value.</param>
    void WriteRom(int offset, byte value)
    {
    }

    /// <summary>
    ///  Gets whether the card has expansion ROM at <c>$C800-$CFFF</c>, which a read of its ROM page selects.
    /// </summary>
    bool HasExpansionRom => false;

    /// <summary>
    ///  Reads the card's expansion ROM, while it is selected.
    /// </summary>
    /// <param name="offset">The offset from <c>$C800</c>.</param>
    /// <returns>The value.</returns>
    byte ReadExpansionRom(int offset) => 0xFF;

    /// <summary>
    ///  Gets whether the card inhibits the motherboard for a read at an address, to answer it itself.
    /// </summary>
    /// <param name="address">The CPU address, <c>$F000-$FFFF</c>.</param>
    /// <returns>Whether the card answers.</returns>
    bool InhibitsRead(ushort address) => false;

    /// <summary>
    ///  Answers a read the card inhibits, with side effects.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The value.</returns>
    byte ReadInhibited(ushort address) => 0xFF;

    /// <summary>
    ///  Answers the Apple III's RESET.
    /// </summary>
    void Reset()
    {
    }
}
