// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Machines.Atari;

/// <summary>
///  A ROM cartridge: a plain 8 KB or 16 KB one, or one that switches banks through the cartridge control page
///  (<c>$D500-$D5FF</c>), as <see cref="AtariCartridgeType"/> lists.
/// </summary>
/// <remarks>
///  <para>
///   A cartridge drives <c>RD4</c> to map itself at <c>$8000-$9FFF</c> and <c>RD5</c> at <c>$A000-$BFFF</c>, either
///   unmapping the RAM there; some turn <c>RD5</c> off from the control page to give the RAM back. The banking
///   follows MAME's <c>a800</c> cartridge devices. Writes to the cartridge's ROM do nothing.
///  </para>
/// </remarks>
public sealed class AtariCartridge
{
    private readonly byte[] _rom;
    private int _bank;

    /// <summary>
    ///  Constructs a cartridge from its ROM.
    /// </summary>
    /// <param name="rom">The ROM, in address and bank order.</param>
    /// <param name="type">The hardware; by default a plain cartridge of the ROM's size.</param>
    /// <exception cref="ArgumentException">The ROM's size doesn't fit the type.</exception>
    public AtariCartridge(ReadOnlySpan<byte> rom, AtariCartridgeType? type = null)
    {
        Type = type ?? (rom.Length == 0x4000 ? AtariCartridgeType.Standard16 : AtariCartridgeType.Standard8);
        if (rom.Length != ExpectedSize(Type))
        {
            throw new ArgumentException($"A {Type} cartridge is {ExpectedSize(Type)} bytes, not {rom.Length}.", nameof(rom));
        }

        _rom = rom.ToArray();
        Reset();
    }

    /// <summary>
    ///  Gets the hardware.
    /// </summary>
    public AtariCartridgeType Type { get; }

    /// <summary>
    ///  Gets the ROM.
    /// </summary>
    public ReadOnlySpan<byte> Rom => _rom;

    /// <summary>
    ///  Gets the ROM's size in bytes.
    /// </summary>
    public int Size => _rom.Length;

    /// <summary>
    ///  Gets whether the cartridge is in the right slot.
    /// </summary>
    public bool IsRight => Type == AtariCartridgeType.Right8;

    /// <summary>
    ///  Gets whether the cartridge maps itself at <c>$8000-$9FFF</c>.
    /// </summary>
    public bool Rd4 { get; private set; }

    /// <summary>
    ///  Gets whether the cartridge maps itself at <c>$A000-$BFFF</c>.
    /// </summary>
    public bool Rd5 { get; private set; }

    /// <summary>
    ///  Gets the bank switched in.
    /// </summary>
    public int Bank => _bank;

    /// <summary>
    ///  Reads a cartridge from a file: a <c>.car</c> with its 16-byte header, or a raw <c>.rom</c> or <c>.bin</c> of 8 KB
    ///  or 16 KB.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The cartridge.</returns>
    public static AtariCartridge Load(string path) => Load(File.ReadAllBytes(path));

    /// <summary>
    ///  Reads a cartridge image: a <c>.car</c> with its 16-byte header, or a raw 8 KB or 16 KB ROM.
    /// </summary>
    /// <param name="data">The image.</param>
    /// <returns>The cartridge.</returns>
    /// <exception cref="NotSupportedException">The <c>.car</c> type isn't one this machine has.</exception>
    public static AtariCartridge Load(ReadOnlySpan<byte> data)
    {
        if (data.Length >= 16 && data[..4].SequenceEqual("CART"u8))
        {
            int type = BinaryPrimitives.ReadInt32BigEndian(data[4..]);
            if (!Enum.IsDefined((AtariCartridgeType)type))
            {
                throw new NotSupportedException($"Cartridge type {type} isn't supported.");
            }

            return new(data[16..], (AtariCartridgeType)type);
        }

        return new(data);
    }

    /// <summary>
    ///  Returns the cartridge to its power-on bank.
    /// </summary>
    public void Reset()
    {
        _bank = 0;
        Rd4 = Type is AtariCartridgeType.Standard16 or AtariCartridgeType.Right8 || IsXegs;
        Rd5 = Type != AtariCartridgeType.Right8;
    }

