// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Architectural CPU registers. Register values do not include memory or device state.
/// </summary>
public struct ProcessorRegisters
{
    /// <summary>
    ///  Gets or sets the accumulator (A).
    /// </summary>
    public byte Accumulator { get; set; }

    /// <summary>
    ///  Gets or sets the X index register.
    /// </summary>
    public byte X { get; set; }

    /// <summary>
    ///  Gets or sets the Y index register.
    /// </summary>
    public byte Y { get; set; }

    /// <summary>
    ///  Gets or sets the stack pointer (S), relative to page one.
    /// </summary>
    public byte StackPointer { get; set; }

    /// <summary>
    ///  Gets or sets the processor status (P).
    /// </summary>
    public StatusRegister Status { get; set; }

    /// <summary>
    ///  Gets or sets the program counter (PC).
    /// </summary>
    public ushort ProgramCounter { get; set; }
}
