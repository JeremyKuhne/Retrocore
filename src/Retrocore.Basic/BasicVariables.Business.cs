// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <remarks>
///  <para>
///   Business BASIC keeps its arrays from ARYTAB and its simple variables after them, from VARTAB to STREND, all at
///   flat addresses its banked pointers give. A simple variable is its entry's length, its name in capitals without
///   its type character, a type byte ($00 real, $80 integer, $40 long integer, $FF string, $10 a DEF FN function)
///   and its value: a four-byte real (exponent, then the mantissa high first with the sign in its top bit), an
///   integer or a long integer high byte first, or a string's descriptor. An array is its length (two bytes, low
///   first), its name, its type, its count of subscripts, each subscript's size high byte first, the last first, and
///   its elements, the first subscript varying fastest. A descriptor is the string's length and its distance below
///   HIMEM; three bytes follow each string in string space: a type ($41 a simple variable's, $81 an array element's)
///   and the descriptor's offset from VARTAB or ARYTAB.
///  </para>
/// </remarks>
public sealed partial class BasicVariables
{
    private const byte BusinessReal = 0x00;
    private const byte BusinessInteger = 0x80;
    private const byte BusinessLong = 0x40;
    private const byte BusinessString = 0xFF;
    private const byte BusinessFunction = 0x10;
    private const byte SimpleString = 0x41;
    private const byte ArrayString = 0x81;
    private const int StringInformation = 3;
    private const byte BusinessForToken = 0x81;
    private const byte BusinessGosubToken = 0xBE;

    private bool BusinessBasic => _dialect == BasicDialect.BusinessBasic;

    // The memory by the flat addresses Business BASIC's pointers hold.
    private BusinessBasicMemory Flat => field ??= new(_memory);

    private int Pointer(int pointer) => BusinessBasicDialect.Pointer(_memory, pointer);

    private List<BasicVariable> BusinessSimple()
    {
        List<BasicVariable> variables = [];
        int end = Pointer(Pointers.FreeStart);
        for (int at = Pointer(Pointers.Variables); at < end && variables.Count < MaximumEntries;)
        {
            int length = Flat.Read(at);
            if (BusinessEntry(at + 1, out string name, out byte type) is not { } kind || length < name.Length + 2)
            {
                break;
            }

            variables.Add(new(BusinessName(name, kind), kind, at, at + 2 + name.Length));
            at += length;
        }

        return variables;
    }

    private List<BasicArray> BusinessArrays()
    {
        List<BasicArray> arrays = [];
        int end = Pointer(Pointers.Variables);
        for (int at = Pointer(Pointers.Arrays); at < end && arrays.Count < MaximumEntries;)
        {
            int size = Flat.Read(at) | (Flat.Read(at + 1) << 8);
            if (size == 0) { break; }
            if (BusinessEntry(at + 2, out string name, out _) is { } kind and not BasicVariableKind.Function)
            {
                int header = at + 3 + name.Length;
                int count = Flat.Read(header);
                int[] dimensions = new int[count];
                for (int index = 0; index < count; index++)
                {
                    int field = header + 1 + (index * 2);
                    dimensions[count - 1 - index] = (Flat.Read(field) << 8) | Flat.Read(field + 1);
                }

                arrays.Add(new(BusinessName(name, kind), kind, at, dimensions, header + 1 + (count * 2), ValueSize(kind)));
            }

            at += size;
        }

        return arrays;
    }

    private BasicValue BusinessRead(BasicVariableKind kind, int address)
    {
        switch (kind)
        {
            case BasicVariableKind.String:
                int length = Flat.Read(address);
                int start = Pointer(Pointers.MemoryTop) - (Flat.Read(address + 1) | (Flat.Read(address + 2) << 8));
                byte[] text = new byte[length];
                for (int index = 0; index < length; index++) { text[index] = Flat.Read(start + index); }
                return BasicValue.Of(text);
            case BasicVariableKind.Integer:
                return new((short)((Flat.Read(address) << 8) | Flat.Read(address + 1)));
            case BasicVariableKind.Long:
                long value = 0;
                for (int index = 0; index < 8; index++) { value = (value << 8) | Flat.Read(address + index); }
                return BasicValue.OfLong(value);
            case BasicVariableKind.Function:
                return new(0);
            default:
                byte[] real = new byte[4];
                for (int index = 0; index < real.Length; index++) { real[index] = Flat.Read(address + index); }
                return new(BasicNumbers.ReadFloat(real, exponentFirst: true));
        }
    }