    /// <summary>
    ///  Reads the cartridge.
    /// </summary>
    /// <param name="address">An address in <c>$8000-$BFFF</c> the cartridge maps.</param>
    /// <returns>The byte.</returns>
    public byte Read(ushort address)
    {
        int offset = address & 0x1FFF;
        bool high = address >= 0xA000;
        return Type switch
        {
            AtariCartridgeType.Standard8 or AtariCartridgeType.Right8 => _rom[offset],
            AtariCartridgeType.Standard16 => _rom[address - 0x8000],
            AtariCartridgeType.Oss8 or AtariCartridgeType.Oss091 => (address & 0x1000) == 0
                ? _rom[(address & 0x0FFF) | (_bank << 12)]
                : _rom[address & 0x0FFF],
            _ when IsXegs => high ? _rom[_rom.Length - 0x2000 + offset] : _rom[(_bank << 13) + offset],
            _ => _rom[(_bank << 13) + offset]
        };
    }

    /// <summary>
    ///  An access to the cartridge control page, which switches banks.
    /// </summary>
    /// <param name="address">The address, <c>$D500-$D5FF</c>.</param>
    /// <param name="value">The value written, or null for a read.</param>
    /// <returns>Whether <see cref="Rd4"/> or <see cref="Rd5"/> changed.</returns>
    public bool Control(ushort address, byte? value)
    {
        bool rd4 = Rd4;
        bool rd5 = Rd5;
        int low = address & 0xFF;
        int banks = _rom.Length / 0x2000;
        switch (Type)
        {
            case AtariCartridgeType.Williams32:
            case AtariCartridgeType.Williams64:
                Select((low & 0x08) == 0, low & 7 & (banks - 1));
                break;
            case AtariCartridgeType.Express64:
                if ((low & 0xF0) == 0x70) { Select((low & 0x08) == 0, (low ^ 7) & 7); }
                break;
            case AtariCartridgeType.Diamond64:
                if ((low & 0xF0) == 0xD0) { Select((low & 0x08) == 0, (low ^ 7) & 7); }
                break;
            case AtariCartridgeType.Atarimax128:
                if (low < 0x20) { Select(low < 0x10, low & 0x0F); }
                break;
            case AtariCartridgeType.Atarimax1024:
                Select(low < 0x80, low & 0x7F);
                break;
            case AtariCartridgeType.Oss8:
                // ---- 0--x bank 1; ---- 1--1 bank 0; ---- 1--0 off.
                if ((low & 0x08) == 0)
                {
                    Select(enabled: true, 1);
                }
                else
                {
                    Select((low & 1) != 0, 0);
                }

                break;
            case AtariCartridgeType.Oss091:
                // ---- 0--0 bank 1; ---- 0--1 bank 3; ---- 1--1 bank 2; ---- 1--0 off.
                if ((low & 0x08) == 0)
                {
                    Select(enabled: true, 1 | ((low & 1) << 1));
                }
                else
                {
                    Select((low & 1) != 0, 2);
                }

                break;
            default:
                if (IsXegs && value is byte bank) { _bank = bank & (banks - 1); }
                break;
        }

        return rd4 != Rd4 || rd5 != Rd5;
    }

    private bool IsXegs => Type is AtariCartridgeType.Xegs32
        or AtariCartridgeType.Xegs64
        or AtariCartridgeType.Xegs128
        or AtariCartridgeType.Xegs256
        or AtariCartridgeType.Xegs512
        or AtariCartridgeType.Xegs1024;

    private void Select(bool enabled, int bank)
    {
        Rd5 = enabled;
        if (enabled) { _bank = bank; }
    }

    private static int ExpectedSize(AtariCartridgeType type) => type switch
    {
        AtariCartridgeType.Standard8 or AtariCartridgeType.Right8 or AtariCartridgeType.Oss8 => 0x2000,
        AtariCartridgeType.Standard16 or AtariCartridgeType.Oss091 => 0x4000,
        AtariCartridgeType.Williams32 or AtariCartridgeType.Xegs32 => 0x8000,
        AtariCartridgeType.Williams64 => 0x10000,
        AtariCartridgeType.Express64 => 0x10000,
        AtariCartridgeType.Diamond64 => 0x10000,
        AtariCartridgeType.Xegs64 => 0x10000,
        AtariCartridgeType.Xegs128 or AtariCartridgeType.Atarimax128 => 0x20000,
        AtariCartridgeType.Xegs256 => 0x40000,
        AtariCartridgeType.Xegs512 => 0x80000,
        _ => 0x100000
    };
}
