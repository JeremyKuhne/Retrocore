// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <remarks>
///  <para>
///   BBC BASIC keeps @% and A% to Z% at &amp;0400, four bytes each, and every other variable in a block on the heap: a
///   two-byte link to the next block in its list (whose high byte is zero at the list's end), the name less its first
///   character, with the % or $ that ends it and the ( that ends an array's, a zero, then the value. Each character a
///   name can start with has a list, whose head is at &amp;0400 plus twice the character. An integer is four bytes,
///   low first; a real five, the exponent first and the sign in the mantissa's top bit; a string's value is its
///   address, the bytes allocated to it and its length. An array's value is a byte, twice its dimensions plus one,
///   then each dimension's number of elements, two bytes, then the elements, the last subscript varying fastest.
///   Names are case-sensitive and kept whole.
///  </para>
/// </remarks>
public sealed partial class BasicVariables
{
    private const int BbcInteger = 4;
    private const int BbcReal = 5;
    private const int BbcString = 4;
    private const int BbcResidents = 27;

    private bool Bbc => _dialect is BbcBasicDialect;

    // The resident integers that are not zero, then each list's variables in the order BASIC made them.
    private List<BasicVariable> BbcSimple()
    {
        List<BasicVariable> variables = [];
        for (int index = 1; index < BbcResidents; index++)
        {
            int address = BbcBasicDialect.ResidentIntegers + (4 * index);
            if (BbcWord32(address) != 0)
            {
                variables.Add(new($"{(char)('@' + index)}%", BasicVariableKind.Integer, address, address));
            }
        }

        foreach ((string name, int block, int value) in BbcBlocks())
        {
            if (name.EndsWith('(')) { continue; }
            variables.Add(new(name, BbcKind(name), block, value));
        }

        return variables;
    }

    private List<BasicArray> BbcArrays()
    {
        List<BasicArray> arrays = [];
        foreach ((string name, int block, int value) in BbcBlocks())
        {
            if (!name.EndsWith('(')) { continue; }
            string bare = name[..^1];
            BasicVariableKind kind = BbcKind(bare);
            int offset = _memory.Read(value);
            int count = (offset - 1) / 2;
            if (count < 1) { continue; }
            int[] dimensions = new int[count];
            for (int index = 0; index < count; index++) { dimensions[index] = Word(value + 1 + (2 * index)); }
            arrays.Add(new(bare, kind, block, dimensions, value + offset, ValueSize(kind), LastFastest: true));
        }

        return arrays;
    }

    // Each variable block, in list order: its whole name, the block's address and its value's.
    private IEnumerable<(string Name, int Block, int Value)> BbcBlocks()
    {
        int count = 0;
        for (int first = '@'; first <= 'z'; first++)
        {
            int link = Word(BbcBasicDialect.ListHeads + (2 * first));
            while ((link >> 8) != 0 && count++ < MaximumEntries)
            {
                System.Text.StringBuilder name = new();
                name.Append((char)first);
                int at = link + 2;
                for (int length = 0; length < 255 && _memory.Read(at) is byte character and not 0; length++, at++)
                {
                    name.Append((char)character);
                }

                yield return (name.ToString(), link, at + 1);
                link = Word(link);
            }
        }
    }

    // A name's kind by its suffix.
    private static BasicVariableKind BbcKind(string name) => name.EndsWith('$')
        ? BasicVariableKind.String
        : name.EndsWith('%') ? BasicVariableKind.Integer : BasicVariableKind.Real;

    private BasicValue BbcRead(BasicVariableKind kind, int address)
    {
        switch (kind)
        {
            case BasicVariableKind.Integer:
                return new(BbcWord32(address));
            case BasicVariableKind.String:
                int text = Word(address);
                int length = _memory.Read(address + 3);
                byte[] bytes = new byte[length];
                for (int index = 0; index < length; index++) { bytes[index] = _memory.Read((text + index) & 0xFFFF); }
                return BasicValue.Of(bytes);
            default:
                byte[] real = new byte[BbcReal];
                for (int index = 0; index < real.Length; index++) { real[index] = _memory.Read(address + index); }
                return new(BasicNumbers.ReadFloat(real, exponentFirst: true));
        }
    }

    private void BbcWrite(BasicVariableKind kind, int address, BasicValue value)
    {
        switch (kind)
        {
            case BasicVariableKind.Integer:
                double truncated = Math.Truncate(value.Number);
                if (truncated is < int.MinValue or > int.MaxValue)
                {
                    throw new OverflowException("Too big: an integer variable holds -2147483648 to 2147483647.");
                }

                int integer = (int)truncated;
                Store(address, [(byte)integer, (byte)(integer >> 8), (byte)(integer >> 16), (byte)(integer >> 24)]);
                break;
            case BasicVariableKind.String:
                BbcWriteString(address, value.Text ?? []);
                break;
            default:
                Store(address, BasicNumbers.WriteFloat(value.Number, BbcReal, exponentFirst: true));
                break;
        }
    }

