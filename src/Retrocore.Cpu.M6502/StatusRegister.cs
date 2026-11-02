// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Processor status register flags for the 6502 CPU. Stored as a single byte where each bit represents a
///  distinct condition or mode set by the processor.
/// </summary>
[Flags]
public enum StatusRegister : byte
{
    /// <summary>
    ///  Carry flag (C). Set when an arithmetic operation produces a carry out of, or borrow into, bit 7.
    ///  Also used by shift and rotate instructions.
    /// </summary>
    Carry           = 0b00000001,

    /// <summary>
    ///  Zero flag (Z). Set when the result of the last operation was zero.
    /// </summary>
    Zero            = 0b00000010,

    /// <summary>
    ///  Interrupt request disable flag (I). When set, maskable IRQB interrupts are ignored.
    /// </summary>
    IRQBDisable     = 0b00000100,

    /// <summary>
    ///  Decimal mode flag (D). When set, ADC and SBC operate in Binary-Coded Decimal (BCD) mode.
    /// </summary>
    DecimalMode     = 0b00001000,

    /// <summary>
    ///  Break command flag (B). Set when an interrupt was caused by a BRK instruction rather than a hardware
    ///  interrupt.
    /// </summary>
    BRKCommand      = 0b00010000,

    /// <summary>
    ///  Unused flag, should always be '1'.
    /// </summary>
    Unused          = 0b00100000,

    /// <summary>
    ///  Overflow flag (V). Set when a signed arithmetic operation produces a result that cannot be represented
    ///  in two's complement (i.e., the sign bit is incorrect).
    /// </summary>
    Overflow        = 0b01000000,

    /// <summary>
    ///  Negative flag (N). Set to the value of bit 7 of the result of the last operation, indicating a
    ///  negative value in two's complement representation.
    /// </summary>
    Negative        = 0b10000000
}
