// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  64K of RAM and nothing else, which <see cref="InstructionCycles"/> runs an instruction over.
/// </summary>
/// <param name="memory">The 64K.</param>
internal readonly struct FlatBus(byte[] memory) : IProcessorBus
{
    /// <summary>
    ///  Gets the 64K.
    /// </summary>
    public byte[] Memory { get; } = memory;

    /// <inheritdoc/>
    public byte Read(ushort address) => Memory[address];

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Memory[address] = value;
}