    // A string goes where it is when it fits the bytes allocated to it, as BASIC's assignment does; otherwise it gets
    // new room at the top of the heap, below BASIC's stack.
    private void BbcWriteString(int address, byte[] text)
    {
        if (text.Length > 255)
        {
            throw new ArgumentException("String too long: a string holds at most 255 characters.");
        }

        int start = Word(address);
        if (text.Length > _memory.Read(address + 2))
        {
            start = Word(BbcBasicDialect.Heap);
            if (start + text.Length > Word(BbcBasicDialect.BasicStack))
            {
                throw new InvalidOperationException("No room: there is no room on the heap for the string.");
            }

            BasicProgram.WriteWord(_memory, BbcBasicDialect.Heap, start + text.Length);
            BasicProgram.WriteWord(_memory, address, start);
            _memory.Write(address + 2, (byte)text.Length);
        }

        for (int index = 0; index < text.Length; index++) { _memory.Write(start + index, text[index]); }
        _memory.Write(address + 3, (byte)text.Length);
    }

    // A resident integer by its name, @% or A% to Z%; null for any other name.
    private static BasicVariable? BbcResident(string name) =>
        name.Length == 2 && name[1] == '%' && name[0] is >= '@' and <= 'Z'
            ? new(name, BasicVariableKind.Integer, ResidentAddress(name[0]), ResidentAddress(name[0]))
            : null;

    private static int ResidentAddress(char letter) => BbcBasicDialect.ResidentIntegers + (4 * (letter - '@'));

    private BasicVariable? BbcFind(string name)
    {
        if (BbcResident(name) is { } resident) { return resident; }
        foreach ((string found, int block, int value) in BbcBlocks())
        {
            if (found == name) { return new(name, BbcKind(name), block, value); }
        }

        return null;
    }

    // Makes a variable as BASIC does the first time a program assigns to it: a block on the heap, linked to the end
    // of its list, with its value zero or empty.
    private BasicVariable BbcCreate(string name)
    {
        // At most one suffix, after a name of its own that does not start with a digit.
        string bare = name.EndsWith('$') || name.EndsWith('%') ? name[..^1] : name;
        bool named = bare.Length != 0
            && !char.IsAsciiDigit(bare[0])
            && bare.All(character => BbcBasicDialect.IsNameCharacter(character));

        if (!named)
        {
            throw new ArgumentException($"{name} {BadName}");
        }

        BasicVariableKind kind = BbcKind(name);
        int size = 2 + (name.Length - 1) + 1 + ValueSize(kind);
        int block = Word(BbcBasicDialect.Heap);
        if (block + size > Word(BbcBasicDialect.BasicStack))
        {
            throw new InvalidOperationException("No room: there is no room on the heap for another variable.");
        }

        for (int at = block; at < block + size; at++) { _memory.Write(at, 0); }
        for (int index = 1; index < name.Length; index++) { _memory.Write(block + 1 + index, (byte)name[index]); }

        // The last block's link, or the list's head, points at the new block.
        int link = BbcBasicDialect.ListHeads + (2 * name[0]);
        while ((Word(link) >> 8) != 0) { link = Word(link); }
        BasicProgram.WriteWord(_memory, link, block);
        BasicProgram.WriteWord(_memory, BbcBasicDialect.Heap, block + size);
        return new(name, kind, block, block + 2 + name.Length);
    }

    // The FOR stack in page five, most recent first: each entry's control variable, its type (an integer's STEP and
    // limit are integers, a real's packed reals) and the statement after the FOR, whose line it is in.
    private List<BasicLoop> BbcLoops()
    {
        List<BasicLoop> loops = [];
        int level = Math.Min((int)_memory.Read(BbcBasicDialect.ForLevel), 10 * BbcBasicDialect.ForEntrySize);
        for (int at = BbcBasicDialect.ForStack + level - BbcBasicDialect.ForEntrySize; at >= BbcBasicDialect.ForStack;
            at -= BbcBasicDialect.ForEntrySize)
        {
            bool real = _memory.Read(at + 2) == BbcReal;
            double step = real ? BbcRead(BasicVariableKind.Real, at + 3).Number : BbcWord32(at + 3);
            double limit = real ? BbcRead(BasicVariableKind.Real, at + 8).Number : BbcWord32(at + 8);

            // The statement after the FOR: after its colon, or the next line's length byte, three past the carriage
            // return that ends the FOR's line.
            int loop = Word(at + 13);
            loops.Add(new(Word(at), step, limit, BbcBasicDialect.LineAt(_memory, loop - 3) ?? 0));
        }

        return loops;
    }

    private int BbcWord32(int address) =>
        _memory.Read(address) | (_memory.Read(address + 1) << 8) | (_memory.Read(address + 2) << 16) | (_memory.Read(address + 3) << 24);
}
