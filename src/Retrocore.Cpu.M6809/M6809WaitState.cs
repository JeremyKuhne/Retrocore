// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Processor wait mode entered by <c>SYNC</c> or <c>CWAI</c>.
/// </summary>
internal enum M6809WaitState : byte
{
    /// <summary>
    ///  Not waiting.
    /// </summary>
    None,

    /// <summary>
    ///  Waiting in <c>SYNC</c> for any interrupt line assertion.
    /// </summary>
    Sync,

    /// <summary>
    ///  Waiting in <c>CWAI</c> with registers already stacked for an unmasked interrupt.
    /// </summary>
    Cwai
}
