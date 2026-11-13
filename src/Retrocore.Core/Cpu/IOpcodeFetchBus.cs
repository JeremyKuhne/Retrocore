// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  A bus that needs to know which reads are opcode fetches, the cycles a 6502 marks with SYNC or a Z80 with M1.
/// </summary>
/// <remarks>
///  <para>
///   Most buses do not care, and a processor reads every byte through <see cref="IProcessorBus.Read"/>. A bus whose
///   decoding follows the fetch, such as the Apple III's extended addressing, which ends at each SYNC, implements
///   this interface and the processor calls <see cref="ReadOpcode"/> for each fetch instead. Only class buses are
///   told; a struct bus that implements it still gets <see cref="IProcessorBus.Read"/>.
///  </para>
/// </remarks>
public interface IOpcodeFetchBus : IProcessorBus
{
    /// <summary>
    ///  Performs an opcode fetch, including the 6502's fetch that an interrupt discards, which still raises SYNC.
    /// </summary>
    /// <param name="address">The 16-bit bus address.</param>
    /// <returns>The value driven onto the data bus.</returns>
    byte ReadOpcode(ushort address);
}
