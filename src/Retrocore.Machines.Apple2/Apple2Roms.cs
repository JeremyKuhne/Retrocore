// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Caller-supplied Apple II firmware: the system ROM and the character generator. No Apple ROM data is bundled with
///  the library.
/// </summary>
/// <remarks>
///  <para>
///   Every model's ROMs are kept in the IIe's form, so the bus and video read them the same way: a 16 KiB system ROM
///   for $C000-$FFFF and a 4 KiB character ROM of 256 glyphs, eight rows each, a dot lit where its bit is clear and
///   bit 0 leftmost. <see cref="FromBoardChips"/> puts the 12 KiB ROM and 2 KiB character generator of the II and
///   II Plus into that form.
///  </para>
/// </remarks>
public sealed class Apple2Roms
{
    private const int BoardSystemSize = 12288;
    private const int BoardCharacterSize = 2048;
    private const string AutostartMonitor = "APPLE II+ - 341-0020 - APPLESOFT BASIC AUTOSTART MONITOR F800 - 2716.bin";
    private const string CharacterGenerator = "APPLE II+ - 7341-0036 - CHARACTER GENERATOR REV7+ - 2716.bin";
    private static readonly string[] s_iiPlusChips =
    [
        "APPLE II+ - 341-0011 - APPLESOFT BASIC D000 - 2716.bin",
        "APPLE II+ - 341-0012 - APPLESOFT BASIC D800 - 2716.bin",
        "APPLE II+ - 341-0013 - APPLESOFT BASIC E000 - 2716.bin",
        "APPLE II+ - 341-0014 - APPLESOFT BASIC E800 - 2716.bin",
        "APPLE II+ - 341-0015 - APPLESOFT BASIC F000 - 2716.bin"
    ];

    private static readonly string[] s_iiChips =
    [
        "APPLE II - 341-0001 - INTEGER BASIC E000 - 2716.bin",
        "APPLE II - 341-0002 - INTEGER BASIC E800 - 2716.bin",
        "APPLE II - 341-0003 - INTEGER BASIC F000 - 2716.bin"
    ];

    private const string OriginalMonitor = "APPLE II - 341-0004 - INTEGER BASIC MONITOR F800 - 2716.bin";

    /// <summary>
    ///  The file name of Programmer's Aid #1's dump, the chip for the II's D0 socket, $D000-$D7FF.
    /// </summary>
    public const string ProgrammersAidChip = "APPLE II - 341-0016 - PROGRAMMER'S  AID #1 - 2716.bin";

    private readonly byte[] _system;
    private readonly byte[] _characters;

    /// <summary>
    ///  Copies the firmware into immutable ROM storage.
    /// </summary>
    /// <param name="system">The 16 KiB system ROM mapped at C000-FFFF.</param>
    /// <param name="characters">The 4 KiB character-generator ROM.</param>
    public Apple2Roms(ReadOnlySpan<byte> system, ReadOnlySpan<byte> characters)
    {
        if (system.Length != 16384)
        {
            throw new ArgumentException("A 16 KiB IIe system ROM is required.", nameof(system));
        }

        if (characters.Length != 4096)
        {
            throw new ArgumentException("A 4 KiB character ROM is required.", nameof(characters));
        }

        _system = system.ToArray();
        _characters = characters.ToArray();
    }

    /// <summary>
    ///  Gets the system ROM bytes.
    /// </summary>
    public ReadOnlySpan<byte> System => _system;

    /// <summary>
    ///  Gets the character-generator bytes.
    /// </summary>
    public ReadOnlySpan<byte> Characters => _characters;

    /// <summary>
    ///  Makes the ROMs of an Apple II or II Plus from its board's chips: the 12 KiB system ROM at $D000-$FFFF and the
    ///  2 KiB character generator.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The board's character generator holds one glyph per character code, eight rows each, a dot lit where its
    ///   bit is set and bit 6 leftmost. Unlike the IIe's, it has no inverse glyphs: the board inverts a character
    ///   whose code is below $40 and flashes one from $40 to $7F. The glyphs are turned into the IIe's form here,
    ///   inverse below $40 and normal from $80, which the video already draws that way.
    ///  </para>
    /// </remarks>
    /// <param name="system">
    ///  The 12 KiB system ROM, $D000-$FFFF: AppleSoft and the Autostart Monitor on the II Plus, Integer BASIC and a
    ///  Monitor on the II, whose $D000-$DFFF sockets are empty ($FF).
    /// </param>
    /// <param name="characters">The 2 KiB character generator, such as 7341-0036.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="ArgumentException">A ROM is the wrong size.</exception>
    public static Apple2Roms FromBoardChips(ReadOnlySpan<byte> system, ReadOnlySpan<byte> characters)
    {
        if (system.Length != BoardSystemSize)
        {
            throw new ArgumentException("A 12 KiB system ROM for $D000-$FFFF is required.", nameof(system));
        }

        if (characters.Length != BoardCharacterSize)
        {
            throw new ArgumentException("A 2 KiB character generator is required.", nameof(characters));
        }

        // $C000-$CFFF is I/O and slot space on the II Plus; it never reads as system ROM.
        byte[] full = new byte[16384];
        full.AsSpan(0, 0x1000).Fill(0xFF);
        system.CopyTo(full.AsSpan(0x1000));

        byte[] glyphs = new byte[4096];
        glyphs.AsSpan().Fill(0xFF);
        for (int code = 0; code < 256; code++)
        {
            bool inverse = code < 0x40;
            for (int row = 0; row < 8; row++)
            {
                int dots = characters[code * 8 + row];
                int stored = 0;
                for (int x = 0; x < 7; x++)
                {
                    bool dot = ((dots >> (6 - x)) & 1) != 0;

                    // The IIe's form lights a dot whose bit is clear.
                    if (dot == inverse) { stored |= 1 << x; }
                }

                glyphs[code * 8 + row] = (byte)(stored | 0x80);
            }
        }

        return new(full, glyphs);
    }

