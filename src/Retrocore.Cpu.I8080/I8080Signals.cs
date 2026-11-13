// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The 8080's and 8085's input lines, asserted when set.
/// </summary>
[Flags]
public enum I8080Signals : byte
{
    /// <summary>
    ///  No line is asserted.
    /// </summary>
    None = 0,

    /// <summary>
    ///  RESET: the processor resets at the next state.
    /// </summary>
    Reset = 1,

    /// <summary>
    ///  INT on the 8080, INTR on the 8085: a maskable interrupt request, level-sensitive, sampled at the end of
    ///  each instruction. The device supplies an instruction, normally <c>RST</c>, in the acknowledge cycle.
    /// </summary>
    InterruptRequest = 2,

    /// <summary>
    ///  READY low: a memory or I/O access waits while it is asserted.
    /// </summary>
    Wait = 4,

    /// <summary>
    ///  TRAP (8085): a non-maskable interrupt to <c>$0024</c>, taken once for each assertion.
    /// </summary>
    Trap = 8,

    /// <summary>
    ///  RST 7.5 (8085): a rising edge latches an interrupt to <c>$003C</c> until it is taken or <c>SIM</c> clears it.
    /// </summary>
    Restart75 = 16,

    /// <summary>
    ///  RST 6.5 (8085): a level-sensitive interrupt to <c>$0034</c>.
    /// </summary>
    Restart65 = 32,

    /// <summary>
    ///  RST 5.5 (8085): a level-sensitive interrupt to <c>$002C</c>.
    /// </summary>
    Restart55 = 64,

    /// <summary>
    ///  SID (8085): the serial input bit <c>RIM</c> reads into bit 7.
    /// </summary>
    SerialInput = 128
}
