// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  Reads the p-machine's state at a fetch: the running procedure and the chain of its callers.
/// </summary>
/// <remarks>
///  <para>
///   Each call builds a mark stack control word (MSCW) below the caller's: its static link (the enclosing
///   procedure's MSCW), its dynamic link (the caller's MSCW), the caller's JTAB, SEG and IPC, the 6502 stack pointer,
///   and on the Apple III the X-byte of the caller's code. The frames are read from the registers, then from each
///   MSCW to the one its dynamic link names.
///  </para>
/// </remarks>
public static class PascalMachine
{
    private const int MaximumFrames = 64;

    /// <summary>
    ///  Reads the running procedure and its callers.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="interpreter">The interpreter.</param>
    /// <returns>The frames, the running procedure first; empty when the registers do not make sense.</returns>
    public static IReadOnlyList<PascalFrame> Frames(IPascalMemory memory, PascalInterpreter interpreter) =>
        Frames(memory, interpreter, PascalRegisters.Read(memory, interpreter));

    /// <summary>
    ///  Reads the running procedure, from registers read earlier, and its callers.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="interpreter">The interpreter.</param>
    /// <param name="registers">The registers, as they were at a fetch.</param>
    /// <returns>The frames, the running procedure first; empty when the registers do not make sense.</returns>
    public static IReadOnlyList<PascalFrame> Frames(IPascalMemory memory, PascalInterpreter interpreter, PascalRegisters registers)
    {
        ArgumentNullException.ThrowIfNull(memory);
        ArgumentNullException.ThrowIfNull(interpreter);
        ArgumentNullException.ThrowIfNull(registers);
        List<PascalFrame> frames = [];
        PascalPointer mark = registers.Mark;
        PascalPointer table = registers.JumpTable;
        PascalPointer segment = registers.Segment;
        PascalPointer code = registers.Code;
        HashSet<ushort> seen = [];
        while (frames.Count < MaximumFrames && seen.Add(mark.Address))
        {
            if (Frame(memory, segment, table, code, mark) is not { } frame) { break; }
            frames.Add(frame);

            // The caller's code shares an X-byte, which the MSCW keeps beside the 6502 stack pointer; without X-bytes,
            // all code is in the code bank.
            byte bank = interpreter.Extended ? Bank(memory.Read(mark.Plus(11).Address, mark.Bank)) : interpreter.CodeBank;
            table = new PascalPointer(Word(memory, mark.Plus(4)), bank);
            segment = new PascalPointer(Word(memory, mark.Plus(6)), bank);
            code = new PascalPointer(Word(memory, mark.Plus(8)), bank);
            ushort caller = Word(memory, mark.Plus(2));
            if (caller == 0 || caller == mark.Address) { break; }
            mark = new PascalPointer(caller, mark.Bank);
        }

        return frames;
    }

    /// <summary>
    ///  Reads the running procedure only: its segment number, procedure number and offset, as quickly as a check at
    ///  every fetch needs.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="interpreter">The interpreter.</param>
    /// <returns>The procedure, or null when the registers do not make sense.</returns>
    public static PascalFrame? Top(IPascalMemory memory, PascalInterpreter interpreter)
    {
        ArgumentNullException.ThrowIfNull(memory);
        ArgumentNullException.ThrowIfNull(interpreter);
        return Frame(
            memory,
            interpreter.Register(memory, PascalInterpreter.SegmentRegister),
            interpreter.Register(memory, PascalInterpreter.JumpTableRegister),
            interpreter.Register(memory, PascalInterpreter.CodeRegister),
            interpreter.Register(memory, PascalInterpreter.MarkRegister));
    }

    /// <summary>
    ///  Reads a word.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="pointer">Where it is.</param>
    /// <returns>The word, least significant byte first.</returns>
    public static ushort Word(IPascalMemory memory, PascalPointer pointer)
    {
        ArgumentNullException.ThrowIfNull(memory);
        return (ushort)(memory.Read(pointer.Address, pointer.Bank) | (memory.Read((ushort)(pointer.Address + 1), pointer.Bank) << 8));
    }

    /// <summary>
    ///  Reads a procedure's frame from its registers.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="segment">Its SEG.</param>
    /// <param name="table">Its JTAB.</param>
    /// <param name="code">Its IPC.</param>
    /// <param name="mark">Its MP.</param>
    /// <returns>The frame, or null when the attributes do not make sense.</returns>
    public static PascalFrame? Frame(IPascalMemory memory, PascalPointer segment, PascalPointer table, PascalPointer code, PascalPointer mark)
    {
        ArgumentNullException.ThrowIfNull(memory);
        int procedure = memory.Read(table.Address, table.Bank);
        int count = memory.Read((ushort)(segment.Address + 1), segment.Bank);
        if (procedure == 0 || procedure > count || table.Address < 8 || table.Address >= segment.Address)
        {
            return null;
        }

        int level = (sbyte)memory.Read((ushort)(table.Address + 1), table.Bank);
        PascalPointer entryPointer = table.Plus(-2);
        PascalPointer entry = new((ushort)(entryPointer.Address - Word(memory, entryPointer)), table.Bank);
        int offset = (ushort)(code.Address - entry.Address);
        if (offset > table.Address - entry.Address) { return null; }

        int words = (Word(memory, table.Plus(-6)) + Word(memory, table.Plus(-8))) / 2;
        return new PascalFrame(segment, memory.Read(segment.Address, segment.Bank), procedure, level, table, code, entry, offset, mark, words);
    }

    private static byte Bank(byte value) => (value & 0x80) != 0 ? value : (byte)0;
}