    private void BusinessWrite(BasicVariableKind kind, int address, BasicValue value)
    {
        switch (kind)
        {
            case BasicVariableKind.String:
                BusinessWriteString(address, value.Text ?? []);
                break;
            case BasicVariableKind.Integer:
                double truncated = Math.Truncate(value.Long ?? value.Number);
                if (truncated is < short.MinValue or > short.MaxValue)
                {
                    throw new OverflowException("?OVERFLOW: integers are -32768 to 32767.");
                }

                int integer = (ushort)(short)truncated;
                Flat.Write(address, (byte)(integer >> 8));
                Flat.Write(address + 1, (byte)integer);
                break;
            case BasicVariableKind.Long:
                if (value.Long is null && Math.Abs(value.Number) >= 9.2233720368547758E18)
                {
                    throw new OverflowException("?OVERFLOW: the number is too large for a long integer.");
                }

                long whole = value.Long ?? (long)Math.Truncate(value.Number);
                for (int index = 7; index >= 0; index--, whole >>= 8) { Flat.Write(address + index, (byte)whole); }
                break;
            case BasicVariableKind.Function:
                throw new ArgumentException("A function's value cannot be set.");
            default:
                byte[] real = BasicNumbers.WriteFloat(value.Long ?? value.Number, 4, exponentFirst: true);
                for (int index = 0; index < real.Length; index++) { Flat.Write(address + index, real[index]); }
                break;
        }
    }

    // Puts a string into string space below FRETOP, as BASIC's LET does: the characters, then the type and the
    // descriptor's offset, which the garbage collector follows. The string it replaces, when it is in string space, is
    // marked free, a zero type and its length.
    private void BusinessWriteString(int address, byte[] text)
    {
        if (text.Length > 255)
        {
            throw new ArgumentException("?STRING TOO LONG: a string holds at most 255 characters.");
        }

        int top = Pointer(Pointers.MemoryTop);
        int bottom = Pointer(Pointers.StringBottom);
        int oldLength = Flat.Read(address);
        int oldStart = top - (Flat.Read(address + 1) | (Flat.Read(address + 2) << 8));
        if (oldLength > 0 && oldStart >= bottom && oldStart + oldLength + StringInformation <= top)
        {
            Flat.Write(oldStart + oldLength, 0);
            Flat.Write(oldStart + oldLength + 2, (byte)oldLength);
        }

        if (text.Length == 0)
        {
            for (int index = 0; index < 3; index++) { Flat.Write(address + index, 0); }
            return;
        }

        int start = bottom - text.Length - StringInformation;
        if (start < Pointer(Pointers.FreeStart) || top - start > 0xFFFF)
        {
            throw new InvalidOperationException("?OUT OF MEMORY: there is no room for the string.");
        }

        for (int index = 0; index < text.Length; index++) { Flat.Write(start + index, text[index]); }
        bool element = address >= Pointer(Pointers.Arrays) && address < Pointer(Pointers.Variables);
        int table = Pointer(element ? Pointers.Arrays : Pointers.Variables);
        int offset = (table - address) & 0xFFFF;
        Flat.Write(start + text.Length, element ? ArrayString : SimpleString);
        Flat.Write(start + text.Length + 1, (byte)offset);
        Flat.Write(start + text.Length + 2, (byte)(offset >> 8));
        SetPointer(Pointers.StringBottom, start);

        int distance = top - start;
        Flat.Write(address, (byte)text.Length);
        Flat.Write(address + 1, (byte)distance);
        Flat.Write(address + 2, (byte)(distance >> 8));
    }

    private BasicVariable BusinessCreate(string name)
    {
        (string letters, BasicVariableKind kind) = BusinessParse(name);
        int size = 2 + letters.Length + ValueSize(kind);
        int start = Pointer(Pointers.FreeStart);
        if (start + size > Pointer(Pointers.StringBottom))
        {
            throw new InvalidOperationException("?OUT OF MEMORY: there is no room for another variable.");
        }

        Flat.Write(start, (byte)size);
        for (int index = 0; index < letters.Length; index++) { Flat.Write(start + 1 + index, (byte)letters[index]); }
        Flat.Write(start + 1 + letters.Length, BusinessType(kind));
        for (int index = 0; index < ValueSize(kind); index++) { Flat.Write(start + 2 + letters.Length + index, 0); }
        SetPointer(Pointers.FreeStart, start + size);
        return new(BusinessName(letters, kind), kind, start, start + 2 + letters.Length);
    }

