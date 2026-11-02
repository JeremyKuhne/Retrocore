// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Text;

namespace Retrocore.Basic;

// Integer BASIC's variables: one list from LOMEM up to PV, each its name (characters with bit 7 set, then $40 for a
// string), a display flag below $40, the address of the next variable, and its value. A number's value is 2 bytes,
// low first; DIM makes an array of 2 bytes an element, element 0 first, or a string of characters with bit 7 set
// followed by a byte with bit 7 clear. Its FOR loops are columns in page 1, FORNDX of them.
public sealed partial class BasicVariables
{
    private const int ForVariableLow = 0x0140;
    private const int ForVariableHigh = 0x0150;
    private const int ForStepLow = 0x0160;
    private const int ForStepHigh = 0x0170;
    private const int ForLineLow = 0x0180;
    private const int ForLineHigh = 0x0190;
    private const int ForLimitLow = 0x01C0;
    private const int ForLimitHigh = 0x01D0;
    private const byte StringMark = 0x40;
    private const byte StringEnd = 0x1E;

    private bool IntegerBasic => _dialect == BasicDialect.Integer;

    // Each variable in the list: its name, where it starts, where its value starts and how many bytes the value has.
    private List<(string Name, bool Text, int Address, int Value, int Size)> IntegerEntries()
    {
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

    // The FOR loops in progress, most recent first, from the columns in page 1.
    private List<BasicLoop> IntegerLoops()
    {
        List<BasicLoop> loops = [];
        int count = Math.Min((int)_memory.Read(IntegerBasicDialect.ForIndex), 16);
        for (int index = count - 1; index >= 0; index--)
        {
            int variable = Pair(ForVariableLow, ForVariableHigh, index);
            short step = (short)Pair(ForStepLow, ForStepHigh, index);
            short limit = (short)Pair(ForLimitLow, ForLimitHigh, index);
            int line = Word(Pair(ForLineLow, ForLineHigh, index) + 1);
            loops.Add(new(variable, step, limit, line));
        }

        return loops;
    }

    private int Pair(int low, int high, int index) => _memory.Read(low + index) | (_memory.Read(high + index) << 8);
}
