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
}