    // The FOR entries on BASIC's stack: FORTK, the type, the variable's offset from its table's start, the step
    // unpacked and its sign, the limit packed, the line, and the text pointer.
    private List<BasicLoop> BusinessLoops(int stack, int forSize, int gosubSize)
    {
        List<BasicLoop> loops = [];
        for (int at = stack, count = 0; at < 0xFFF0 && count < MaximumEntries; count++)
        {
            int token = _memory.Read(at);
            if (token == BusinessGosubToken)
            {
                at += gosubSize;
                continue;
            }

            if (token != BusinessForToken) { break; }
            bool element = (_memory.Read(at + 1) & 1) != 0;
            int offset = _memory.Read(at + 2) | (_memory.Read(at + 3) << 8);
            int table = Pointer(element ? Pointers.Arrays : Pointers.Variables);
            int end = Pointer(element ? Pointers.Variables : Pointers.FreeStart);

            // The offset is the table's start less the address in 16 bits, which loses whether one or two banks of
            // 32K separate them; the address must be in the table.
            int address = table + 0x10000 - offset;
            if (address >= end) { address -= 0x10000; }

            byte[] step = [.. Enumerable.Range(4, 5).Select(index => _memory.Read(at + index))];
            int sign = _memory.Read(at + 9);
            step[1] = (byte)((step[1] & 0x7F) | (sign == 0xFF ? 0x80 : 0));
            byte[] limit = [.. Enumerable.Range(10, 5).Select(index => _memory.Read(at + index))];
            int line = _memory.Read(at + 15) | (_memory.Read(at + 16) << 8);
            loops.Add(new(
                address,
                sign == 0 ? 0 : BasicNumbers.ReadFloat(step, exponentFirst: true),
                BasicNumbers.ReadFloat(limit, exponentFirst: true),
                line));

            at += forSize;
        }

        return loops;
    }

    // A name and type from an entry: the name's capitals, digits and periods, then the type byte.
    private BasicVariableKind? BusinessEntry(int at, out string name, out byte type)
    {
        Span<char> letters = stackalloc char[64];
        for (int index = at, count = 0; count < letters.Length; index++, count++)
        {
            byte value = Flat.Read(index);
            if (!(char.IsAsciiLetterOrDigit((char)value) || value == '.'))
            {
                name = new string(letters[..count]);
                type = value;
                return name.Length == 0 ? null : type switch
                {
                    BusinessReal => BasicVariableKind.Real,
                    BusinessInteger => BasicVariableKind.Integer,
                    BusinessLong => BasicVariableKind.Long,
                    BusinessString => BasicVariableKind.String,
                    BusinessFunction => BasicVariableKind.Function,
                    _ => null
                };
            }

            letters[count] = (char)value;
        }

        name = "";
        type = 0;
        return null;
    }

    private static string BusinessName(string letters, BasicVariableKind kind) => letters + kind switch
    {
        BasicVariableKind.Integer => "%",
        BasicVariableKind.Long => "&",
        BasicVariableKind.String => "$",
        _ => ""
    };

    private static byte BusinessType(BasicVariableKind kind) => kind switch
    {
        BasicVariableKind.Integer => BusinessInteger,
        BasicVariableKind.Long => BusinessLong,
        BasicVariableKind.String => BusinessString,
        _ => BusinessReal
    };

    // A name as a program writes it: a letter, then letters, digits and periods, and a type character.
    private static (string Letters, BasicVariableKind Kind) BusinessParse(string name)
    {
        string text = name.Trim().ToUpperInvariant();
        BasicVariableKind kind = text.Length == 0 ? BasicVariableKind.Real : text[^1] switch
        {
            '%' => BasicVariableKind.Integer,
            '&' => BasicVariableKind.Long,
            '$' => BasicVariableKind.String,
            _ => BasicVariableKind.Real
        };

        string letters = kind == BasicVariableKind.Real ? text : text[..^1];
        bool named = letters.Length is > 0 and < 64
            && char.IsAsciiLetter(letters[0])
            && letters.All(character => char.IsAsciiLetterOrDigit(character) || character == '.');

        if (!named)
        {
            throw new ArgumentException($"'{name}' {BadName}");
        }

        return (letters, kind);
    }

    // Sets one of BASIC's zero-page pointers to a flat address, its X-byte with it.
    private void SetPointer(int pointer, int flat)
    {
        (byte xByte, int address) = BusinessBasicDialect.Split(flat);
        _memory.Write(pointer, (byte)address);
        _memory.Write(pointer + 1, (byte)(address >> 8));
        _memory.Write(pointer - BusinessBasicDialect.XByteOffset, xByte);
    }
}
