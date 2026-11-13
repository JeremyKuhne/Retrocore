// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Pascal;

namespace Retrocore.Debug;

/// <summary>
///  The memory Apple Pascal's interpreter sees on the Apple II: main memory below <c>$C000</c> (bank 0) or the IIe's
///  auxiliary 64K (bank 1), whichever the CPU reads now; zero page, the stack and <c>$C000-$FFFF</c> as the CPU sees
///  them, with the language card as it is switched.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal 1.3 on a 128K IIe reads its code from the auxiliary 64K and its data from main memory, switching
///   between them, so the bank says which a pointer is into.
///  </para>
/// </remarks>
/// <param name="bus">The bus.</param>
internal sealed class Apple2PascalMemory(Apple2Bus bus) : IPascalMemory
{
    /// <inheritdoc/>
    public byte Read(ushort address, byte bank) =>
        address is < 0x200 or >= 0xC000 ? bus.Peek(address)
            : bank == 1 ? bus.AuxiliaryMemory[address]
                : bus.MainMemory[address];
}