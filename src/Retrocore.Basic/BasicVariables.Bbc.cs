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

    // The longest name read from a block or made: longer than any a line can hold.
    private const int BbcLongestName = 255;

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
                for (int length = 1; length < BbcLongestName && _memory.Read(at) is byte character and not 0; length++, at++)
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
                return BasicValue.OfLong(BbcWord32(address));    // an integer, &80000000 included, not a real
            case BasicVariableKind.String:
                int text = Word(address);
                int length = _memory.Read(address + 3);
                byte[] bytes = new byte[length];
                for (int index = 0; index < length; index++) { bytes[index] = _memory.Read((text + index) & 0xFFFF); }
                return BasicValue.Of(bytes);
            default:
                byte[] real = new byte[BbcReal];
                for (int index = 0; index < real.Length; index++) { real[index] = _memory.Read(address + index); }
                return new(ReadBbcReal(real));
        }
    }

    /// <summary>
    ///  Reads a packed BBC BASIC real: the exponent around &amp;80, then the mantissa, top byte first, its top bit the
    ///  sign.
    /// </summary>
    /// <param name="bytes">The five bytes.</param>
    /// <returns>The real.</returns>
    /// <remarks>
    ///  <para>
    ///   Only five zero bytes are zero: exponent 0 with a mantissa is a real, from 2^-129 up.
    ///  </para>
    /// </remarks>
    internal static double ReadBbcReal(ReadOnlySpan<byte> bytes)
    {
        if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 && bytes[4] == 0) { return 0; }
        uint mantissa = ((uint)(bytes[1] | 0x80) << 24) | ((uint)bytes[2] << 16) | ((uint)bytes[3] << 8) | bytes[4];
        double value = Math.ScaleB(mantissa, bytes[0] - 0x80 - 32);
        return (bytes[1] & 0x80) != 0 ? -value : value;
    }

    /// <summary>
    ///  Packs a real as BASIC II does: its mantissa rounded by the ROM's rounding byte, and zero below 2^-129, where
    ///  the exponent would go below 0.
    /// </summary>
    /// <param name="value">The real.</param>
    /// <returns>Its five bytes.</returns>
    /// <exception cref="OverflowException">The real is too big for BBC BASIC.</exception>
    internal static byte[] PackBbcReal(double value)
    {
        // NaN and infinity have no packed form; they are too big, not a garbage exponent.
        if (!double.IsFinite(value))
        {
            throw new OverflowException("Too big: a real variable holds less than 1.7E38.");
        }

        double rounded = value == 0 ? 0 : BbcBasicExpression.RoundMantissa(value);
        if (rounded == 0 || Math.Abs(rounded) < Math.ScaleB(1.0, -129)) { return new byte[BbcReal]; }
        int exponent = Math.ILogB(rounded) + 1 + 0x80;
        if (exponent > 0xFF)
        {
            throw new OverflowException("Too big: a real variable holds less than 1.7E38.");
        }

        uint mantissa = (uint)Math.ScaleB(Math.Abs(rounded), 32 - (exponent - 0x80));
        byte top = (byte)(((mantissa >> 24) & 0x7F) | (rounded < 0 ? 0x80u : 0));
        return [(byte)exponent, top, (byte)(mantissa >> 16), (byte)(mantissa >> 8), (byte)mantissa];
    }

    private void BbcWrite(BasicVariableKind kind, int address, BasicValue value)
    {
        switch (kind)
        {
            case BasicVariableKind.Integer:
                // An integer goes in as it is; a real is truncated, and one of 2^31 or more in size, -2^31 included,
                // is too big, as BASIC's assignment has it.
                bool fits = value.Long is long whole
                    ? whole is >= int.MinValue and <= int.MaxValue
                    : Math.Abs(value.Number) < BbcBasicExpression.TwoToThe31;

                if (!fits)
                {
                    throw new OverflowException("Too big: an integer variable holds -2147483648 to 2147483647.");
                }

                int integer = value.Long is long exact ? (int)exact : (int)Math.Truncate(value.Number);
                Store(address, [(byte)integer, (byte)(integer >> 8), (byte)(integer >> 16), (byte)(integer >> 24)]);
                break;
            case BasicVariableKind.String:
                BbcWriteString(address, value.Text ?? []);
                break;
            default:
                Store(address, PackBbcReal(value.Number));
                break;
        }
    }

    // A string goes where it is when it fits the bytes allocated to it, as BASIC's assignment does. Otherwise, as
    // ASSIGN_STRING does, it gets room at the top of the heap, below BASIC's stack: its own room grown in place when
    // that is already at the top, or new room. A string of eight or more characters gets eight bytes to spare.
    private void BbcWriteString(int address, byte[] text)
    {
        const int Spare = 8;
        if (text.Length > 255)
        {
            throw new ArgumentException("String too long: a string holds at most 255 characters.");
        }

        int start = Word(address);
        int allocated = _memory.Read(address + 2);
        if (text.Length > allocated)
        {
            int size = Math.Min(255, text.Length + (text.Length >= Spare ? Spare : 0));
            int heap = Word(BbcBasicDialect.Heap);
            if (allocated == 0 || start + allocated != heap) { start = heap; }
            if (start + size > Word(BbcBasicDialect.BasicStack))
            {
                throw new InvalidOperationException("No room: there is no room on the heap for the string.");
            }

            BasicProgram.WriteWord(_memory, BbcBasicDialect.Heap, start + size);
            BasicProgram.WriteWord(_memory, address, start);
            _memory.Write(address + 2, (byte)size);
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

        if (name.Length > BbcLongestName)
        {
            throw new ArgumentException(
                $"The name is {name.Length} characters long: a variable's name can be at most {BbcLongestName}.");
        }

        // The last block's link, or the list's head, will point at the new block. A list that loops is corrupt, and
        // nothing is made.
        int link = BbcBasicDialect.ListHeads + (2 * name[0]);
        HashSet<int> seen = [];
        while ((Word(link) >> 8) != 0)
        {
            link = Word(link);
            if (!seen.Add(link))
            {
                throw new InvalidOperationException($"The variable list for {name[0]} loops: it is corrupt.");
            }
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
