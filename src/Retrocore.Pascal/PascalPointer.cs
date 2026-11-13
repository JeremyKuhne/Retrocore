// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A p-machine pointer: an address, and on the Apple III the X-byte that says which banks it reaches.
/// </summary>
/// <param name="Address">The address.</param>
/// <param name="Bank">The X-byte, or 0 for the memory the CPU sees.</param>
public readonly record struct PascalPointer(ushort Address, byte Bank)
{
    /// <summary>
    ///  Gets the pointer moved by some bytes, in the same banks.
    /// </summary>
    /// <param name="offset">The bytes to move by.</param>
    /// <returns>The pointer.</returns>
    public PascalPointer Plus(int offset) => new((ushort)(Address + offset), Bank);

    /// <inheritdoc/>
    public override string ToString() => Bank is 0 or < 0x80 ? $"${Address:X4}" : $"x{Bank:X2}:${Address:X4}";
}
