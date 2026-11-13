// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Pascal;

namespace Retrocore.Debug;

/// <summary>
///  The memory Apple Pascal's interpreter sees on the Apple II: the 64K the CPU sees, with the language card as it
///  is switched.
/// </summary>
/// <param name="bus">The bus.</param>
internal sealed class Apple2PascalMemory(Apple2Bus bus) : IPascalMemory
{
    /// <inheritdoc/>
    public byte Read(ushort address, byte bank) => bus.Peek(address);
}
