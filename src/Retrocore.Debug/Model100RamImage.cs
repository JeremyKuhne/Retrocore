// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

/// <summary>
///  A Model 100's RAM image as the memory it fills, the top of the 64K space; below it reads $FF and takes no writes,
///  as the machine's unfitted addresses do.
/// </summary>
/// <param name="ram">The image.</param>
/// <param name="start">The image's first address.</param>
internal sealed class Model100RamImage(byte[] ram, int start) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address) => address >= start ? ram[address - start] : (byte)0xFF;

    /// <inheritdoc/>
    public void Write(int address, byte value)
    {
        if (address >= start) { ram[address - start] = value; }
    }
}
