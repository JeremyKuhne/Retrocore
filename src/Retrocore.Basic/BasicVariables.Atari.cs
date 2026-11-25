// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

// Atari BASIC's variables: their names in the variable name table from VNTP, and their eight-byte entries in the value
// table from VVTP, in the same order. An entry is a type byte ($00 a number, $80 a string, $40 an array, bit 0 set once
// DIMensioned), the variable's number and six bytes: a number's value, or a string's or an array's offset from STARP
// and its sizes, a string's length then its DIMensioned room, an array's two subscript counts (one more than DIM's).
// An array's elements are six-byte numbers, its second subscript varying fastest. Its FOR loops and GOSUBs are on the
// run-time stack from RUNSTK up to BASIC's MEMTOP: each a four-byte header, its token (a FOR's variable's, 0 for a
// GOSUB), its line's number and its statement's offset, a FOR's above its limit and step.
public sealed partial class BasicVariables
{
    private const byte AtariString = 0x80;
    private const byte AtariArray = 0x40;
    private const byte AtariDimensioned = 0x01;
    private const int AtariHeader = 4;
    private const int AtariForValues = 12;

    private bool AtariBasic => _dialect is AtariBasicDialect;

    // The entries: each name with its type and the address of its value table entry.
    private List<(string Name, byte Type, int Entry)> AtariEntries()
    {
        List<(string, byte, int)> entries = [];
        int at = Word(AtariBasicDialect.Vntp);
        int end = Word(AtariBasicDialect.Vntd);
        int value = Word(AtariBasicDialect.Vvtp);
        int limit = Word(AtariBasicDialect.Stmtab);
        Span<char> name = stackalloc char[256];
        int length = 0;
        while (at < end && entries.Count < 128 && value + AtariBasicDialect.ValueSize <= limit && length < name.Length)
        {
            byte character = _memory.Read(at++);
            name[length++] = (char)(character & 0x7F);
            if ((character & High) == 0) { continue; }
            entries.Add((new string(name[..length]), _memory.Read(value), value));
            length = 0;
            value += AtariBasicDialect.ValueSize;
        }

        return entries;
    }

    private List<BasicVariable> AtariSimple() =>
        [.. AtariEntries()
            .Where(entry => (entry.Type & AtariArray) == 0)
            .Select(entry => new BasicVariable(
                entry.Name,
                (entry.Type & AtariString) != 0 ? BasicVariableKind.String : BasicVariableKind.Real,
                entry.Entry,
                entry.Entry + 2))];

    // The DIMensioned arrays; an array not yet DIMensioned has no elements.
    private List<BasicArray> AtariArrays()
    {
        List<BasicArray> arrays = [];
        int starp = Word(AtariBasicDialect.Starp);
        foreach ((string name, byte type, int entry) in AtariEntries())
        {
            if ((type & AtariArray) == 0 || (type & AtariDimensioned) == 0) { continue; }
            int first = Word(entry + 4);
            int second = Word(entry + 6);
            if (first == 0 || second == 0) { continue; }
            int[] dimensions = second == 1 ? [first] : [first, second];
            arrays.Add(new(
                name.TrimEnd('('),
                BasicVariableKind.Real,
                entry,
                dimensions,
                (starp + Word(entry + 2)) & 0xFFFF,
                AtariNumbers.Size,
                LowerBound: 0,
                LastFastest: true));
        }

        return arrays;
    }

    // A number's six bytes, or a string's characters from its offset, its length long; an undimensioned string is
    // empty.
    private BasicValue AtariRead(BasicVariableKind kind, int address)
    {
        if (kind != BasicVariableKind.String)
        {
            byte[] number = new byte[AtariNumbers.Size];
            for (int index = 0; index < number.Length; index++)
            {
                number[index] = _memory.Read((address + index) & 0xFFFF);
            }

            return new(AtariNumbers.ToDouble(number));
        }

        if ((_memory.Read(address - 2) & AtariDimensioned) == 0) { return BasicValue.Of([]); }
        int text = (Word(AtariBasicDialect.Starp) + Word(address)) & 0xFFFF;
        int length = Math.Min(Word(address + 2), Word(address + 4));
        byte[] bytes = new byte[length];
        for (int index = 0; index < length; index++) { bytes[index] = _memory.Read((text + index) & 0xFFFF); }
        return BasicValue.Of(bytes);
    }

    // A number in its six bytes, or a string within the room DIM gave it.
    private void AtariWrite(BasicVariableKind kind, int address, BasicValue value)
    {
        if (kind != BasicVariableKind.String)
        {
            Store(address, AtariNumbers.FromDouble(value.Number));
            return;
        }

        if ((_memory.Read(address - 2) & AtariDimensioned) == 0)
        {
            throw new InvalidOperationException("ERROR- 9: the string has not been DIMensioned.");
        }

        byte[] text = value.Text ?? [];
        int room = Word(address + 4);
        if (text.Length > room)
        {
            throw new InvalidOperationException($"ERROR- 5: the string has room for {room} characters.");
        }

        Store((Word(AtariBasicDialect.Starp) + Word(address)) & 0xFFFF, text);
        BasicProgram.WriteWord(_memory, address + 2, text.Length);
    }

    // The FOR loops in progress, most recent first, from the top of the run-time stack down.
    private List<BasicLoop> AtariLoops()
    {
        List<BasicLoop> loops = [];
        int bottom = Word(AtariBasicDialect.Runstk);
        int at = Word(AtariBasicDialect.BasicMemtop);
        int vvtp = Word(AtariBasicDialect.Vvtp);
        while (at - AtariHeader >= bottom && loops.Count < MaximumEntries)
        {
            at -= AtariHeader;
            byte token = _memory.Read(at);
            int line = Word(at + 1);
            if (token == 0) { continue; }
            at -= AtariForValues;
            if (at < bottom) { break; }
            double limit = AtariRead(BasicVariableKind.Real, at).Number;
            double step = AtariRead(BasicVariableKind.Real, at + AtariNumbers.Size).Number;
            int variable = vvtp + ((token & 0x7F) * AtariBasicDialect.ValueSize) + 2;
            loops.Add(new(variable, step, limit, line));
        }

        return loops;
    }

    private static bool AtariNamed(string stored, string wanted) =>
        string.Equals(stored, wanted, StringComparison.OrdinalIgnoreCase);
}
