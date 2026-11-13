// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  The p-machine's registers, as the interpreter's zero page holds them.
/// </summary>
/// <param name="Base">BASE: the outer block's mark stack control word.</param>
/// <param name="Mark">MP: the running procedure's.</param>
/// <param name="JumpTable">JTAB: the running procedure's attributes.</param>
/// <param name="Segment">SEG: its segment's last word.</param>
/// <param name="Code">IPC: the next p-code.</param>
public sealed record PascalRegisters(
    PascalPointer Base,
    PascalPointer Mark,
    PascalPointer JumpTable,
    PascalPointer Segment,
    PascalPointer Code)
{
    /// <summary>
    ///  Reads the registers.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="interpreter">The interpreter.</param>
    /// <returns>The registers.</returns>
    public static PascalRegisters Read(IPascalMemory memory, PascalInterpreter interpreter)
    {
        ArgumentNullException.ThrowIfNull(interpreter);
        return new(
            interpreter.Register(memory, PascalInterpreter.BaseRegister),
            interpreter.Register(memory, PascalInterpreter.MarkRegister),
            interpreter.Register(memory, PascalInterpreter.JumpTableRegister),
            interpreter.Register(memory, PascalInterpreter.SegmentRegister),
            interpreter.Register(memory, PascalInterpreter.CodeRegister));
    }
}
