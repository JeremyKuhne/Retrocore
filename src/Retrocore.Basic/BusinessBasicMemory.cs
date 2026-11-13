// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Memory read by flat address: banked addresses through their X-byte, others as mapped now.
/// </summary>
/// <param name="memory">The memory.</param>
internal sealed class BusinessBasicMemory(IBasicMemory memory) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address)
    {
        (byte xByte, int at) = BusinessBasicDialect.Split(address);
        return memory.ReadFar(xByte, at);
    }

    /// <inheritdoc/>
    public void Write(int address, byte value)
    {
        (byte xByte, int at) = BusinessBasicDialect.Split(address);
        memory.WriteFar(xByte, at, value);
    }
}
