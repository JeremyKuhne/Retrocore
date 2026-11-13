// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  Memory with the Apple III's extended addressing for BASIC tests: plain addresses, and banked ones by their flat
///  address.
/// </summary>
internal sealed class BankedBasicMemory : IBasicMemory
{
    private readonly Dictionary<int, byte> _bytes = [];

    /// <inheritdoc/>
    public byte Read(int address) => _bytes.GetValueOrDefault(address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => _bytes[address] = value;

    /// <inheritdoc/>
    public byte ReadFar(byte xByte, int address) => Read(BusinessBasicDialect.Flat(xByte, address));

    /// <inheritdoc/>
    public void WriteFar(byte xByte, int address, byte value) => Write(BusinessBasicDialect.Flat(xByte, address), value);

    /// <summary>
    ///  Writes a byte at a flat address.
    /// </summary>
    /// <param name="flat">The flat address.</param>
    /// <param name="value">The byte.</param>
    public void WriteFlat(int flat, byte value) => Write(flat, value);

    /// <summary>
    ///  Sets one of BASIC's pointers in its zero page: its low and high bytes, and its X-byte.
    /// </summary>
    /// <param name="pointer">The pointer's address.</param>
    /// <param name="flat">The flat address it holds.</param>
    public void SetPointer(int pointer, int flat)
    {
        (byte xByte, int address) = BusinessBasicDialect.Split(flat);
        Write(pointer, (byte)address);
        Write(pointer + 1, (byte)(address >> 8));
        Write(pointer - BusinessBasicDialect.XByteOffset, xByte);
    }
}
