// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Logical assertions of CPU inputs, independent of physical pin polarity.
///  Edge-sensitive inputs are sampled by <see cref="Processor{TBus}.StepCycle"/>.
/// </summary>
[Flags]
public enum ProcessorSignals : byte
{
    /// <summary>
    ///  No inputs are asserted; RDY permits execution.
    /// </summary>
    None = 0,

    /// <summary>
    ///  RESET is asserted.
    /// </summary>
    Reset = 1,

    /// <summary>
    ///  IRQ is asserted.
    /// </summary>
    InterruptRequest = 2,

    /// <summary>
    ///  NMI is asserted. A new assertion latches an interrupt request.
    /// </summary>
    NonMaskableInterrupt = 4,

    /// <summary>
    ///  RDY holds reads on NMOS and both reads and writes on CMOS processors.
    /// </summary>
    ReadStall = 8,

    /// <summary>
    ///  Alias for the RDY assertion, including CMOS write-cycle stalls.
    /// </summary>
    ReadyStall = ReadStall,

    /// <summary>
    ///  SO is asserted. A new assertion sets the overflow flag.
    /// </summary>
    SetOverflow = 16
}