    /// <summary>
    ///  Loads a model's ROMs from chip dumps named as the standalone and debugger hosts expect.
    ///  Firmware must be supplied by the caller; no ROMs are downloaded.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="directory">
    ///  The directory holding the dumps: the IIe's CD, EF and video ROMs; the II Plus's five AppleSoft chips
    ///  (341-0011 to 341-0015), its Autostart Monitor (341-0020) and its 7341-0036 character generator; or the II's
    ///  three Integer BASIC chips (341-0001 to 341-0003) and original Monitor (341-0004). The II's board takes the
    ///  same character generator, and its Autostart Monitor is the II Plus's chip, so for the II those two are found
    ///  in the directory or in an <c>APPLE II+</c> folder beside it.
    /// </param>
    /// <param name="autostart">
    ///  For the II, whether the Monitor is the Autostart ROM rather than the original, which resets into the
    ///  Monitor. The II Plus always has the Autostart ROM.
    /// </param>
    /// <returns>The validated immutable firmware.</returns>
    public static Apple2Roms LoadFromDirectory(Apple2Model model, string directory, bool autostart = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        if (model == Apple2Model.IIPlus) { return LoadBoard(directory, s_iiPlusChips, 0, AutostartMonitor); }
        if (model == Apple2Model.II)
        {
            return LoadBoard(directory, s_iiChips, 0x1000, autostart ? AutostartMonitor : OriginalMonitor);
        }

        if (!model.IsIIe())
        {
            throw new ArgumentOutOfRangeException(nameof(model), $"There are no ROM dumps to load for the {model}.");
        }

        string variant = model == Apple2Model.IIeEnhanced ? "ENHANCED" : "UNENHANCED";
        string cd = model == Apple2Model.IIeEnhanced ? "342-0304 - A" : "342-0135 - B";
        string ef = model == Apple2Model.IIeEnhanced ? "342-0303 - A" : "342-0134 - A";
        string video = model == Apple2Model.IIeEnhanced ? "342-0265 - A" : "342-0133 - A";
        byte[] low = File.ReadAllBytes(Path.Join(directory, $"APPLE IIe - CD {variant} - {cd} - 2764.bin"));
        byte[] high = File.ReadAllBytes(Path.Join(directory, $"APPLE IIe - EF {variant} - {ef} - 2764.bin"));
        if (low.Length != 8192 || high.Length != 8192)
        {
            throw new InvalidDataException("Each system ROM chip must be 8 KiB.");
        }

        byte[] characters = File.ReadAllBytes(Path.Join(directory, $"APPLE IIe - VIDEO {variant} - {video} - 2732.bin"));
        return new([.. low, .. high], characters);
    }

    /// <summary>
    ///  Loads the 12 KiB ROM a II or II Plus firmware card holds in place of the board's: the other model's BASIC
    ///  and Monitor, $D000-$FFFF.
    /// </summary>
    /// <param name="model">
    ///  The BASIC the card holds: <see cref="Apple2Model.IIPlus"/> for AppleSoft and the Autostart Monitor,
    ///  <see cref="Apple2Model.II"/> for Integer BASIC and the original Monitor.
    /// </param>
    /// <param name="directory">
    ///  The directory holding that model's dumps, as <see cref="LoadFromDirectory"/> takes.
    /// </param>
    /// <returns>The card's 12 KiB ROM.</returns>
    public static byte[] LoadFirmwareCard(Apple2Model model, string directory) => model switch
    {
        Apple2Model.IIPlus => LoadSystem(directory, s_iiPlusChips, 0, AutostartMonitor),
        Apple2Model.II => LoadSystem(directory, s_iiChips, 0x1000, OriginalMonitor),
        _ => throw new ArgumentOutOfRangeException(nameof(model), "A firmware card holds the II's or the II Plus's ROMs.")
    };

    private static Apple2Roms LoadBoard(string directory, string[] chips, int first, string monitor) =>
        FromBoardChips(LoadSystem(directory, chips, first, monitor), File.ReadAllBytes(Find(directory, CharacterGenerator)));

    // The 12 KiB at $D000-$FFFF: the BASIC chips from an offset, the Monitor at $F800, and $FF in empty sockets.
    private static byte[] LoadSystem(string directory, string[] chips, int first, string monitor)
    {
        byte[] system = new byte[BoardSystemSize];
        system.AsSpan().Fill(0xFF);
        for (int chip = 0; chip < chips.Length; chip++)
        {
            Chip(Find(directory, chips[chip])).CopyTo(system, first + chip * 2048);
        }

        Chip(Find(directory, monitor)).CopyTo(system, 0x2800);
        return system;
    }

    private static byte[] Chip(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        return bytes.Length == 2048 ? bytes : throw new InvalidDataException($"{Path.GetFileName(path)} must be 2 KiB.");
    }

    // A chip in the directory, or in the APPLE II+ folder beside it, where the II's shared chips are.
    private static string Find(string directory, string name)
    {
        string path = Path.Join(directory, name);
        if (File.Exists(path)) { return path; }
        string? parent = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory)));
        string beside = parent is null ? path : Path.Join(parent, "APPLE II+", name);
        return File.Exists(beside) ? beside : path;
    }
}
