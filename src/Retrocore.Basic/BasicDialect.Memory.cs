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
    ///  Gets where the program lies in memory, as addresses <see cref="Text"/> reads.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program's first byte and the first byte past it.</returns>
    internal virtual (int Start, int End) ProgramBounds(IBasicMemory memory) =>
        (BasicProgram.Word(memory, Pointers.ProgramStart), BasicProgram.Word(memory, Pointers.Variables));

    /// <summary>
    ///  Gets memory read by the addresses this BASIC's program and text pointers hold: the CPU's own addresses, or a
    ///  wider space for a BASIC that reaches banked memory.
    /// </summary>
    /// <param name="memory">The memory as the CPU maps it.</param>
    /// <returns>The memory by program addresses.</returns>
    internal virtual IBasicMemory Text(IBasicMemory memory) => memory;

    /// <summary>
    ///  Gets a program's bytes as they lie in memory from its start, the bytes <see cref="ProgramBounds"/> spans.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="start">Where it starts.</param>
    /// <returns>The bytes.</returns>
    internal virtual byte[] MemoryImage(BasicProgram program, int start) => program.ToImage(start);

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
