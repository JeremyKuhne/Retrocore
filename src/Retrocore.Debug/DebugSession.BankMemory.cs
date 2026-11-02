// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A memory bank as debug modules read memory: as if the bank were mapped at every address it holds, so a
    ///  module whose code lives in the bank finds its lines and labels there, whatever the memory map maps now.
    /// </summary>
    /// <param name="Bank">The bank.</param>
    private sealed record BankMemory(DebugMemoryBank Bank) : IDebugMemory
    {
        /// <inheritdoc/>
        public byte Peek(ushort address) => Bank.Peek(address) ?? 0xFF;

        /// <inheritdoc/>
        public Enum ReadArea(ushort address) => Bank.AreaOf(address) ?? Unmapped.Nothing;
    }
}
