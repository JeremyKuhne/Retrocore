// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  A BBC Micro's ROMs: the 16K MOS, the four paged ROM sockets and the SAA5050's character generator.
/// </summary>
/// <remarks>
///  <para>
///   The Model B's sockets are IC101, IC100, IC88 and IC52, paged in as ROMs 0-3. Without a sideways ROM board
///   ROMSEL's upper bits go nowhere, so ROMs 4-15 are ROMs 0-3 again. The highest-numbered language ROM starts at
///   BREAK, which is why BASIC goes in IC52. An 8K ROM in a socket answers in both halves of its 16K. An empty socket
///   reads <c>$FF</c>.
///  </para>
/// </remarks>
public sealed class BbcRoms
{
    /// <summary>
    ///  The size of the MOS and of a paged ROM.
    /// </summary>
    public const int RomSize = 0x4000;

    /// <summary>
    ///  The paged ROM sockets on the board.
    /// </summary>
    public const int Sockets = 4;

    /// <summary>
    ///  The size of the SAA5050's character ROM: 96 characters of 10 rows of 5 dots.
    /// </summary>
    public const int CharacterRomSize = 960;

    private readonly byte[] _mos;
    private readonly byte[]?[] _sockets = new byte[Sockets][];
    private readonly byte[] _characters;

    /// <summary>
    ///  Constructs the ROMs.
    /// </summary>
    /// <param name="mos">The 16K MOS.</param>
    /// <param name="characters">The SAA5050's 960-byte character ROM.</param>
    /// <exception cref="ArgumentException">A ROM is the wrong size.</exception>
    public BbcRoms(ReadOnlySpan<byte> mos, ReadOnlySpan<byte> characters)
    {
        if (mos.Length != RomSize) { throw new ArgumentException("The MOS is 16,384 bytes.", nameof(mos)); }
        if (characters.Length != CharacterRomSize)
        {
            throw new ArgumentException("The SAA5050's character ROM is 960 bytes.", nameof(characters));
        }

        _mos = mos.ToArray();
        _characters = characters.ToArray();
    }

    /// <summary>
    ///  Gets the MOS, mapped at <c>$C000</c>.
    /// </summary>
    public ReadOnlySpan<byte> Mos => _mos;

    /// <summary>
    ///  Gets the SAA5050's character ROM: characters <c>$20-$7F</c>, ten rows each, the dots in bits 0-4 with the
    ///  leftmost in bit 4.
    /// </summary>
    public ReadOnlySpan<byte> Characters => _characters;

    /// <summary>
    ///  Gets the ROM in a socket, 16K, or empty when the socket is.
    /// </summary>
    /// <param name="socket">The socket, 0-3.</param>
    /// <returns>The ROM.</returns>
    public ReadOnlySpan<byte> Socket(int socket) => _sockets[socket];

    /// <summary>
    ///  Puts a ROM in a socket, or empties it.
    /// </summary>
    /// <param name="socket">The socket, 0-3.</param>
    /// <param name="rom">An 8K or 16K ROM, or empty to leave the socket empty.</param>
    /// <exception cref="ArgumentException">The ROM is neither 8K nor 16K.</exception>
    public void Fit(int socket, ReadOnlySpan<byte> rom)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(socket);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(socket, Sockets);
        if (rom.IsEmpty)
        {
            _sockets[socket] = null;
            return;
        }

        if (rom.Length is not (RomSize or RomSize / 2))
        {
            throw new ArgumentException("A paged ROM is 8,192 or 16,384 bytes.", nameof(rom));
        }

        byte[] image = new byte[RomSize];
        rom.CopyTo(image);
        if (rom.Length != RomSize) { rom.CopyTo(image.AsSpan(RomSize / 2)); }
        _sockets[socket] = image;
    }

    /// <summary>
    ///  Loads the ROMs from a directory holding MAME's chip files, as its <c>bbcb</c> set unzipped does: MOS 1.20
    ///  (<c>os12.rom</c>), BASIC II (<c>basic2.rom</c>) in socket 3, and the character ROM (<c>saa5050</c>).
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="filingSystem">
    ///  The disk filing system ROM's file for socket 0, such as <c>dnfs120.rom</c>, or null to leave it empty.
    /// </param>
    /// <param name="basic">BASIC's file: <c>basic2.rom</c>, or <c>basic1.rom</c> for BASIC I.</param>
    /// <param name="mos">The MOS's file.</param>
    /// <returns>The ROMs.</returns>
    public static BbcRoms LoadFromDirectory(
        string directory,
        string? filingSystem = null,
        string basic = "basic2.rom",
        string mos = "os12.rom")
    {
        BbcRoms roms = new(
            File.ReadAllBytes(Path.Join(directory, mos)),
            File.ReadAllBytes(Path.Join(directory, "saa5050")));

        roms.Fit(3, File.ReadAllBytes(Path.Join(directory, basic)));
        if (filingSystem is not null) { roms.Fit(0, File.ReadAllBytes(Path.Join(directory, filingSystem))); }
        return roms;
    }
}
