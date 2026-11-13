// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Pascal;

namespace Retrocore.Debug;

/// <summary>
///  The memory Apple III Pascal's interpreter sees: the CPU's view, and through an X-byte, a bank pair.
/// </summary>
/// <param name="bus">The bus.</param>
internal sealed class Apple3PascalMemory(Apple3Bus bus) : IPascalMemory
{
    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   An X-byte reaches its banks above zero page, as the hardware's extended addressing does.
    ///  </para>
    /// </remarks>
    public byte Read(ushort address, byte bank) =>
        (bank & 0x80) != 0 && address >= 0x100 ? bus.Ram[bus.ExtendedOffset(bank, address)] : bus.Peek(address);
}
