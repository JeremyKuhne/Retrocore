// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Internal processor sequence kind.
/// </summary>
internal enum M6809Sequence : byte
{
    /// <summary>
    ///  Instruction execution.
    /// </summary>
    Instruction,

    /// <summary>
    ///  Hardware interrupt entry.
    /// </summary>
    Interrupt,

    /// <summary>
    ///  Reset-vector fetch.
    /// </summary>
    Reset
}
