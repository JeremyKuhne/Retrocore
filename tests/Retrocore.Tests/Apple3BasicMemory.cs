// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  An Apple III's memory as BASIC sees it, read and written: addresses as the CPU maps them now, and extended
///  addresses through their X-byte, as the debugger reads them.
/// </summary>
/// <param name="bus">The machine's bus.</param>
internal sealed class Apple3BasicMemory(Apple3Bus bus) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address) => bus.Peek((ushort)address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => bus.Write((ushort)address, value);

    /// <inheritdoc/>
    public byte ReadFar(byte xByte, int address) =>
        (xByte & 0x80) != 0 && address >= 0x100 ? bus.Ram[bus.ExtendedOffset(xByte, (ushort)address)] : Read(address);

    /// <inheritdoc/>
    public void WriteFar(byte xByte, int address, byte value)
    {
        if ((xByte & 0x80) != 0 && address >= 0x100)
        {
            bus.Ram[bus.ExtendedOffset(xByte, (ushort)address)] = value;
        }
        else
        {
            Write(address, value);
        }
    }
}
