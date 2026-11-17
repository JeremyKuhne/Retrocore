// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The Intel CPUs the core runs.
/// </summary>
public enum I8080Variant : byte
{
    /// <summary>
    ///  The 8080A: 4 to 18 states an instruction, with the undocumented opcodes as aliases of NOP, JMP, RET and
    ///  CALL.
    /// </summary>
    I8080,

    /// <summary>
    ///  The 8085A: the 8080's instructions with its own timings, RIM and SIM, the TRAP and RST 5.5, 6.5 and 7.5
    ///  interrupts, and the undocumented instructions and the V and K flags.
    /// </summary>
    I8085
}
