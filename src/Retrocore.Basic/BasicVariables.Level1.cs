// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

// Level I BASIC's variables, which are always there: A to Z, four bytes each from $4000 in Level I's floating point;
// A$ and B$, sixteen bytes each at $4070 and $4080, ended by a zero byte when shorter; and A(n), counting down from
// MEMTOP, as many elements as fit above the program (TSTV).
//
// Its FOR loop is kept in LOPVAR and the words before it, and each loop it is inside, and the loop of each GOSUB's
// caller, in the frames PUSHA puts on the Z80's stack: the variable's address, 0 for none, then, for a loop, its
// STEP, limit, line and text pointer. A GOSUB's own frame, from STKGOS, is the previous GOSUB's frame, the calling
// line and the text it returns to.
public sealed partial class BasicVariables
{
    private const int Level1Letters = 26;
    private const int Level1Frame = 10;
    private const int Level1GosubFrame = 6;

    private bool Level1Basic => _dialect is Level1Dialect;

    // A to Z, then A$ and B$.
    private static List<BasicVariable> Level1Simple()
    {
        List<BasicVariable> variables = [with(Level1Letters + 2)];
        for (int letter = 0; letter < Level1Letters; letter++)
        {
            int address = Level1Dialect.VariablesStart + (letter * Level1Dialect.NumberSize);
            variables.Add(new(((char)('A' + letter)).ToString(), BasicVariableKind.Real, address, address));
        }

        for (int index = 0; index < 2; index++)
        {
            int address = Level1Dialect.StringA + (index * Level1Dialect.StringSize);
            variables.Add(new($"{(char)('A' + index)}$", BasicVariableKind.String, address, address));
        }

        return variables;
    }

    // A(n): element 0 just below MEMTOP, each next one four bytes lower, down to the program's end.
    private List<BasicArray> Level1Arrays()
    {
        int top = Word(Level1Dialect.MemoryTop);
        int end = Word(Level1Dialect.TextEnd);
        int count = (top - end) / Level1Dialect.NumberSize;
        if (end < Level1Dialect.ProgramStart || count <= 0) { return []; }
        return
        [
            new BasicArray(
                "A",
                BasicVariableKind.Real,
                top,
                [count],
                top - Level1Dialect.NumberSize,
                ElementSize: -Level1Dialect.NumberSize)
        ];
    }

    private BasicValue Level1Read(BasicVariableKind kind, int address)
    {
        if (kind != BasicVariableKind.String)
        {
            Span<byte> number = stackalloc byte[Level1Dialect.NumberSize];
            for (int index = 0; index < number.Length; index++)
            {
                number[index] = _memory.Read((address + index) & 0xFFFF);
            }

            return new(Level1Numbers.Read(number));
        }

        List<byte> text = [];
        for (int index = 0; index < Level1Dialect.StringSize; index++)
        {
            byte value = _memory.Read(address + index);
            if (value == 0) { break; }
            text.Add(value);
        }

        return BasicValue.Of([.. text]);
    }

    // A number, or a string padded with zero bytes to its sixteen, as STORE_STR_PAD leaves it.
    private void Level1Write(BasicVariableKind kind, int address, BasicValue value)
    {
        if (kind != BasicVariableKind.String)
        {
            Store(address, Level1Numbers.Write(value.Number));
            return;
        }

        byte[] text = value.Text ?? [];
        if (text.Length > Level1Dialect.StringSize)
        {
            throw new InvalidOperationException($"A$ and B$ hold {Level1Dialect.StringSize} characters.");
        }

        if (text.AsSpan().IndexOfAny((byte)0, Level1Dialect.EndOfLine) >= 0)
        {
            throw new ArgumentException("A Level I string cannot hold a zero byte or a carriage return.");
        }

        byte[] stored = new byte[Level1Dialect.StringSize];
        text.CopyTo(stored, 0);
        Store(address, stored);
    }

    private static BasicVariable? Level1Find(string name)
    {
        string upper = name.ToUpperInvariant();
        return Level1Simple().FirstOrDefault(variable => variable.Name == upper);
    }

    // The loop running, then those its FOR's frame and the frames under it keep, as far as they read as frames.
    private List<BasicLoop> Level1Loops(int stack)
    {
        List<BasicLoop> loops = [];
        if (Level1Loop(Level1Dialect.LoopVariable, Level1Dialect.LoopStep, Level1Dialect.LoopLimit, Level1Dialect.LoopLine) is { } running)
        {
            loops.Add(running);
        }

        int gosub = Word(Level1Dialect.GosubFrame);
        for (int at = stack, count = 0; at >= 0x4000 && at < Level1Dialect.ProgramStart && count < MaximumEntries; count++)
        {
            if (at == gosub)
            {
                gosub = Word(at);
                at += Level1GosubFrame;
                continue;
            }

            if (Word(at) == 0)
            {
                at += 2;
                continue;
            }

            if (Level1Loop(at, at + 2, at + 4, at + 6) is not { } loop) { break; }
            loops.Add(loop);
            at += Level1Frame;
        }

        return loops;
    }

    // A loop whose variable is one of A to Z or an element of A(n), and whose line is in the program.
    private BasicLoop? Level1Loop(int variable, int step, int limit, int line)
    {
        int address = Word(variable);
        int end = Word(Level1Dialect.TextEnd);
        bool letter = address >= Level1Dialect.VariablesStart
            && address < Level1Dialect.VariablesStart + (Level1Letters * Level1Dialect.NumberSize)
            && (address - Level1Dialect.VariablesStart) % Level1Dialect.NumberSize == 0;

        bool element = address >= end && address < Word(Level1Dialect.MemoryTop);
        int at = Word(line);
        if (!(letter || element) || at < Level1Dialect.ProgramStart || at >= end) { return null; }
        return new(address, (short)Word(step), (short)Word(limit), Word(at));
    }
}
