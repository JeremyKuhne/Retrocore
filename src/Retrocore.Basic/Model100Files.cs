// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Text;

namespace Retrocore.Basic;

/// <summary>
///  The files in a Model 100's or Tandy 102's RAM: the directory the menu shows and the file area below it, read and
///  written as the ROM keeps them.
/// </summary>
/// <remarks>
///  <para>
///   The directory at <c>$F962</c> has 27 entries of 11 bytes, a type, the file's address and an eight-character
///   name (six for the name and two for the extension, padded with spaces), and an <c>$FF</c> after them. The file
///   area starts at the bottom of RAM: a <c>$00</c>, the <c>.BA</c> files, then BASIC's unsaved program; the
///   <c>.DO</c> files from the pointer at <c>$FBAE</c>, then the paste buffer; the <c>.CO</c> files from
///   <c>$FBB0</c>; and BASIC's variables from <c>$FBB2</c>.
///  </para>
///  <para>
///   Adding, replacing or removing a file moves every file after it, and the directory's addresses, the region
///   pointers and BASIC's program pointer that point past it move with them, as the ROM's own routines move
///   them. A change to the program BASIC has open, or to a file before it, clears BASIC's variables,
///   strings, DATA pointer and <c>CONT</c>, as typing a line does; one past it keeps them, moving the variables with
///   the files, as the ROM's <c>OPEN</c>, <c>CLOSE</c> and <c>KILL</c> of another file do. A <c>.BA</c> file that
///   moves is linked again for its new address. A <c>FOR</c> loop's frame on BASIC's stack keeps its variable's
///   address, so a change made while a program is stopped inside one leaves <c>CONT</c> unsafe, as on the machine.
///  </para>
/// </remarks>
public sealed class Model100Files
{
    /// <summary>
    ///  The directory's first entry.
    /// </summary>
    public const int Directory = 0xF962;

    /// <summary>
    ///  The number of directory entries.
    /// </summary>
    public const int Entries = 27;

    /// <summary>
    ///  The bytes in a directory entry.
    /// </summary>
    public const int EntrySize = 11;

    /// <summary>
    ///  The bottom of a 32 KB machine's RAM, where its file area starts, and the lowest address any machine has RAM at.
    /// </summary>
    internal const int FileArea = 0x8000;

    /// <summary>
    ///  The bytes left free below the stack top for the stack when files are written.
    /// </summary>
    internal const int StackRoom = 0x100;

    // The directory's types: bit 7 marks a file, bit 3 one the menu hides, and $B0 is the ROM's own programs; a free
    // entry is 0. RickY's $48 is hidden but not a file, and not free either.
    private const byte BasicType = 0x80;
    private const byte TextType = 0xC0;
    private const byte MachineType = 0xA0;
    private const byte InUse = 0x80;
    private const byte Hidden = 0x08;
    private const byte RomType = 0xB0;

    // BASIC's unsaved program and the paste buffer, the hidden entries the regions end with.
    private const int Unsaved = Directory + (5 * EntrySize);
    private const int Paste = Directory + (6 * EntrySize);

    private const int TextStart = 0xFBAE;
    private const int MachineStart = 0xFBB0;
    private const int VariableStart = 0xFBB2;
    private const int ArrayStart = 0xFBB4;
    private const int FreeStart = 0xFBB6;
    private const int ProgramPointer = 0xF67C;
    private const int StackTop = 0xF678;
    private const byte EndOfText = 0x1A;

    private readonly IBasicMemory _memory;

    /// <summary>
    ///  Initializes the file system over a machine's memory.
    /// </summary>
    /// <param name="memory">The memory, read and written without side effects.</param>
    public Model100Files(IBasicMemory memory)
    {
        ArgumentNullException.ThrowIfNull(memory);
        _memory = memory;
    }

    /// <summary>
    ///  Gets the files in RAM, in the directory's order: the menu's own files and the hidden entries are left out.
    /// </summary>
    /// <returns>The files.</returns>
    public IReadOnlyList<Model100File> List()
    {
        List<Model100File> files = [];
        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            byte type = _memory.Read(entry);
            if ((type & InUse) == 0 || (type & Hidden) != 0 || type == RomType) { continue; }
            if (TypeOf(type) is not { } kind) { continue; }
            files.Add(new(EntryName(entry), kind, Word(entry + 1)));
        }

