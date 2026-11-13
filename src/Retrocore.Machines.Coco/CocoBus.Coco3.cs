// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

// The CoCo 3's memory map: the GIME's MMU over 128 or 512 KB, the 32 KB ROM and the cartridge, and the I/O page.
// $FF00-$FF0F is PIA 0 and $FF20-$FF2F PIA 1 (each mirrored every 4 bytes), $FF40-$FF5F the cartridge's I/O,
// $FF90-$FFBF the GIME, $FFC0-$FFDF the SAM's switches, and $FFE0-$FFFF the internal ROM's vectors; the rest of
// the page reads the floating bus.
public sealed partial class CocoBus
{
    /// <summary>
    ///  Reads physical RAM, wrapping at its size, as the CoCo 3's video does.
    /// </summary>
    /// <param name="address">The physical address.</param>
    /// <returns>The byte.</returns>
    internal byte PhysicalRead(int address) => _ram[(int)((uint)address % (uint)_ram.Length)];

    private byte ReadCoco3(ushort address)
    {
        if (address < 0xFF00) { return ReadMapped(address); }
        return address switch
        {
            < 0xFF10 => ReadPia0(address),
            < 0xFF20 => _floating,
            < 0xFF30 => Pia1.Read(address & 3),
            < 0xFF40 => _floating,
            < 0xFF60 => DiskController is { } disk ? disk.Read(address, _floating) : _floating,
            < 0xFF90 => _floating,
            < 0xFFC0 => Gime3.Read(address, _floating),
            < 0xFFE0 => _floating,
            _ => _rom3[0x7FE0 + (address & 0x1F)]
        };
    }

    private byte PeekCoco3(ushort address)
    {
        if (address < 0xFF00) { return ReadMapped(address); }
        return address switch
        {
            < 0xFF10 => Pia0.Peek(address & 3),
            < 0xFF20 => _floating,
            < 0xFF30 => Pia1.Peek(address & 3),
            < 0xFF40 => _floating,
            < 0xFF60 => DiskController is { } disk ? disk.Peek(address, _floating) : _floating,
            < 0xFF90 => _floating,
            < 0xFFC0 => Gime3.Peek(address, _floating),
            < 0xFFE0 => _floating,
            _ => _rom3[0x7FE0 + (address & 0x1F)]
        };
    }

    private void WriteCoco3(ushort address, byte value)
    {
        if (address < 0xFF00)
        {
            int ram = MapRam(address);
            if (ram >= 0) { _ram[ram] = value; }
            return;
        }

        if (address < 0xFF10)
        {
            Pia0.Write(address & 3, value);
            RefreshKeyboard(force: true);
        }
        else if (address is >= 0xFF20 and < 0xFF30)
        {
            Pia1.Write(address & 3, value);
        }
        else if (address is >= 0xFF40 and < 0xFF60)
        {
            DiskController?.Write(address, value);
        }
        else if (address is >= 0xFF90 and < 0xFFC0)
        {
            Gime3.Write(address, value);
        }
        else if (address is >= 0xFFC0 and < 0xFFE0)
        {
            Sam.Write(address);
        }
    }

    private CocoMemoryArea AreaCoco3(ushort address)
    {
        if (address >= 0xFF00)
        {
            return address >= 0xFFE0 ? CocoMemoryArea.ColorBasic : CocoMemoryArea.Io;
        }

        if (MapRam(address) >= 0) { return CocoMemoryArea.Ram; }
        int page = address >> 13;
        if (IsCartridgeBlock(Gime3.Block(page)))
        {
            return Slot is null ? CocoMemoryArea.None : CocoMemoryArea.Cartridge;
        }

        return (page & 3) < 2 ? CocoMemoryArea.ExtendedBasic : CocoMemoryArea.ColorBasic;
    }

    private byte ReadMapped(ushort address)
    {
        int ram = MapRam(address);
        if (ram >= 0) { return _ram[ram]; }

        // Blocks $3C-$3F are ROM: the page's 8 KB of the internal ROM, or the cartridge's, as the ROM map says.
        int page = address >> 13;
        int offset = address & 0x1FFF;
        if (IsCartridgeBlock(Gime3.Block(page)))
        {
            return Slot is { } cartridge ? cartridge.Read((((page & 3) ^ 2) * 0x2000) + offset) : _floating;
        }

        return _rom3[((page & 3) * 0x2000) + offset];
    }

    // The RAM index an address maps to, or -1 for ROM.
    private int MapRam(ushort address)
    {
        CocoGime gime = Gime3;
        if (address >= 0xFE00 && gime.ConstantVectorPage)
        {
            return ((0x3F * 0x2000) + (address & 0x1FFF)) & (_ram.Length - 1);
        }

        int block = gime.Block(address >> 13);
        if (block >= 0x3C && !Sam.MapType1) { return -1; }
        return (int)((uint)((block * 0x2000) + (address & 0x1FFF)) % (uint)_ram.Length);
    }

    private bool IsCartridgeBlock(int block) => Gime3.RomMap == 3 || (Gime3.RomMap < 2 && block >= 0x3E);

    private CocoGime Gime3 => Gime ?? throw new InvalidOperationException("Only the CoCo 3 has a GIME.");
}
