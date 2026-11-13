// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Text;

namespace Retrocore.Basic;

// Integer BASIC's variables: one list from LOMEM up to PV, each its name (characters with bit 7 set, then $40 for a
// string), a display flag below $40, the address of the next variable, and its value. A number's value is 2 bytes,
// low first; DIM makes an array of 2 bytes an element, element 0 first, or a string of characters with bit 7 set
// followed by a byte with bit 7 clear. Its FOR loops are columns in page 1, FORNDX of them.
//
// Apple-1 BASIC's are the same list, but a name is two bytes: the letter shifted left, and the digit, $40 for a
// string, or 0. Its FOR stack's columns are 8 bytes apart, from $0120.
public sealed partial class BasicVariables
{
    private const int ForVariable = 0x0140;
    private const int ForStep = 0x0160;
    private const int ForLine = 0x0180;
    private const int ForLimit = 0x01C0;
    private const int ForColumn = 0x10;
    private const int Apple1ForVariable = 0x0120;
    private const int Apple1ForStep = 0x0130;
    private const int Apple1ForLine = 0x0140;
    private const int Apple1ForLimit = 0x0160;
    private const int Apple1ForColumn = 0x08;
    private const byte StringMark = 0x40;
    private const byte StringEnd = 0x1E;

    private bool IntegerBasic => _dialect is IntegerBasicDialect;

    private bool Apple1Basic => _dialect is IntegerBasicDialect { IsApple1: true };

    // Each variable in the list: its name, where it starts, where its value starts and how many bytes the value has.
    private List<(string Name, bool Text, int Address, int Value, int Size)> IntegerEntries()
    {
        if (Apple1Basic) { return Apple1Entries(); }
        List<(string, bool, int, int, int)> entries = [];
        int at = Word(IntegerBasicDialect.LoMem);
        int end = Word(IntegerBasicDialect.Pv);
        Span<char> buffer = stackalloc char[32];
        while (at < end && entries.Count < MaximumEntries)
        {
            using ValueStringBuilder name = new(buffer);
            int index = at;
            while (index < end && _memory.Read(index) >= High && name.Length < 0x100)
            {
                name.Append((char)(_memory.Read(index) & 0x7F));
                index++;
            }

            bool text = index < end && _memory.Read(index) == StringMark;
            if (text)
            {
                name.Append('$');
                index++;
            }

            int next = Word(index + 1);
            int value = index + 3;
            if (name.Length == 0 || next <= value || next > end) { break; }
            entries.Add((name.ToString(), text, at, value, next - value));
            at = next;
        }

        return entries;
    }

    // Apple-1 BASIC's list: two name bytes, the next variable's address, then the value.
    private List<(string Name, bool Text, int Address, int Value, int Size)> Apple1Entries()
    {
        List<(string, bool, int, int, int)> entries = [];
        int at = Word(IntegerBasicDialect.LoMem);
        int end = Word(IntegerBasicDialect.Pv);
        while (at + 4 <= end && entries.Count < MaximumEntries)
        {
            char letter = (char)(_memory.Read(at) >> 1);
            byte second = _memory.Read(at + 1);
            bool text = second == StringMark;
            int next = Word(at + 2);
            int value = at + 4;
            if (!char.IsAsciiLetterUpper(letter) || next < value || next > end) { break; }
            string name = text ? $"{letter}$" : second >= High ? $"{letter}{(char)(second & 0x7F)}" : $"{letter}";
            entries.Add((name, text, at, value, next - value));
            at = next;
        }

        return entries;
    }

    // The simple variables: numbers of 2 bytes, and every string.
    private List<BasicVariable> IntegerSimple() =>
        [.. IntegerEntries()
            .Where(entry => entry.Text || entry.Size == 2)
            .Select(entry => new BasicVariable(
                entry.Name,
                entry.Text ? BasicVariableKind.String : BasicVariableKind.Integer,
                entry.Address,
                entry.Value))];

    // The arrays: numbers DIM made more than one element, A(0) to A(n).
    private List<BasicArray> IntegerArrays() =>
        [.. IntegerEntries()
            .Where(entry => !entry.Text && entry.Size > 2)
            .Select(entry => new BasicArray(
                entry.Name,
                BasicVariableKind.Integer,
                entry.Address,
                [entry.Size / 2],
                entry.Value,
                ElementSize: 2))];

    // A number, low byte first, or a string's characters up to the byte with bit 7 clear.
    private BasicValue IntegerRead(BasicVariableKind kind, int address)
    {
        if (kind != BasicVariableKind.String) { return new((short)Word(address)); }
        List<byte> text = [];
        for (int at = address; text.Count < 0x100; at++)
        {
            byte value = _memory.Read(at & 0xFFFF);
            if (value < High) { break; }
            text.Add((byte)(value & 0x7F));
        }

        return BasicValue.Of([.. text]);
    }