        return files;
    }

    /// <summary>
    ///  Reads a file's bytes as a host file holds them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A <c>.BA</c> file is its linked lines and the zero link, as they lie in RAM; a <c>.DO</c> file its text and
    ///   the <c>$1A</c> after it; a <c>.CO</c> file its six-byte header and its bytes.
    ///  </para>
    /// </remarks>
    /// <param name="name">The file's name and extension, such as <c>PROG.BA</c>; case does not matter.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="FileNotFoundException">There is no such file.</exception>
    /// <exception cref="InvalidDataException">The file in RAM has no end.</exception>
    public byte[] Read(string name)
    {
        Model100File file = Find(name) ?? throw new FileNotFoundException($"There is no {name} in RAM.", name);
        int length = Length(file.Type, file.Address);
        byte[] bytes = new byte[length];
        for (int index = 0; index < length; index++)
        {
            bytes[index] = _memory.Read(file.Address + index);
        }

        return bytes;
    }

    /// <summary>
    ///  Writes a file into RAM, replacing one of the same name, as the ROM's <c>SAVE</c>, <c>SAVEM</c> and text files
    ///  place them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A new file takes the first free directory entry and goes at the end of its kind's region; one that replaces
    ///   another takes its place and entry, so BASIC keeps a program it has open. RAM is changed only once the file
    ///   is known to fit; but a <c>.BA</c> file already in RAM whose lines do not end is found only as the files are
    ///   linked again, after they have moved, which leaves RAM changed.
    ///  </para>
    /// </remarks>
    /// <param name="name">
    ///  The name and extension: up to six letters and digits, the first a letter, then <c>.BA</c>, <c>.DO</c> or
    ///  <c>.CO</c>.
    /// </param>
    /// <param name="bytes">
    ///  The file's bytes, as <see cref="Read"/> gives them. A <c>.BA</c> file is linked again for where it goes; a
    ///  <c>.DO</c> file without a <c>$1A</c> gets one.
    /// </param>
    /// <exception cref="ArgumentException">
    ///  The name is not a Model 100 file's, or a <c>.CO</c> file's length is wrong.
    /// </exception>
    /// <exception cref="InvalidDataException">A <c>.BA</c> file's lines do not end.</exception>
    /// <exception cref="InvalidOperationException">The directory is full, or RAM has no room.</exception>
    public void Write(string name, ReadOnlySpan<byte> bytes)
    {
        (string stem, Model100FileType type) = ParseName(name);
        byte[] contents = Contents(type, bytes);
        if (Find(name) is { } old)
        {
            // In its place, so the directory and BASIC's open program stay as they were.
            if (type == Model100FileType.Basic)
            {
                contents = BasicProgram.FromImage(BasicDialect.Model100, contents).ToImage(old.Address);
            }

            Move(old.Address, Length(type, old.Address), contents, keep: -1);
            return;
        }

        int entry = FreeEntry() ?? throw new InvalidOperationException("The Model 100's directory is full.");

        // .BA files go before BASIC's unsaved program, .DO before the paste buffer and .CO at the end of their region,
        // so each region keeps its own start.
        (int at, int keep) = type switch
        {
            Model100FileType.Basic => (Word(Unsaved + 1), -1),
            Model100FileType.Text => (Word(Paste + 1), TextStart),
            _ => (Word(VariableStart), MachineStart)
        };

        if (type == Model100FileType.Basic)
        {
            contents = BasicProgram.FromImage(BasicDialect.Model100, contents).ToImage(at);
        }

        Move(at, removed: 0, contents, keep);
        _memory.Write(entry, type switch
        {
            Model100FileType.Basic => BasicType,
            Model100FileType.Text => TextType,
            _ => MachineType
        });

        WriteWord(entry + 1, at);
        string padded = stem.PadRight(6) + Extension(type);
        for (int index = 0; index < 8; index++)
        {
            _memory.Write(entry + 3 + index, (byte)padded[index]);
        }
    }

    /// <summary>
    ///  Removes a file from RAM.
    /// </summary>
    /// <param name="name">The file's name and extension.</param>
    /// <exception cref="FileNotFoundException">There is no such file.</exception>
    /// <exception cref="InvalidOperationException">
    ///  BASIC has the file open, which the ROM's <c>KILL</c> refuses too.
    /// </exception>
    /// <exception cref="InvalidDataException">A file in RAM has no end.</exception>
    public void Delete(string name)
    {
        Model100File file = Find(name) ?? throw new FileNotFoundException($"There is no {name} in RAM.", name);
        if (file.Type == Model100FileType.Basic && Word(ProgramPointer) == file.Address)
        {
            throw new InvalidOperationException($"BASIC has {file.Name} open, and the ROM's KILL refuses it too; open another program first.");
        }

        int entry = EntryOf(file.Address);
        for (int index = 0; index < EntrySize; index++) { _memory.Write(entry + index, 0); }
        Move(file.Address, Length(file.Type, file.Address), [], keep: -1);
    }

    /// <summary>
    ///  Tests whether an address is a BASIC program's: a <c>.BA</c> file's or BASIC's unsaved program's.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether a directory entry for one has it.</returns>
    internal bool HoldsProgram(int address)
    {
        if (address < FileArea) { return false; }
        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            byte type = _memory.Read(entry);
            if ((type == BasicType || entry == Unsaved) && Word(entry + 1) == address) { return true; }
        }

        return false;
    }

    /// <summary>
    ///  Gets the first byte past a BASIC program, past its zero link.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="start">The program's first line.</param>
    /// <returns>The address.</returns>
    internal static int BasicEnd(IBasicMemory memory, int start)
    {
        int address = start;
        while (address < 0xFFFE)
        {
            int link = BasicProgram.Word(memory, address);
            if (link == 0) { return address + 2; }

            // Links are not trusted: a line ends at its zero byte.
            int at = address + 4;
            while (at < 0xFFFF && memory.Read(at) != 0) { at++; }
            address = at + 1;
        }

        throw new InvalidDataException($"The program at ${start:X4} has no end.");
    }

    /// <summary>
    ///  Replaces a run of the file area with other bytes, moving what follows and the pointers past it.
    /// </summary>
    /// <param name="at">The run's first byte.</param>
    /// <param name="length">Its bytes.</param>
    /// <param name="bytes">What replaces it.</param>
    /// <exception cref="InvalidOperationException">RAM has no room.</exception>
    internal void Replace(int at, int length, ReadOnlySpan<byte> bytes) => Move(at, length, bytes, keep: -1);

    private void Move(int at, int removed, ReadOnlySpan<byte> inserted, int keep)
    {
        int delta = inserted.Length - removed;
        // Strings live above the stack top, between it and the memory top, and the stack grows down from it, so the
        // stack's room below the stack top bounds the files and variables, kept strings or not.
        int end = Word(FreeStart);
        if (end + delta > Word(StackTop) - StackRoom)
        {
            throw new InvalidOperationException(
                $"RAM has {Word(StackTop) - StackRoom - end} bytes free; {delta} more are needed.");
        }

        // The words that move: those pointing past the run, or at it when nothing is removed, but for the start of
        // the region a file is added to, which is then the new file's.
        int from = at + removed;
        List<int> moved = [];
        void Check(int word)
        {
            int address = Word(word);
            if (address >= FileArea && address >= from && (removed > 0 || address > at || word != keep))
            {
                moved.Add(word);
            }
        }

        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            if ((_memory.Read(entry) & InUse) != 0 && _memory.Read(entry) != RomType)
            {
                Check(entry + 1);
            }
        }

        // A change to BASIC's open program, or before it, moves its text, which string variables set from a literal
        // point into, so they are cleared, as typing a line clears them; one past it moves the variables with the
        // files, as OPEN, CLOSE and KILL of another file leave them. With no program open, they are cleared.
        bool clears;
        try
        {
            int program = Word(ProgramPointer);
            clears = !HoldsProgram(program) || at < BasicEnd(_memory, program);
        }
        catch (InvalidDataException)
        {
            clears = true;
        }

        int[] pointers = clears
            ? [ProgramPointer, TextStart, MachineStart, VariableStart]
            : [ProgramPointer, TextStart, MachineStart, VariableStart, ArrayStart, FreeStart];

        foreach (int pointer in pointers)
        {
            Check(pointer);
        }

        // Shift the rest of the file area, then put the bytes in.
        if (delta > 0)
        {
            for (int address = end - 1; address >= from; address--)
            {
                _memory.Write(address + delta, _memory.Read(address));
            }
        }
        else if (delta < 0)
        {
            for (int address = from; address < end; address++)
            {
                _memory.Write(address + delta, _memory.Read(address));
            }
        }

        for (int index = 0; index < inserted.Length; index++)
        {
            _memory.Write(at + index, inserted[index]);
        }

        foreach (int word in moved) { WriteWord(word, Word(word) + delta); }

        if (delta != 0) { Relink(); }
        if (clears) { Model100Dialect.Instance.Clear(_memory); }
    }

    // Links each .BA file and BASIC's unsaved program for where it now is.
    private void Relink()
    {
        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            byte type = _memory.Read(entry);
            if ((type & InUse) == 0 || (type & 0x60) != 0 || type == RomType) { continue; }
            int address = Word(entry + 1);
            if (address < FileArea) { continue; }
            while (true)
            {
                if (Word(address) == 0) { break; }
                int at = address + 4;
                while (_memory.Read(at) != 0)
                {
                    if (++at > 0xFFFF)
                    {
                        throw new InvalidDataException($"The program at ${address:X4} has a line with no end.");
                    }
                }

                WriteWord(address, at + 1);
                address = at + 1;
            }
        }
    }

    private static byte[] Contents(Model100FileType type, ReadOnlySpan<byte> bytes)
    {
        switch (type)
        {
            case Model100FileType.Basic:
                return [.. BasicProgram.FromImage(BasicDialect.Model100, bytes).ToImage(FileArea + 1)];
            case Model100FileType.Text:
                int end = bytes.IndexOf(EndOfText);
                ReadOnlySpan<byte> text = end < 0 ? bytes : bytes[..end];
                return [.. text, EndOfText];
            default:
                if (bytes.Length < 6 || bytes[2] + (bytes[3] << 8) != bytes.Length - 6)
                {
                    throw new ArgumentException("A .CO file is its start, length and entry, two bytes each, then that many bytes.", nameof(bytes));
                }

                return bytes.ToArray();
        }
    }

    private int Length(Model100FileType type, int address)
    {
        switch (type)
        {
            case Model100FileType.Basic:
                return BasicEnd(_memory, address) - address;
            case Model100FileType.Text:
                int at = address;
                while (_memory.Read(at) != EndOfText)
                {
                    if (++at > 0xFFFF)
                    {
                        throw new InvalidDataException($"The text file at ${address:X4} has no end.");
                    }
                }

                return at + 1 - address;
            default:
                return 6 + Word(address + 2);
        }
    }

    private Model100File? Find(string name)
    {
        (string stem, Model100FileType type) = ParseName(name);
        string wanted = $"{stem}.{Extension(type)}";
        return List().FirstOrDefault(file => string.Equals(file.Name, wanted, StringComparison.Ordinal));
    }

    private int EntryOf(int address)
    {
        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            if ((_memory.Read(entry) & InUse) != 0 && Word(entry + 1) == address) { return entry; }
        }

        throw new InvalidDataException($"No directory entry has ${address:X4}.");
    }

    private int? FreeEntry()
    {
        for (int entry = Directory; entry < Directory + (Entries * EntrySize); entry += EntrySize)
        {
            if (_memory.Read(entry) == 0) { return entry; }
        }

        return null;
    }

    private string EntryName(int entry)
    {
        using ValueStringBuilder builder = new(stackalloc char[9]);
        for (int index = 0; index < 6; index++)
        {
            builder.Append((char)_memory.Read(entry + 3 + index));
        }

        builder.Append('.');
        builder.Append((char)_memory.Read(entry + 9));
        builder.Append((char)_memory.Read(entry + 10));
        return builder.ToString().Replace(" ", "", StringComparison.Ordinal);
    }

    private static Model100FileType? TypeOf(byte type) => type switch
    {
        BasicType => Model100FileType.Basic,
        TextType => Model100FileType.Text,
        MachineType => Model100FileType.Machine,
        _ => null
    };

    private static string Extension(Model100FileType type) => type switch
    {
        Model100FileType.Basic => "BA",
        Model100FileType.Text => "DO",
        _ => "CO"
    };

    /// <summary>
    ///  Splits a file name into its six-character stem and its kind.
    /// </summary>
    /// <param name="name">The name and extension.</param>
    /// <returns>The stem in capitals and the kind.</returns>
    /// <exception cref="ArgumentException">The name is not a Model 100 file's.</exception>
    public static (string Stem, Model100FileType Type) ParseName(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        string upper = name.ToUpperInvariant();
        int dot = upper.LastIndexOf('.');
        Model100FileType? type = dot < 0 ? null : upper[(dot + 1)..] switch
        {
            "BA" => Model100FileType.Basic,
            "DO" => Model100FileType.Text,
            "CO" => Model100FileType.Machine,
            _ => null
        };

        string stem = dot < 0 ? upper : upper[..dot];
        if (type is null || stem.Length is 0 or > 6 || !char.IsAsciiLetterUpper(stem[0]) || !stem.All(char.IsAsciiLetterOrDigit))
        {
            throw new ArgumentException(
                $"{name} is not a Model 100 file name: up to six letters and digits, the first a letter, then .BA, .DO or .CO.", nameof(name));
        }

        return (stem, type.Value);
    }

    private int Word(int address) => BasicProgram.Word(_memory, address);

    private void WriteWord(int address, int value) => BasicProgram.WriteWord(_memory, address, value);
}
