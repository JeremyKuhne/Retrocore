// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Cpu.M6502;

/// <summary>
///  An encoded instruction and its addressing mode.
///  The packed representation is three bytes: code, addressing mode, instruction.
/// </summary>
[StructLayout(LayoutKind.Sequential, Pack = 1)]
public readonly struct OpCode
{
    /// <summary>
    ///  Gets the encoded instruction byte.
    /// </summary>
    public byte Code { get; init; }

    /// <summary>
    ///  Gets the instruction's addressing mode.
    /// </summary>
    public AddressMode AddressMode { get; init; }

    /// <summary>
    ///  Gets the instruction.
    /// </summary>
    public Instruction Instruction { get; init; }
}
