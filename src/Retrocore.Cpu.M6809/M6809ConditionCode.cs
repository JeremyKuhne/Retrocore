// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  The MC6809 condition-code bits.
/// </summary>
[Flags]
public enum M6809ConditionCode : byte
{
    /// <summary>
    ///  No condition-code bits are set.
    /// </summary>
    None = 0x00,

    /// <summary>
    ///  Carry / borrow.
    /// </summary>
    Carry = 0x01,

    /// <summary>
    ///  Overflow.
    /// </summary>
    Overflow = 0x02,

    /// <summary>
    ///  Zero.
    /// </summary>
    Zero = 0x04,

    /// <summary>
    ///  Negative.
    /// </summary>
    Negative = 0x08,

    /// <summary>
    ///  Mask IRQ.
    /// </summary>
    InterruptMask = 0x10,

    /// <summary>
    ///  Half carry.
    /// </summary>
    HalfCarry = 0x20,

    /// <summary>
    ///  Mask FIRQ.
    /// </summary>
    FastInterruptMask = 0x40,

    /// <summary>
    ///  Entire flag.
    /// </summary>
    Entire = 0x80
}
