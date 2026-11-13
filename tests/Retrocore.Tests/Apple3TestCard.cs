// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  An Apple III card for the slot bus's tests: its I/O reads <c>$20</c> plus the offset, its ROM page reads the
///  offset, and its expansion ROM reads <c>$E0</c>.
/// </summary>
/// <param name="slot">The slot.</param>
internal sealed class Apple3TestCard(int slot) : IApple3Card
{
    /// <inheritdoc/>
    public int Slot => slot;

    /// <summary>
    ///  Gets the last write to the card's I/O.
    /// </summary>
    public (int Offset, byte Value) Written { get; private set; }

    /// <inheritdoc/>
    public bool HasExpansionRom => true;

    /// <inheritdoc/>
    public byte ReadIo(int offset) => (byte)(0x20 + offset);

    /// <inheritdoc/>
    public void WriteIo(int offset, byte value) => Written = (offset, value);

    /// <inheritdoc/>
    public byte ReadRom(int offset) => (byte)offset;

    /// <inheritdoc/>
    public byte ReadExpansionRom(int offset) => 0xE0;
}
