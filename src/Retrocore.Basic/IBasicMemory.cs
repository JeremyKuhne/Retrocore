// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The machine's memory as BASIC sees it, read and written without side effects.
/// </summary>
public interface IBasicMemory
{
    /// <summary>
    ///  Reads a byte.
    /// </summary>
    /// <param name="address">The address, $0000-$FFFF.</param>
    /// <returns>The byte.</returns>
    byte Read(int address);

    /// <summary>
    ///  Writes a byte.
    /// </summary>
    /// <param name="address">The address, $0000-$FFFF.</param>
    /// <param name="value">The byte.</param>
    void Write(int address, byte value);

    /// <summary>
    ///  Reads a byte through an Apple III extended address: an X-byte with bit 7 set names a pair of 32K banks the
    ///  address reaches, as an indirect access through zero page does.
    /// </summary>
    /// <param name="xByte">The X-byte; without bit 7, the address as mapped now.</param>
    /// <param name="address">The address, $0000-$FFFF.</param>
    /// <returns>The byte.</returns>
    byte ReadFar(byte xByte, int address) => Read(address);

    /// <summary>
    ///  Writes a byte through an Apple III extended address.
    /// </summary>
    /// <param name="xByte">The X-byte; without bit 7, the address as mapped now.</param>
    /// <param name="address">The address, $0000-$FFFF.</param>
    /// <param name="value">The byte.</param>
    void WriteFar(byte xByte, int address, byte value) => Write(address, value);

    /// <summary>
    ///  Gets whether the memory keeps words high byte first, as the 6809's does, rather than low byte first.
    /// </summary>
    bool BigEndian => false;
}
