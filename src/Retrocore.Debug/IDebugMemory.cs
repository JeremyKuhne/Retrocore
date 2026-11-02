// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A machine's memory as debug modules read it: without side effects, and with the area each address maps.
/// </summary>
internal interface IDebugMemory
{
    /// <summary>
    ///  Reads a byte without the side effects of a read.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The byte.</returns>
    byte Peek(ushort address);

    /// <summary>
    ///  Gets the memory area an address reads under the current memory map.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The area, such as the IIe's main RAM or the Model I's ROM.</returns>
    Enum ReadArea(ushort address);

    /// <summary>
    ///  Gets the memory area a write to an address reaches under the current memory map.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The area; the one a read uses unless the machine maps writes apart from reads.</returns>
    Enum WriteArea(ushort address) => ReadArea(address);
}
