// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

public abstract partial class BasicDialect
{
    /// <summary>
    ///  Gets the address a program written into memory must end by.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The first address past the room for the program.</returns>
    internal virtual int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, Pointers.MemoryTop);

    /// <summary>
    ///  Tests whether BASIC is at its prompt or running a typed command, rather than running a program.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>Whether the current line is the direct-mode line.</returns>
    public virtual bool InDirectMode(IBasicMemory memory) => BasicProgram.Word(memory, Pointers.CurrentLine) == 0xFFFF;

    /// <summary>
    ///  Clears the variables, arrays and strings, and resets the DATA pointer and CONT, as the ROM's <c>CLEARC</c>
    ///  does after a line is typed. Leaves the stack alone.
    /// </summary>
    /// <param name="memory">The memory.</param>
    internal virtual void Clear(IBasicMemory memory)
    {
        BasicPointers pointers = Pointers;
        int variables = BasicProgram.Word(memory, pointers.Variables);
        BasicProgram.WriteWord(memory, pointers.StringBottom, BasicProgram.Word(memory, pointers.MemoryTop));
        BasicProgram.WriteWord(memory, pointers.Arrays, variables);
        BasicProgram.WriteWord(memory, pointers.FreeStart, variables);
        BasicProgram.WriteWord(memory, pointers.DataPointer, BasicProgram.Word(memory, pointers.ProgramStart) - 1);
        BasicProgram.WriteWord(memory, pointers.ContinueText, 0);
    }
}
