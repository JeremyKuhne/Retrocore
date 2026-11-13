// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Asserted MC6809 input signals.
/// </summary>
[Flags]
public enum M6809Signals : byte
{
    /// <summary>
    ///  No inputs are asserted.
    /// </summary>
    None = 0,

    /// <summary>
    ///  RESET is asserted.
    /// </summary>
    Reset = 1,

    /// <summary>
    ///  IRQ is asserted, level sensitive.
    /// </summary>
    InterruptRequest = 2,

    /// <summary>
    ///  FIRQ is asserted, level sensitive.
    /// </summary>
    FastInterruptRequest = 4,

    /// <summary>
    ///  NMI is asserted; a low-to-high transition latches a request.
    /// </summary>
    NonMaskableInterrupt = 8,

    /// <summary>
    ///  HALT is asserted: the processor stops at the end of the instruction in progress, or of the next one when
    ///  HALT rises during an instruction's last cycle, and leaves the bus idle until it is released, latching NMI
    ///  and seeing IRQ and FIRQ only afterwards.
    /// </summary>
    Halt = 16
}
