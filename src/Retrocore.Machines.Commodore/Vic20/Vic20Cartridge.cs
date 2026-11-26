// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using System.Globalization;
using System.Numerics;

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  A cartridge for the VIC-20's expansion port: ROM in blocks 1, 2, 3 and 5 (<c>$2000-$7FFF</c> and
///  <c>$A000-$BFFF</c>), and any RAM it brings.
/// </summary>
/// <remarks>
///  <para>
///   A cartridge is chips at addresses. A chip smaller than its 8K block, when it starts at the block's start or
///   fills an aligned part of it, is seen again through the rest, since a cartridge does not decode the address lines
///   it has no use for: a 4K chip at <c>$A000</c> is also at <c>$B000</c>. What a cartridge leaves empty, the bus
///   leaves to RAM where there is some, and to nothing otherwise.
///  </para>
///  <para>
///   A ROM at <c>$A000</c> that has <c>A0CBM</c> at <c>$A004</c> starts itself: the kernal checks for it at reset and
///   jumps through <c>$A000</c>.
///  </para>
/// </remarks>
public sealed class Vic20Cartridge
{
    private static ReadOnlySpan<byte> CrtSignature => "VIC20 CARTRIDGE "u8;
    private static ReadOnlySpan<byte> AutostartSignature => [0x41, 0x30, 0xC3, 0xC2, 0xCD];

    // The ROM by address, and for each 8K block (address >> 13) which of its 1K pages a chip filled.
    private readonly byte[] _rom = new byte[0x10000];
    private readonly int[] _filled = new int[8];

    /// <summary>
    ///  Creates a cartridge from its chips.
    /// </summary>
    /// <param name="chips">Each chip's address and bytes.</param>
    /// <param name="ram">The RAM the cartridge brings, such as the Super Expander's 3K.</param>
    /// <exception cref="ArgumentException">
    ///  A chip is outside blocks 1, 2, 3 and 5, two chips fill the same 1K page, or there is neither a chip nor RAM.
    /// </exception>
    public Vic20Cartridge(IEnumerable<(int Address, byte[] Rom)> chips, Vic20Expansion ram = Vic20Expansion.None)
    {
        ArgumentNullException.ThrowIfNull(chips);
        Ram = ram;
        foreach ((int address, byte[] rom) in chips)
        {
            ArgumentNullException.ThrowIfNull(rom);
            if (rom.Length == 0) { continue; }
            if (address < 0 || address + rom.Length > 0x10000)
            {
                throw new ArgumentException($"A chip at ${address:X4} of {rom.Length} bytes runs past $FFFF.", nameof(chips));
            }

            // A chip that ends inside a page, as some dumps do, fills the page; the rest of it reads 0.
            for (int page = address >> 10; page <= (address + rom.Length - 1) >> 10; page++)
            {
                int block = page >> 3;
                if (block is not (1 or 2 or 3 or 5))
                {
                    throw new ArgumentException(
                        $"A chip at ${address:X4} of {rom.Length} bytes reaches ${page << 10:X4}, outside blocks 1, 2, 3 and 5.",
                        nameof(chips));
                }

                if ((_filled[block] & (1 << (page & 7))) != 0)
                {
                    throw new ArgumentException($"Two chips fill ${page << 10:X4}.", nameof(chips));
                }

                _filled[block] |= 1 << (page & 7);
            }

            rom.CopyTo(_rom, address);
        }

        // A chip that fills an aligned power-of-two part of its block repeats through the rest.
        for (int block = 0; block < 8; block++)
        {
            int filled = _filled[block];
            if (filled is 0 or 0xFF) { continue; }
            int pages = BitOperations.PopCount((uint)filled);
            int first = BitOperations.TrailingZeroCount(filled);
            if (!BitOperations.IsPow2(pages) || first % pages != 0 || filled != ((1 << pages) - 1) << first)
            {
                continue;
            }

            int start = block << 13;
            for (int offset = 0; offset < 0x2000; offset++)
            {
                _rom[start + offset] = _rom[start + (first * 0x400) + (offset % (pages * 0x400))];
            }

            _filled[block] = 0xFF;
        }

        if (Blocks == Vic20Expansion.None && ram == Vic20Expansion.None)
        {
            throw new ArgumentException("A cartridge has at least a chip or some RAM.", nameof(chips));
        }
    }

    /// <summary>
    ///  Gets the blocks the cartridge's ROM is in, as <see cref="Vic20Expansion"/>'s block flags.
    /// </summary>
    public Vic20Expansion Blocks
    {
        get
        {
            Vic20Expansion blocks = Vic20Expansion.None;
            if (_filled[1] != 0) { blocks |= Vic20Expansion.Block1; }
            if (_filled[2] != 0) { blocks |= Vic20Expansion.Block2; }
            if (_filled[3] != 0) { blocks |= Vic20Expansion.Block3; }
            if (_filled[5] != 0) { blocks |= Vic20Expansion.Block5; }
            return blocks;
        }
    }

    /// <summary>
    ///  Gets the RAM the cartridge brings.
    /// </summary>
    public Vic20Expansion Ram { get; }

    /// <summary>
    ///  Gets whether the cartridge starts itself: <c>A0CBM</c> at <c>$A004</c>.
    /// </summary>
    public bool Autostarts => (_filled[5] & 1) != 0 && _rom.AsSpan(0xA004, 5).SequenceEqual(AutostartSignature);

    /// <summary>
    ///  Gets whether the cartridge's ROM fills an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether a chip answers there.</returns>
    public bool Fills(int address) => (_filled[(address >> 13) & 7] & (1 << ((address >> 10) & 7))) != 0;

