// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  A <c>SOS.DRIVER</c> file: the drivers SOS loads at boot, each relocatable, after a header of the console's
///  character set and keyboard layout.
/// </summary>
/// <remarks>
///  <para>
///   The file starts with <c>SOS DRVR</c>, then the header: a 2-byte count and that many bytes. SOS's loader reads
///   the header at fixed offsets: the number of built-in floppy drives to configure (a word, of which the loader
///   reads the low byte, taking 0 as 1 and more than 4 as 4), a 16-character name it skips, the 1,024-byte
///   character set, another name, and the 256-byte keyboard layout. Then come the drivers. Each driver is a
///   comment, its code assembled at origin 0, and its relocation table, each with a 2-byte length; a comment length
///   of <c>$FFFF</c> ends the file. A driver's code starts with its first device
///   information block (DIB): the link to the next, the entry point, then the device's name as a length and 15
///   characters. The links, offsets in the code, chain the driver's own DIBs. The loader places and links the drivers
///   from the last in the file to the first, linking each driver's last active DIB to the first active DIB of the
///   driver before it in the file.
///  </para>
///  <para>
///   The relocation table lists the offsets, 2 bytes each, of the code's words that hold addresses in the code.
///   SOS adds the driver's load address to each as it moves the driver into place, wherever it finds room: a
///   driver has no fixed address.
///  </para>
/// </remarks>
public sealed class SosDriverFile
{
    /// <summary>
    ///  The size of the header SOS's loader reads: through the end of the keyboard layout.
    /// </summary>
    public const int HeaderSize = CharacterSetOffset + CharacterSetSize + NameSize + KeyboardLayoutSize;

    /// <summary>
    ///  The size of the character set: 128 glyphs of 8 bytes.
    /// </summary>
    public const int CharacterSetSize = 0x400;

    /// <summary>
    ///  The size of the keyboard layout.
    /// </summary>
    public const int KeyboardLayoutSize = 0x100;

    // A field's length as the loader walks the file: below $8000.
    private const int MaxField = 0x7FFF;

    private const int NameSize = 16;
    private const int CharacterSetOffset = 2 + NameSize;
    private const int KeyboardLayoutOffset = CharacterSetOffset + CharacterSetSize + NameSize;
    private const int End = 0xFFFF;

    private static readonly byte[] s_signature = "SOS DRVR"u8.ToArray();

    private readonly byte[] _header;

    private SosDriverFile(byte[] header, IReadOnlyList<SosDriver> drivers)
    {
        _header = header;
        Drivers = drivers;
    }

    /// <summary>
    ///  Gets the header, after its count: the drive count, the character set and the keyboard layout, with their
    ///  names.
    /// </summary>
    public ReadOnlySpan<byte> Header => _header;

    /// <summary>
    ///  Gets the drive count the header asks for, as its word, or 0 when the header is too short to hold it. The
    ///  loader reads only the low byte, and configures 1 drive for 0 and 4 for more than 4.
    /// </summary>
    public int Drives => _header.Length >= 2 ? _header[0] | (_header[1] << 8) : 0;

    /// <summary>
    ///  Gets the character set's name, such as <c>STANDARD</c>, without its padding; empty when the header is too
    ///  short to hold it.
    /// </summary>
    public string CharacterSetName => Name(CharacterSetOffset - NameSize);

    /// <summary>
    ///  Gets the character set: 128 glyphs of 8 rows; empty when the header is too short to hold it.
    /// </summary>
    public ReadOnlySpan<byte> CharacterSet =>
        _header.Length >= HeaderSize ? _header.AsSpan(CharacterSetOffset, CharacterSetSize) : [];

    /// <summary>
    ///  Gets the keyboard layout's name, such as <c>SHOLES</c>, without its padding; empty when the header is too
    ///  short to hold it.
    /// </summary>
    public string KeyboardLayoutName => Name(KeyboardLayoutOffset - NameSize);

    /// <summary>
    ///  Gets the keyboard layout; empty when the header is too short to hold it.
    /// </summary>
    public ReadOnlySpan<byte> KeyboardLayout =>
        _header.Length >= HeaderSize ? _header.AsSpan(KeyboardLayoutOffset, KeyboardLayoutSize) : [];

    /// <summary>
    ///  Gets the drivers, in the file's order.
    /// </summary>
    public IReadOnlyList<SosDriver> Drivers { get; }

