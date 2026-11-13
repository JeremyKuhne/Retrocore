// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

/// <summary>
///  A launched machine's memory as BASIC sees it: the CPU's memory map, read and written without side effects.
/// </summary>
/// <param name="target">The machine.</param>
internal sealed class TargetBasicMemory(IDebugTarget target) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address) => target.Peek((ushort)address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => target.Poke((ushort)address, value);

    /// <inheritdoc/>
    public byte ReadFar(byte xByte, int address) => target.PeekFar(xByte, (ushort)address);

    /// <inheritdoc/>
    public void WriteFar(byte xByte, int address, byte value) => target.PokeFar(xByte, (ushort)address, value);

    /// <inheritdoc/>
    public bool BigEndian => target.Basic?.BigEndian == true;
}