    // Writes a number, or a string within the room DIM gave it.
    private void IntegerWrite(BasicVariableKind kind, int address, BasicValue value)
    {
        if (kind != BasicVariableKind.String)
        {
            double truncated = Math.Truncate(value.Number);
            if (truncated is < -32767 or > 32767)
            {
                throw new OverflowException("*** >32767 ERR: numbers are -32767 to 32767.");
            }

            int integer = (ushort)(short)truncated;
            Store(address, [(byte)integer, (byte)(integer >> 8)]);
            return;
        }

        // The room is the next variable's address, just before the value, less the value's, less the ending byte.
        int room = Word(address - 2) - address - 1;
        byte[] text = value.Text ?? [];
        if (text.Length > room)
        {
            throw new InvalidOperationException($"*** STR OVFL ERR: the string has room for {room} characters.");
        }

        byte[] stored = new byte[text.Length + 1];
        for (int index = 0; index < text.Length; index++) { stored[index] = (byte)(text[index] | High); }
        stored[^1] = StringEnd;
        Store(address, stored);
    }

    // Makes a variable as Integer BASIC does the first time a program names it: at PV, its value 2 bytes of zero.
    private BasicVariable IntegerCreate(string name)
    {
        string upper = name.ToUpperInvariant();
        bool text = upper.EndsWith('$');
        string letters = text ? upper[..^1] : upper;
        if (letters.Length == 0 || !char.IsAsciiLetter(letters[0]) || !letters.All(char.IsAsciiLetterOrDigit))
        {
            throw new ArgumentException($"'{name}' {BadName}");
        }

        if (Apple1Basic) { return Apple1Create(upper, letters, text); }
        int start = Word(IntegerBasicDialect.Pv);
        List<byte> entry = [.. letters.Select(character => (byte)(character | High))];
        if (text) { entry.Add(StringMark); }
        entry.Add(0);
        int value = start + entry.Count + 2;
        entry.Add((byte)(value + 2));
        entry.Add((byte)((value + 2) >> 8));
        entry.AddRange(text ? [StringEnd, 0] : [0, 0]);
        if (start + entry.Count > Word(IntegerBasicDialect.Pp))
        {
            throw new InvalidOperationException("*** MEM FULL ERR: there is no room for another variable.");
        }

        Store(start, [.. entry]);
        BasicProgram.WriteWord(_memory, IntegerBasicDialect.Pv, start + entry.Count);
        return new(upper, text ? BasicVariableKind.String : BasicVariableKind.Integer, start, value);
    }

    // Makes a variable as Apple-1 BASIC does: its 6-byte entry at PV, with a value of zero. A name is a letter and a
    // digit at most.
    private BasicVariable Apple1Create(string upper, string letters, bool text)
    {
        if (letters.Length > 2 || (letters.Length == 2 && !char.IsAsciiDigit(letters[1])) || (text && letters.Length != 1))
        {
            throw new ArgumentException($"'{upper}' is not an Apple-1 BASIC name: a letter, then a digit or $.");
        }

        int start = Word(IntegerBasicDialect.Pv);
        int value = start + 4;
        int next = value + 2;
        byte second = text ? StringMark : letters.Length == 2 ? (byte)(letters[1] | High) : (byte)0;
        if (next > Word(IntegerBasicDialect.Pp))
        {
            throw new InvalidOperationException("*** MEM FULL ERR: there is no room for another variable.");
        }

        Store(start, [(byte)((letters[0] | High) << 1), second, (byte)next, (byte)(next >> 8), 0, 0]);
        BasicProgram.WriteWord(_memory, IntegerBasicDialect.Pv, next);
        return new(upper, text ? BasicVariableKind.String : BasicVariableKind.Integer, start, value);
    }

    // The FOR loops in progress, most recent first, from the columns in page 1.
    private List<BasicLoop> IntegerLoops()
    {
        bool apple1 = Apple1Basic;
        int column = apple1 ? Apple1ForColumn : ForColumn;
        int variableAt = apple1 ? Apple1ForVariable : ForVariable;
        int stepAt = apple1 ? Apple1ForStep : ForStep;
        int lineAt = apple1 ? Apple1ForLine : ForLine;
        int limitAt = apple1 ? Apple1ForLimit : ForLimit;
        List<BasicLoop> loops = [];
        int count = Math.Min((int)_memory.Read(IntegerBasicDialect.ForIndex), column);
        for (int index = count - 1; index >= 0; index--)
        {
            int variable = Pair(variableAt, column, index);
            short step = (short)Pair(stepAt, column, index);
            short limit = (short)Pair(limitAt, column, index);
            int line = Word(Pair(lineAt, column, index) + 1);
            loops.Add(new(variable, step, limit, line));
        }

        return loops;
    }

    // An entry of a page-1 column pair: its low byte at low + index, its high byte a column later.
    private int Pair(int low, int column, int index) => _memory.Read(low + index) | (_memory.Read(low + column + index) << 8);
}