    /// <summary>
    ///  Reads a driver file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>Its header and drivers.</returns>
    /// <exception cref="InvalidDataException">The data is not a driver file.</exception>
    public static SosDriverFile Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < 10 || !data[..8].SequenceEqual(s_signature))
        {
            throw new InvalidDataException("A SOS.DRIVER file starts with \"SOS DRVR\".");
        }

        int offset = 8;
        byte[] header = Field(data, ref offset).ToArray();
        List<SosDriver> drivers = [];
        while (offset + 2 <= data.Length && (data[offset] | (data[offset + 1] << 8)) != End)
        {
            string driverComment = Encoding.ASCII.GetString(Field(data, ref offset));
            byte[] code = Field(data, ref offset).ToArray();
            ReadOnlySpan<byte> table = Field(data, ref offset);
            int[] relocations = new int[table.Length / 2];
            for (int index = 0; index < relocations.Length; index++)
            {
                relocations[index] = table[index * 2] | (table[(index * 2) + 1] << 8);
            }

            drivers.Add(new SosDriver(driverComment, code, relocations));
        }

        return new SosDriverFile(header, drivers);
    }

    /// <summary>
    ///  Writes a driver file that <see cref="Read"/> reads back to the same header and drivers.
    /// </summary>
    /// <param name="header">
    ///  The header, after its count: at least <see cref="HeaderSize"/> bytes, such as the SDK's
    ///  <c>Sos/SosDriverHeader.asm</c> assembled, with a drive count of 1-4.
    /// </param>
    /// <param name="drivers">
    ///  The drivers, in the file's order; SOS's loader places and links them from the last to the first.
    /// </param>
    /// <returns>The file's contents.</returns>
    /// <exception cref="ArgumentException">
    ///  The header is short, $8000 bytes or more, or its drive count is not 1-4 (stricter than the loader, which
    ///  takes 0 as 1 and more than 4 as 4); there are no drivers; or a driver's comment is not ASCII, a field is
    ///  $8000 bytes or more, its code is too short for the DIB fields the loader reads along its chain of DIBs, or a
    ///  relocation does not point at a word in its code.
    /// </exception>
    public static byte[] Write(ReadOnlySpan<byte> header, IReadOnlyList<SosDriver> drivers)
    {
        ArgumentNullException.ThrowIfNull(drivers);
        if (header.Length < HeaderSize)
        {
            throw new ArgumentException($"A SOS.DRIVER header is at least {HeaderSize} bytes; this one is {header.Length}.", nameof(header));
        }

        if (header.Length > MaxField)
        {
            throw new ArgumentException("The header is $8000 bytes or more.", nameof(header));
        }

        int count = header[0] | (header[1] << 8);
        if (count is < 1 or > 4)
        {
            throw new ArgumentException($"SOS configures 1-4 built-in drives; the header asks for {count}.", nameof(header));
        }

        if (drivers.Count == 0) { throw new ArgumentException("SOS needs at least one driver.", nameof(drivers)); }

        using MemoryStream file = new();
        file.Write(s_signature);
        WriteField(file, header);
        foreach (SosDriver driver in drivers)
        {
            ArgumentNullException.ThrowIfNull(driver, nameof(drivers));
            if (!Ascii.IsValid(driver.Comment))
            {
                throw new ArgumentException($"The comment of {driver.Name} is not ASCII.", nameof(drivers));
            }

            byte[] comment = Encoding.ASCII.GetBytes(driver.Comment);
            if (driver.Code.Length < DibFlags + 1 || driver.Code.Length > MaxField)
            {
                throw new ArgumentException($"A driver's code is {DibFlags + 1}-{MaxField} bytes; {driver.Name}'s is {driver.Code.Length}.", nameof(drivers));
            }

            CheckDibs(driver);

            if (comment.Length > MaxField || driver.Relocations.Length * 2 > MaxField)
            {
                throw new ArgumentException($"A field of {driver.Name} is $8000 bytes or more.", nameof(drivers));
            }

            byte[] table = new byte[driver.Relocations.Length * 2];
            for (int index = 0; index < driver.Relocations.Length; index++)
            {
                int relocation = driver.Relocations[index];
                if (relocation < 0 || relocation > driver.Code.Length - 2)
                {
                    throw new ArgumentException($"{driver.Name} relocates offset {relocation}, which is not a word in its code.", nameof(drivers));
                }

                table[index * 2] = (byte)relocation;
                table[(index * 2) + 1] = (byte)(relocation >> 8);
            }

            WriteField(file, comment);
            WriteField(file, driver.Code);
            WriteField(file, table);
        }

        file.WriteByte(End & 0xFF);
        file.WriteByte(End >> 8);
        return file.ToArray();
    }

    // A DIB's flags byte, after the link, the entry point, and the name's length and 15 characters, which the loader
    // reads for every DIB in the driver's chain. Bit 7 marks the DIB active; an active DIB with bit 6 set asks for the
    // driver to be page-aligned, for which the loader reads the word at $20 of the driver's code, its first DIB's DCB
    // length.
    private const int DibFlags = 0x14;
    private const int DibActivePageAligned = 0xC0;
    private const int DibDcb = 0x20;

    // Walks the driver's chain of DIBs as SOS's loader does, from the first at the code's start along the links (each
    // an offset in the code) to a link of 0 or one to itself, checking that each DIB's flags, and the DCB length an
    // active page-aligned one makes the loader read, are inside the code.
    private static void CheckDibs(SosDriver driver)
    {
        byte[] code = driver.Code;
        HashSet<int> seen = [];
        for (int dib = 0; seen.Add(dib);)
        {
            if (dib + DibFlags >= code.Length)
            {
                throw new ArgumentException($"{driver.Name} links to a DIB at offset {dib}, which runs past its code.", "drivers");
            }

            if ((code[dib + DibFlags] & DibActivePageAligned) == DibActivePageAligned && code.Length < DibDcb + 2)
            {
                throw new ArgumentException($"{driver.Name} asks to be page-aligned but its code ends before its DCB's length.", "drivers");
            }

            int link = code[dib] | (code[dib + 1] << 8);
            if (link == 0 || link == dib) { break; }
            dib = link;
        }
    }

    private static void WriteField(MemoryStream file, ReadOnlySpan<byte> field)
    {
        file.WriteByte((byte)field.Length);
        file.WriteByte((byte)(field.Length >> 8));
        file.Write(field);
    }

    // A 16-character name in the header, without its trailing spaces.
    private string Name(int offset) =>
        _header.Length >= HeaderSize ? Encoding.ASCII.GetString(_header, offset, NameSize).TrimEnd(' ') : "";

    // A 2-byte length and that many bytes.
    private static ReadOnlySpan<byte> Field(ReadOnlySpan<byte> data, ref int offset)
    {
        if (offset + 2 > data.Length) { throw new InvalidDataException("The driver file ends inside a length."); }
        int length = data[offset] | (data[offset + 1] << 8);
        offset += 2;
        if (offset + length > data.Length) { throw new InvalidDataException("The driver file ends inside a field."); }
        ReadOnlySpan<byte> field = data.Slice(offset, length);
        offset += length;
        return field;
    }
}
