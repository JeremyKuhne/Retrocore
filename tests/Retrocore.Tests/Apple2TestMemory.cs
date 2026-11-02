// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  A IIe bus as debug modules read it.
/// </summary>
/// <param name="bus">The bus.</param>
internal sealed class Apple2TestMemory(Apple2Bus bus) : IDebugMemory
{
    /// <inheritdoc/>
    public byte Peek(ushort address) => bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => bus.ReadArea(address);
}
