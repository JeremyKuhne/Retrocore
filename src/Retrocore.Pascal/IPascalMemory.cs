// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  The memory a p-machine's interpreter sees, read without side effects.
/// </summary>
public interface IPascalMemory
{
    /// <summary>
    ///  Reads a byte.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="bank">
    ///  The Apple III's X-byte for the pointer the interpreter reads through: <c>$80-$8F</c> for a bank pair, or 0 for
    ///  the memory the CPU sees.
    /// </param>
    /// <returns>The byte.</returns>
    byte Read(ushort address, byte bank);
}
