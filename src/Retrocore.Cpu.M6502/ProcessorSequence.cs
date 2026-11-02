// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Identifies the active CPU microsequence.
/// </summary>
internal enum ProcessorSequence : byte
{
    /// <summary>
    ///  Fetch or execute an instruction.
    /// </summary>
    Instruction,

    /// <summary>
    ///  Perform reset bus cycles.
    /// </summary>
    Reset,

    /// <summary>
    ///  Perform hardware interrupt bus cycles.
    /// </summary>
    Interrupt
}
