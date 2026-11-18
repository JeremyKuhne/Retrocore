// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  BASIC's variables, arrays and strings in a machine's memory: reading them, changing them, and making new ones,
///  as the interpreter lays them out.
/// </summary>
/// <remarks>
///  <para>
///   AppleSoft keeps each simple variable in seven bytes: two name characters, whose high bits give the type, and
///   five value bytes. Level II keeps a type byte that is also the value's size (2 integer, 3 string, 4 single,
///   8 double), the second name character, the first, and the value. A string's value is its length and address.
///   Arrays follow the simple variables, each with its name, its size, its number of subscripts and the count of
///   each, last subscript first, then its elements with the first subscript varying fastest.
///  </para>
/// </remarks>
public sealed partial class BasicVariables
{
    private const int AppleSoftEntry = 7;
    private const int MaximumEntries = 0x4000;
    private const byte High = 0x80;
    private const int LevelTwoDefaultTypes = 0x4101;
    private const int LevelTwoStackTop = 0x40A0;
    private const int MbasicNameLength = 40;
    private const int MbasicWhileToken = 0xB4;
    private const int MbasicWhileSize = 7;
    private const int StackRoom = 0x100;

    private const string TypeMismatch = "?TYPE MISMATCH: a string variable takes a string, and a numeric one a number.";
    private const string BadName = "is not a variable name.";

    private readonly BasicDialect _dialect;
    private readonly IBasicMemory _memory;

