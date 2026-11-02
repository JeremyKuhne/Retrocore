// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  A flat 64K memory for debugger tests, all in one area.
/// </summary>
internal sealed class DebugTestMemory : IDebugMemory
{
    private readonly byte[] _bytes = new byte[0x10000];

    /// <summary>
    ///  Stores bytes.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="bytes">The bytes.</param>
    public void Set(ushort address, params byte[] bytes) => bytes.CopyTo(_bytes, address);

    /// <inheritdoc/>
    public byte Peek(ushort address) => _bytes[address];

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => DayOfWeek.Monday;
}
