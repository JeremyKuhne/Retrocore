// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Opcode maps authored in OpcodeTables.txt and emitted as static byte spans by the source generator.
///  Each entry contains code, addressing mode, and instruction in <see cref="OpCode"/> layout order.
/// </summary>
internal static partial class OpcodeTable
{
    /// <summary>
    ///  Gets a processor's static read-only opcode map without initialization or allocation.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <returns>A complete map indexed by opcode byte.</returns>
    internal static ReadOnlySpan<OpCode> Get(ProcessorVariant variant) =>
        MemoryMarshal.Cast<byte, OpCode>(variant switch
        {
            ProcessorVariant.Mos6502 => Mos6502,
            ProcessorVariant.Wdc65C02 => Wdc65C02,
            ProcessorVariant.Rockwell65C02 => Rockwell65C02,
            _ => throw new ArgumentOutOfRangeException(nameof(variant))
        });
}
