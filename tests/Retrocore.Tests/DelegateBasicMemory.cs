// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  BASIC's view of memory through a machine's side-effect-free reads and writes, or a plain array.
/// </summary>
/// <param name="read">Reads a byte.</param>
/// <param name="write">Writes a byte.</param>
/// <param name="bigEndian">Whether words are kept high byte first.</param>
internal sealed class DelegateBasicMemory(Func<int, byte> read, Action<int, byte> write, bool bigEndian = false) : IBasicMemory
{
    /// <summary>
    ///  Wraps a 64K array.
    /// </summary>
    /// <param name="memory">The array.</param>
    /// <returns>The memory.</returns>
    internal static DelegateBasicMemory Of(byte[] memory) => new(address => memory[address], (address, value) => memory[address] = value);

    /// <inheritdoc/>
    public byte Read(int address) => read(address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => write(address, value);

    /// <inheritdoc/>
    public bool BigEndian => bigEndian;
}
