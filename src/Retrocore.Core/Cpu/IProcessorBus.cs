// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  Supplies memory and device side effects for CPU bus accesses, including dummy accesses.
/// </summary>
public interface IProcessorBus
{
    /// <summary>
    ///  Performs one bus read.
    /// </summary>
    /// <param name="address">The 16-bit bus address.</param>
    /// <returns>The value driven onto the data bus.</returns>
    byte Read(ushort address);

    /// <summary>
    ///  Performs one bus write.
    /// </summary>
    /// <param name="address">The 16-bit bus address.</param>
    /// <param name="value">The value driven onto the data bus.</param>
    void Write(ushort address, byte value);
}
