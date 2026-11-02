// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  A separate I/O address space, as the Z80's <c>IN</c> and <c>OUT</c> reach; CPUs with memory-mapped I/O
///  only, such as the 6502, have none.
/// </summary>
public interface IIoBus
{
    /// <summary>
    ///  Reads a port.
    /// </summary>
    /// <param name="port">The full port address the CPU drives, such as <c>BC</c> for <c>IN A,[C]</c>.</param>
    /// <returns>The value.</returns>
    byte In(ushort port);

    /// <summary>
    ///  Writes a port.
    /// </summary>
    /// <param name="port">The full port address the CPU drives.</param>
    /// <param name="value">The value.</param>
    void Out(ushort port, byte value);
}