    /// <summary>
    ///  Reads the cartridge's ROM.
    /// </summary>
    /// <param name="address">An address it <see cref="Fills"/>.</param>
    /// <returns>The byte.</returns>
    public byte Read(int address) => _rom[address & 0xFFFF];

    /// <summary>
    ///  Reads a cartridge from its files: one, or the several chips a MAME software list's zip holds.
    /// </summary>
    /// <param name="paths">The files.</param>
    /// <returns>The cartridge.</returns>
    public static Vic20Cartridge Load(params string[] paths)
    {
        ArgumentNullException.ThrowIfNull(paths);
        return Load(paths.Select(path => (Path.GetFileName(path), File.ReadAllBytes(path))).ToArray());
    }

    /// <summary>
    ///  Reads a cartridge from its files' names and bytes.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each file is a VICE <c>.crt</c> (by its <c>VIC20 CARTRIDGE</c> signature), a chip whose extension is its
    ///   address's high byte (MAME's <c>.20</c>, <c>.40</c>, <c>.60</c>, <c>.70</c>, <c>.a0</c> and <c>.b0</c>), or a
    ///   <c>.prg</c> whose first two bytes are its address. A file with none of these is a <c>.prg</c> when its first
    ///   two bytes are a block's start or middle and the rest is whole 1K pages, and otherwise a chip at
    ///   <c>$A000</c>.
    ///  </para>
    /// </remarks>
    /// <param name="files">Each file's name and bytes.</param>
    /// <returns>The cartridge.</returns>
    /// <exception cref="InvalidDataException">A file is not a cartridge image this reads.</exception>
    public static Vic20Cartridge Load(params (string Name, byte[] Data)[] files)
    {
        ArgumentNullException.ThrowIfNull(files);
        List<(int Address, byte[] Rom)> chips = [];
        Vic20Expansion ram = Vic20Expansion.None;
        foreach ((string name, byte[] data) in files)
        {
            if (data.AsSpan().StartsWith(CrtSignature))
            {
                ram |= ReadCrt(data, chips);
                continue;
            }

            string extension = Path.GetExtension(name).TrimStart('.').ToUpperInvariant();
            if (extension is "20" or "40" or "60" or "70" or "A0" or "B0")
            {
                chips.Add((int.Parse(extension, NumberStyles.HexNumber, CultureInfo.InvariantCulture) << 8, data));
            }
            else if (extension == "PRG" || LooksLikePrg(data))
            {
                if (data.Length < 3) { throw new InvalidDataException($"{name} is too short for a .prg cartridge."); }
                chips.Add((data[0] | (data[1] << 8), data[2..]));
            }
            else
            {
                chips.Add((0xA000, data));
            }
        }

        try
        {
            return new(chips, ram);
        }
        catch (ArgumentException e)
        {
            throw new InvalidDataException(e.Message, e);
        }
    }

    private static bool LooksLikePrg(byte[] data) =>
        data.Length > 2
            && (data.Length - 2) % 0x400 == 0
            && (data[0] | (data[1] << 8)) is 0x2000 or 0x3000 or 0x4000 or 0x5000 or 0x6000 or 0x7000 or 0xA000 or 0xB000;

    // VICE's CRT: the header (its length big-endian at $10, the hardware type at $16), then CHIP packets of a length,
    // a type, a bank, an address and a size, all big-endian, and the bytes.
    private static Vic20Expansion ReadCrt(ReadOnlySpan<byte> data, List<(int Address, byte[] Rom)> chips)
    {
        if (data.Length < 0x40) { throw new InvalidDataException("The .crt file ends inside its header."); }
        int type = BinaryPrimitives.ReadUInt16BigEndian(data[0x16..]);
        if (type != 0)
        {
            throw new InvalidDataException($"The .crt file is hardware type {type}; only generic cartridges (type 0) are supported.");
        }

        Vic20Expansion ram = Vic20Expansion.None;
        int offset = (int)Math.Max(0x40, BinaryPrimitives.ReadUInt32BigEndian(data[0x10..]));
        while (offset + 0x10 <= data.Length)
        {
            ReadOnlySpan<byte> packet = data[offset..];
            if (!packet.StartsWith("CHIP"u8))
            {
                throw new InvalidDataException($"The .crt file has no CHIP packet at {offset}.");
            }

            int length = (int)BinaryPrimitives.ReadUInt32BigEndian(packet[4..]);
            int chipType = BinaryPrimitives.ReadUInt16BigEndian(packet[8..]);
            int bank = BinaryPrimitives.ReadUInt16BigEndian(packet[10..]);
            int address = BinaryPrimitives.ReadUInt16BigEndian(packet[12..]);
            int size = BinaryPrimitives.ReadUInt16BigEndian(packet[14..]);
            if (length < 0x10 + size || offset + 0x10 + size > data.Length)
            {
                throw new InvalidDataException($"The .crt file's CHIP packet at {offset} runs past its end.");
            }

            if (bank != 0) { throw new InvalidDataException("The .crt file has banks; a generic cartridge has none."); }
            if (chipType == 1)
            {
                // A RAM chip: the 3K or a block of RAM.
                ram |= address switch
                {
                    0x0400 => Vic20Expansion.Ram3K,
                    0x2000 => Vic20Expansion.Block1,
                    0x4000 => Vic20Expansion.Block2,
                    0x6000 => Vic20Expansion.Block3,
                    0xA000 => Vic20Expansion.Block5,
                    _ => throw new InvalidDataException($"The .crt file has RAM at ${address:X4}, which is no expansion block.")
                };
            }
            else
            {
                chips.Add((address, packet.Slice(0x10, size).ToArray()));
            }

            offset += length;
        }

        return ram;
    }
}
