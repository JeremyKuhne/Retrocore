// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Atari;

namespace Retrocore.Tests;

/// <summary>
///  An Atari's memory as Atari BASIC's tables reach it, through the bus.
/// </summary>
/// <param name="machine">The machine.</param>
internal sealed class AtariBasicMemory(AtariMachine machine) : IBasicMemory
{
    /// <inheritdoc/>
    public byte Read(int address) => machine.Bus.Peek((ushort)address);

    /// <inheritdoc/>
    public void Write(int address, byte value) => machine.Bus.Write((ushort)address, value);
}
