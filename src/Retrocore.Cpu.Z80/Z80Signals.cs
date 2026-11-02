// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The Z80's input lines, asserted when set.
/// </summary>
[Flags]
public enum Z80Signals : byte
{
    /// <summary>
    ///  No line is asserted.
    /// </summary>
    None = 0,

    /// <summary>
    ///  RESET: the processor resets at the next cycle.
    /// </summary>
    Reset = 1,

    /// <summary>
    ///  INT: a maskable interrupt request, level-sensitive, sampled at the end of each instruction.
    /// </summary>
    InterruptRequest = 2,

    /// <summary>
    ///  NMI: a non-maskable interrupt, taken once for each assertion.
    /// </summary>
    NonMaskableInterrupt = 4,

    /// <summary>
    ///  WAIT: a memory or I/O access waits while it is asserted.
    /// </summary>
    Wait = 8
}
