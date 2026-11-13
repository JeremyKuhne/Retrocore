// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Apple1;

namespace Retrocore.Tests;

/// <summary>
///  An Apple-1's memory as BASIC's program reader sees it.
/// </summary>
/// <param name="machine">The machine.</param>
internal sealed class Apple1BasicMemory(Apple1Machine machine) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address) => machine.Bus.Peek((ushort)address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => machine.Bus.Write((ushort)address, value);
}