    /// <summary>
    ///  Creates the view of a machine's variables.
    /// </summary>
    /// <param name="dialect">The interpreter.</param>
    /// <param name="memory">The memory.</param>
    public BasicVariables(BasicDialect dialect, IBasicMemory memory)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(memory);
        _dialect = dialect;
        _memory = memory;
    }

    private bool LevelTwo => _dialect == BasicDialect.Level2;

    // MBASIC keeps Level II's types and number formats, but a name's characters past its second follow a count of
    // them, each with bit 7 set, and a FOR entry has a text pointer after its variable.
    private bool Mbasic => _dialect == BasicDialect.Mbasic;

    // Whether numbers are Microsoft's later formats: integers low byte first, floats with the exponent last, and each
    // letter's type set by DEFINT and the others.
    private bool Typed => LevelTwo || Mbasic;

    // Color BASIC keeps AppleSoft's layout, but a string's descriptor has a spare byte before its address, and a
    // string array's elements are five bytes.
    private bool ColorBasic => _dialect is ColorBasicDialect;

    private BasicPointers Pointers => _dialect.Pointers;

    /// <summary>
    ///  Lists the simple variables and functions, in the order BASIC made them.
    /// </summary>
    /// <returns>The variables.</returns>
    public IReadOnlyList<BasicVariable> Simple()
    {
        if (IntegerBasic) { return IntegerSimple(); }
        if (BusinessBasic) { return BusinessSimple(); }
        List<BasicVariable> variables = [];
        int at = Word(Pointers.Variables);
        int end = Word(Pointers.Arrays);
        while (at < end && variables.Count < MaximumEntries)
        {
            if (Mbasic)
            {
                int type = _memory.Read(at);
                if (KindOfType(type) is not { } kind) { break; }
                int header = MbasicHeader(at);

                // GETFNM sets bit 7 of a DEF FN's first character; its value is the definition's text pointer.
                bool function = (_memory.Read(at + 1) & High) != 0;
                variables.Add(new(MbasicName(at, kind), function ? BasicVariableKind.Function : kind, at, at + header));
                at += header + type;
            }
            else if (LevelTwo)
            {
                int type = _memory.Read(at);
                if (KindOfType(type) is not { } kind) { break; }
                string name = Name((char)_memory.Read(at + 2), (char)_memory.Read(at + 1), kind);
                variables.Add(new(name, kind, at, at + 3));
                at += 3 + type;
            }
            else
            {
                (char first, char second, BasicVariableKind kind) = AppleSoftName(
                    _memory.Read(at),
                    _memory.Read(at + 1));

                variables.Add(new(Name(first, second, kind), kind, at, at + 2));
                at += AppleSoftEntry;
            }
        }

        return variables;
    }

    /// <summary>
    ///  Lists the arrays, in the order BASIC made them.
    /// </summary>
    /// <returns>The arrays.</returns>
    public IReadOnlyList<BasicArray> Arrays()
    {
        if (IntegerBasic) { return IntegerArrays(); }
        if (BusinessBasic) { return BusinessArrays(); }
        List<BasicArray> arrays = [];
        int at = Word(Pointers.Arrays);
        int end = Word(Pointers.FreeStart);
        while (at < end && arrays.Count < MaximumEntries)
        {
            BasicVariableKind kind;
            char first;
            char second;
            int header;
            string? full = null;
            if (Mbasic)
            {
                if (KindOfType(_memory.Read(at)) is not { } type) { break; }
                (kind, first, second, header) = (type, (char)_memory.Read(at + 1), (char)_memory.Read(at + 2), MbasicHeader(at));
                full = MbasicName(at, kind);
            }
            else if (LevelTwo)
            {
                if (KindOfType(_memory.Read(at)) is not { } type) { break; }
                (kind, first, second, header) = (type, (char)_memory.Read(at + 2), (char)_memory.Read(at + 1), 3);
            }
            else
            {
                (first, second, kind) = AppleSoftName(_memory.Read(at), _memory.Read(at + 1));
                header = 2;
            }

            int size = Word(at + header);
            int count = _memory.Read(at + header + 2);
            if (size <= 0 || count == 0) { break; }
            int[] dimensions = new int[count];
            for (int index = 0; index < count; index++)
            {
                int field = at + header + 3 + (index * 2);
                int elements = Typed ? Word(field) : (_memory.Read(field) << 8) | _memory.Read(field + 1);

                // The last subscript's count is stored first.
                dimensions[count - 1 - index] = elements;
            }

            int elementsAt = at + header + 3 + (count * 2);
            // MBASIC's arrays start at OPTION BASE, each dimension's count from there.
            int lowerBound = Mbasic ? _memory.Read(MbasicMemory.OPTVAL) : 0;
            arrays.Add(new(full ?? Name(first, second, kind), kind, at, dimensions, elementsAt, ValueSize(kind), lowerBound));

            // AppleSoft's size counts from the array's start; Level II's and MBASIC's from just past the size.
            at += Typed ? header + 2 + size : size;
        }

        return arrays;
    }

    /// <summary>
    ///  Reads a value.
    /// </summary>
    /// <param name="kind">What it holds.</param>
    /// <param name="address">Where its value starts.</param>
    /// <returns>The value; a function reads as zero.</returns>
    public BasicValue Read(BasicVariableKind kind, int address)
    {
        if (IntegerBasic) { return IntegerRead(kind, address); }
        if (BusinessBasic) { return BusinessRead(kind, address); }
        switch (kind)
        {
            case BasicVariableKind.String:
                int length = _memory.Read(address);
                int text = Word(address + (ColorBasic ? 2 : 1));
                byte[] bytes = new byte[length];
                for (int index = 0; index < length; index++) { bytes[index] = _memory.Read((text + index) & 0xFFFF); }
                return BasicValue.Of(bytes);
            case BasicVariableKind.Integer:
                int word = Typed ? Word(address) : (_memory.Read(address) << 8) | _memory.Read(address + 1);
                return new((short)word);
            case BasicVariableKind.Function:
                return new(0);
            default:
                byte[] value = new byte[ValueSize(kind)];
                for (int index = 0; index < value.Length; index++) { value[index] = _memory.Read(address + index); }
                return new(BasicNumbers.ReadFloat(value, exponentFirst: !Typed));
        }
    }

    /// <summary>
    ///  Writes a value: a number in the variable's format, or a string put into string space as BASIC puts one there,
    ///  below the strings already in it.
    /// </summary>
    /// <param name="kind">What the variable holds.</param>
    /// <param name="address">Where its value starts.</param>
    /// <param name="value">The value.</param>
    /// <exception cref="ArgumentException">A string is given for a number, or a number for a string.</exception>
    /// <exception cref="OverflowException">The number does not fit the variable's type.</exception>
    /// <exception cref="InvalidOperationException">String space is full.</exception>
    public void Write(BasicVariableKind kind, int address, BasicValue value)
    {
        if ((kind == BasicVariableKind.String) != value.IsString)
        {
            throw new ArgumentException(TypeMismatch);
        }

        if (IntegerBasic)
        {
            IntegerWrite(kind, address, value);
            return;
        }

        if (BusinessBasic)
        {
            BusinessWrite(kind, address, value);
            return;
        }

        switch (kind)
        {
            case BasicVariableKind.String:
                WriteString(address, value.Text ?? []);
                break;
            case BasicVariableKind.Integer:
                double truncated = Math.Truncate(value.Number);
                if (truncated is < short.MinValue or > short.MaxValue)
                {
                    throw new OverflowException("?ILLEGAL QUANTITY: integers are -32768 to 32767.");
                }

                int integer = (ushort)(short)truncated;
                byte low = (byte)integer;
                byte high = (byte)(integer >> 8);
                Store(address, Typed ? [low, high] : [high, low]);
                break;
            case BasicVariableKind.Function:
                throw new ArgumentException("A function's value cannot be set.");
            default:
                Store(address, BasicNumbers.WriteFloat(value.Number, ValueSize(kind), exponentFirst: !Typed));
                break;
        }
    }

    /// <summary>
    ///  Finds a simple variable by its name as a program writes it, such as <c>SCORE</c> or <c>N$</c>: BASIC
    ///  compares the first two characters and the type.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The variable, or null when BASIC has not made it yet.</returns>
    public BasicVariable? Find(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (IntegerBasic)
        {
            return Simple().FirstOrDefault(variable => variable.Name == name.ToUpperInvariant());
        }

        if (BusinessBasic)
        {
            (string letters, BasicVariableKind type) = BusinessParse(name);
            string full = BusinessName(letters, type);
            return Simple().FirstOrDefault(variable => variable.Name == full && variable.Kind != BasicVariableKind.Function);
        }

        (char first, char second, BasicVariableKind kind) = Parse(name);
        string stored = Mbasic ? MbasicStored(name, kind) : Name(first, second, kind);
        return Simple().FirstOrDefault(variable => variable.Kind == kind && variable.Name == stored);
    }

    /// <summary>
    ///  Finds an array by its name as a program writes it.
    /// </summary>
    /// <param name="name">The name, without its subscripts.</param>
    /// <returns>The array, or null when BASIC has not made it yet.</returns>
    public BasicArray? FindArray(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (IntegerBasic)
        {
            return Arrays().FirstOrDefault(array => array.Name == name.ToUpperInvariant());
        }

        if (BusinessBasic)
        {
            (string letters, BasicVariableKind type) = BusinessParse(name);
            string full = BusinessName(letters, type);
            return Arrays().FirstOrDefault(array => array.Name == full);
        }

        (char first, char second, BasicVariableKind kind) = Parse(name);
        string stored = Mbasic ? MbasicStored(name, kind) : Name(first, second, kind);
        return Arrays().FirstOrDefault(array => array.Kind == kind && array.Name == stored);
    }

    /// <summary>
    ///  Makes a simple variable, zero or empty, at the end of the simple variables, moving the arrays up as BASIC
    ///  does the first time a program uses a variable.
    /// </summary>
    /// <param name="name">The name, as a program writes it.</param>
    /// <returns>The variable.</returns>
    /// <exception cref="InvalidOperationException">There is no room for it.</exception>
    public BasicVariable Create(string name)
    {
        if (Find(name) is { } existing) { return existing; }
        if (IntegerBasic) { return IntegerCreate(name); }
        if (BusinessBasic) { return BusinessCreate(name); }
        (char first, char second, BasicVariableKind kind) = Parse(name);
        byte[] rest = Mbasic ? MbasicRest(name) : [];
        int header = Mbasic ? 4 + rest.Length : LevelTwo ? 3 : 2;
        int size = Typed ? header + ValueSize(kind) : AppleSoftEntry;
        int start = Word(Pointers.Arrays);
        int end = Word(Pointers.FreeStart);
        int limit = LevelTwo ? Word(LevelTwoStackTop) - StackRoom : _dialect.VariableLimit(_memory);
        if (end + size > limit)
        {
            throw new InvalidOperationException("?OUT OF MEMORY: there is no room for another variable.");
        }

        for (int at = end - 1; at >= start; at--) { _memory.Write(at + size, _memory.Read(at)); }
        for (int at = start; at < start + size; at++) { _memory.Write(at, 0); }
        if (Mbasic)
        {
            Store(start, [(byte)ValueSize(kind), (byte)first, (byte)second, (byte)rest.Length, .. rest]);
        }
        else if (LevelTwo)
        {
            Store(start, [(byte)ValueSize(kind), (byte)second, (byte)first]);
        }
        else
        {
            bool integer = kind == BasicVariableKind.Integer;
            bool marked = integer || kind == BasicVariableKind.String;
            Store(start, [(byte)(first | (integer ? High : 0)), (byte)(second | (marked ? High : 0))]);
        }

        BasicProgram.WriteWord(_memory, Pointers.Arrays, start + size);
        BasicProgram.WriteWord(_memory, Pointers.FreeStart, end + size);
        if (LinksStrings) { RelinkArrayStrings(start + size, end + size, size); }
        return new(Mbasic ? MbasicStored(name, kind) : Name(first, second, kind), kind, start, start + header);
    }

    /// <summary>
    ///  Lists the FOR loops in progress on BASIC's stack, most recent first.
    /// </summary>
    /// <param name="stack">The address of the most recent stack entry.</param>
    /// <param name="forSize">The size of a FOR entry.</param>
    /// <param name="gosubSize">
    ///  The size of a GOSUB entry: 5, and in AppleSoft 7, as the return into the statement fetcher stays under it.
    /// </param>
    /// <returns>The loops.</returns>
    public IReadOnlyList<BasicLoop> Loops(int stack, int forSize, int gosubSize)
    {
        if (IntegerBasic) { return IntegerLoops(); }
        if (BusinessBasic) { return BusinessLoops(stack, forSize, gosubSize); }
        List<BasicLoop> loops = [];
        int forToken = _dialect.StackForToken;
        int gosubToken = _dialect.StackGosubToken;
        for (int at = stack, count = 0; at < 0xFFF0 && count < MaximumEntries; count++)
        {
            int token = _memory.Read(at);
            if (token == gosubToken)
            {
                at += gosubSize;
                continue;
            }

            // MBASIC's WHILE entries: the token, two text pointers and the line.
            if (Mbasic && token == MbasicWhileToken)
            {
                at += MbasicWhileSize;
                continue;
            }

            if (token != forToken) { break; }
            loops.Add(Mbasic ? MbasicLoop(at) : LevelTwo ? LevelTwoLoop(at) : AppleSoftLoop(at));
            at += forSize;
        }

        return loops;
    }

    /// <summary>
    ///  Gets the bytes each value of a kind takes.
    /// </summary>
    /// <param name="kind">The kind.</param>
    /// <returns>The size.</returns>
    public int ValueSize(BasicVariableKind kind) => kind switch
    {
        BasicVariableKind.Integer => 2,
        BasicVariableKind.String => ColorBasic ? 5 : 3,
        BasicVariableKind.Single => 4,
        BasicVariableKind.Double or BasicVariableKind.Long => 8,
        BasicVariableKind.Function when BusinessBasic => 6,
        _ => Typed || BusinessBasic ? 4 : 5
    };

    // AppleSoft's FOR entry: the token, the variable, the step unpacked (its top bit set, its sign after it), the
    // limit, the line and the text pointer.
    private BasicLoop AppleSoftLoop(int at)
    {
        byte[] step = new byte[5];
        for (int index = 0; index < step.Length; index++) { step[index] = _memory.Read(at + 3 + index); }
        step[1] &= 0x7F;
        double magnitude = BasicNumbers.ReadFloat(step, exponentFirst: true);
        bool negative = (_memory.Read(at + 8) & High) != 0;
        byte[] limit = new byte[5];
        for (int index = 0; index < limit.Length; index++) { limit[index] = _memory.Read(at + 9 + index); }
        double end = BasicNumbers.ReadFloat(limit, exponentFirst: true);
        return new(Word(at + 1), negative ? -magnitude : magnitude, end, Word(at + 14));
    }

    // Level II's FOR entry: the token, the variable, the step's sign, an integer flag, then a single step and limit,
    // or an unused slot and an integer step and limit; then the line.
    private BasicLoop LevelTwoLoop(int at)
    {
        int variable = Word(at + 1);
        int line = Word(at + 13);
        if ((_memory.Read(at + 4) & High) != 0)
        {
            return new(variable, (short)Word(at + 9), (short)Word(at + 11), line);
        }

        byte[] step = new byte[4];
        byte[] limit = new byte[4];
        for (int index = 0; index < 4; index++)
        {
            step[index] = _memory.Read(at + 5 + index);
            limit[index] = _memory.Read(at + 9 + index);
        }

        double increment = BasicNumbers.ReadFloat(step, exponentFirst: false);
        return new(variable, increment, BasicNumbers.ReadFloat(limit, exponentFirst: false), line);
    }

    // MBASIC's FOR entry: the token, the variable, a text pointer, the step's sign, $FF for an integer loop, then a
    // single step and limit, or an unused slot and an integer step and limit; then the line and the text pointer.
    private BasicLoop MbasicLoop(int at)
    {
        int variable = Word(at + 1);
        int line = Word(at + 15);
        if (_memory.Read(at + 6) == 0xFF)
        {
            return new(variable, (short)Word(at + 11), (short)Word(at + 13), line);
        }

        byte[] step = new byte[4];
        byte[] limit = new byte[4];
        for (int index = 0; index < 4; index++)
        {
            step[index] = _memory.Read(at + 7 + index);
            limit[index] = _memory.Read(at + 11 + index);
        }

        double increment = BasicNumbers.ReadFloat(step, exponentFirst: false);
        return new(variable, increment, BasicNumbers.ReadFloat(limit, exponentFirst: false), line);
    }

    // An MBASIC entry's header: the type, two characters and the count of the rest, then the rest.
    private int MbasicHeader(int at) => 4 + _memory.Read(at + 3);

    // An MBASIC entry's whole name, with its suffix unless its type is its first letter's default; a DEF FN's first
    // character has bit 7 set.
    private string MbasicName(int at, BasicVariableKind kind)
    {
        char first = (char)(_memory.Read(at + 1) & 0x7F);
        char second = (char)_memory.Read(at + 2);
        string rest = new([.. Enumerable.Range(at + 4, _memory.Read(at + 3)).Select(index => (char)(_memory.Read(index) & 0x7F))]);
        return Suffixed(second == '\0' ? first.ToString() : $"{first}{second}{rest}", first, kind);
    }

    // A name as a program writes it, as MBASIC stores it: its first 40 characters in uppercase, with its suffix
    // unless its type is its first letter's default.
    private string MbasicStored(string name, BasicVariableKind kind)
    {
        string letters = Letters(name);
        return Suffixed(letters, letters[0], kind);
    }

    // The characters of a name past its second, as MBASIC stores them, each with bit 7 set.
    private static byte[] MbasicRest(string name)
    {
        string letters = Letters(name);
        return letters.Length <= 2 ? [] : [.. letters[2..].Select(character => (byte)(character | High))];
    }

    // A name's letters, digits and dots, in uppercase, up to MBASIC's 40.
    private static string Letters(string name)
    {
        string upper = name.Trim().ToUpperInvariant().TrimEnd('$', '%', '!', '#');
        return upper.Length > MbasicNameLength ? upper[..MbasicNameLength] : upper;
    }

    private static BasicVariableKind? KindOfType(int type) => type switch
    {
        2 => BasicVariableKind.Integer,
        3 => BasicVariableKind.String,
        4 => BasicVariableKind.Single,
        8 => BasicVariableKind.Double,
        _ => null
    };

    // AppleSoft's two name bytes: their high bits give the type.
    private static (char First, char Second, BasicVariableKind Kind) AppleSoftName(byte first, byte second)
    {
        BasicVariableKind kind = ((first & High) != 0, (second & High) != 0) switch
        {
            (true, true) => BasicVariableKind.Integer,
            (false, true) => BasicVariableKind.String,
            (true, false) => BasicVariableKind.Function,
            _ => BasicVariableKind.Real
        };

        return ((char)(first & 0x7F), (char)(second & 0x7F), kind);
    }

    // A name as BASIC stores it, with its suffix unless its type is the default for its first letter.
    private string Name(char first, char second, BasicVariableKind kind) =>
        Suffixed(second == '\0' ? first.ToString() : $"{first}{second}", first, kind);

    // Letters with their type's suffix, unless the type is the default for the first letter.
    private string Suffixed(string letters, char first, BasicVariableKind kind)
    {
        return kind switch
        {
            BasicVariableKind.Integer when !Defaults(first, kind) => letters + "%",
            BasicVariableKind.String when !Defaults(first, kind) => letters + "$",
            BasicVariableKind.Double when !Defaults(first, kind) => letters + "#",
            BasicVariableKind.Single when !Defaults(first, kind) => letters + "!",
            _ => letters
        };
    }

    // Whether a type is the one Level II's DEFINT, DEFSTR, DEFSNG and DEFDBL give a letter, so its name needs no
    // suffix. AppleSoft's numbers are its only default.
    private bool Defaults(char first, BasicVariableKind kind)
    {
        if (!Typed || first is < 'A' or > 'Z') { return false; }
        return KindOfType(_memory.Read(DefaultTypes + (first - 'A'))) == kind;
    }

    // Splits a name as a program writes it into the two characters BASIC keeps and its type.
    private (char First, char Second, BasicVariableKind Kind) Parse(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        string upper = name.Trim().ToUpperInvariant();
        if (upper.Length == 0 || !char.IsAsciiLetter(upper[0])) { throw new ArgumentException($"'{name}' {BadName}"); }
        char suffix = upper[^1];
        string letters = suffix is '$' or '%' or '!' or '#' ? upper[..^1] : upper;
        if (!letters.All(character => char.IsAsciiLetterOrDigit(character) || (Mbasic && character == '.')))
        {
            throw new ArgumentException($"'{name}' {BadName}");
        }

        BasicVariableKind kind = suffix switch
        {
            '$' => BasicVariableKind.String,
            '%' => BasicVariableKind.Integer,
            '!' when Typed => BasicVariableKind.Single,
            '#' when Typed => BasicVariableKind.Double,
            _ when Typed => DefaultKind(letters[0]),
            _ => BasicVariableKind.Real
        };

        return (letters[0], letters.Length > 1 ? letters[1] : '\0', kind);
    }

    // The type Level II's DEF statements give names starting with a letter.
    private BasicVariableKind DefaultKind(char first) =>
        KindOfType(_memory.Read(DefaultTypes + (first - 'A'))) ?? BasicVariableKind.Single;

    // Where each letter's default type is.
    private int DefaultTypes => Mbasic ? MbasicMemory.DEFTBL : LevelTwoDefaultTypes;

    private void WriteString(int address, byte[] text)
    {
        if (text.Length > byte.MaxValue)
        {
            throw new OverflowException("?STRING TOO LONG: a string holds at most 255 characters.");
        }

        // BASIC 4 marks the string the variable had as garbage, once the new one fits, and gives the new one its link
        // back to the variable.
        bool linked = LinksStrings;
        int place = 0;
        if (text.Length > 0)
        {
            int top = Word(Pointers.StringBottom);
            int bottom = LevelTwo ? Word(LevelTwoStackTop) : _dialect.StringFloorOf(_memory);
            place = top - text.Length - (linked ? 2 : 0);
            if (place < bottom)
            {
                throw new InvalidOperationException(LevelTwo || ColorBasic
                    ? "?OS ERROR: out of string space; CLEAR sets aside more."
                    : "?OUT OF MEMORY: string space is full.");
            }

            if (linked) { MarkGarbage(address); }
            Store(place, text);
            if (linked) { BasicProgram.WriteWord(_memory, place + text.Length, address); }
            BasicProgram.WriteWord(_memory, Pointers.StringBottom, place);
        }
        else if (linked)
        {
            MarkGarbage(address);
        }

        Store(address, ColorBasic
            ? [(byte)text.Length, 0, (byte)(place >> 8), (byte)place]
            : [(byte)text.Length, (byte)place, (byte)(place >> 8)]);
    }

    // BASIC 4: whether strings carry links back to their descriptors.
    private bool LinksStrings => _dialect is PetBasicDialect { LinksStrings: true };

    // STRADJ: where the link of the string a descriptor points at is, or -1 for one that has none: empty, in the
    // program's text or above $8000, below string space, or the disk status.
    private int LinkOf(int descriptor)
    {
        int length = _memory.Read(descriptor);
        int text = Word(descriptor + 1);
        if (length == 0 || text >= 0x8000 || text < Word(Pointers.StringBottom)) { return -1; }

        // The disk status's string has no link, while it has a length: Clear leaves its address behind.
        bool diskStatus = _memory.Read(PetBasicDialect.DiskStatusDescriptor) != 0
            && text == Word(PetBasicDialect.DiskStatusDescriptor + 1);

        return diskStatus ? -1 : text + length;
    }

    // Marks the string a descriptor points at as garbage, as assignment does: its length and 255 for its link.
    private void MarkGarbage(int descriptor)
    {
        int link = LinkOf(descriptor);
        if (link < 0) { return; }
        Store(link, [_memory.Read(descriptor), 0xFF]);
    }

    // GOGO1: after the arrays move up, each string an element of a string array points at links back to where the
    // element is now.
    private void RelinkArrayStrings(int start, int end, int moved)
    {
        for (int array = start; array < end && array + 5 <= end;)
        {
            int size = Word(array + 2);
            if (size < 5) { return; }
            bool strings = (_memory.Read(array) & High) == 0 && (_memory.Read(array + 1) & High) != 0;
            if (strings)
            {
                int elements = array + 5 + (2 * _memory.Read(array + 4));
                for (int element = elements; element + 3 <= array + size; element += 3)
                {
                    int link = LinkOf(element);
                    if (link >= 0) { BasicProgram.WriteWord(_memory, link, Word(link) + moved); }
                }
            }

            array += size;
        }
    }

    private void Store(int address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++) { _memory.Write(address + index, bytes[index]); }
    }

    private int Word(int address) => BasicProgram.Word(_memory, address);
}
