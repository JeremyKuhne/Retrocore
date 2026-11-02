// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  The IIe bus's memory areas, which the debugger's memory banks are built on: storage read and written
///  directly whatever the soft switches map, and the read and write areas that say where each is mapped.
/// </summary>
[TestClass]
public class MemoryBankTests
{
    /// <summary>
    ///  Reads and writes are mapped apart: RAMWRT sends writes to auxiliary RAM while reads stay in main RAM.
    /// </summary>
    [TestMethod]
    public void WritesMapApartFromReads()
    {
        Apple2Bus bus = Bus();
        bus.Write(0xC005, value: 0);
        bus.ReadArea(0x2000).Should().Be(Apple2MemoryArea.MainRam);
        bus.WriteArea(0x2000).Should().Be(Apple2MemoryArea.AuxiliaryRam);
        bus.Write(0x2000, value: 0x5A);
        bus.PeekArea(Apple2MemoryArea.AuxiliaryRam, 0x2000, out byte aux).Should().BeTrue();
        aux.Should().Be(0x5A);
        bus.Peek(0x2000).Should().Be(0);

        // ROM reads at $D000 until the language card's RAM is enabled, and writes there change nothing.
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.SystemRom);
        bus.Read(0xC08A);
        bus.WriteArea(0xD000).Should().Be(Apple2MemoryArea.None);
    }

    /// <summary>
    ///  The language card's two $D000 banks are separate storage, each readable whichever is mapped.
    /// </summary>
    [TestMethod]
    public void LanguageCardBanksAreSeparate()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC08B);
        bus.Read(0xC08B);
        bus.ReadArea(0xD000).Should().Be(Apple2MemoryArea.MainLanguageCardBank1);
        bus.WriteArea(0xD000).Should().Be(Apple2MemoryArea.MainLanguageCardBank1);
        bus.ReadArea(0xE000).Should().Be(Apple2MemoryArea.MainLanguageCard);
        bus.Write(0xD000, value: 1);
        bus.PokeArea(Apple2MemoryArea.MainLanguageCard, 0xD000, value: 2).Should().BeTrue();
        bus.Peek(0xD000).Should().Be(1);
        bus.PeekArea(Apple2MemoryArea.MainLanguageCard, 0xD000, out byte bank2).Should().BeTrue();
        bank2.Should().Be(2);

        // Bank one has nothing above $DFFF, and RAM has nothing at $C000-$CFFF.
        bus.PeekArea(Apple2MemoryArea.MainLanguageCardBank1, 0xE000, out _).Should().BeFalse();
        bus.PeekArea(Apple2MemoryArea.MainRam, 0xC800, out _).Should().BeFalse();
        bus.PokeArea(Apple2MemoryArea.SystemRom, 0xD000, value: 0).Should().BeFalse();
    }

    /// <summary>
    ///  A slot's ROM reads directly whether the slot or the internal firmware is mapped at its page.
    /// </summary>
    [TestMethod]
    public void SlotRomsReadWhateverIsMapped()
    {
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]), new MemoryBlockDevice(new byte[512 * 8]));
        bus.ReadArea(0xC700).Should().Be(Apple2MemoryArea.Slot7Rom);
        bus.PeekArea(Apple2MemoryArea.Slot7Rom, 0xC700, out byte firmware).Should().BeTrue();
        firmware.Should().Be(bus.Peek(0xC700));

        bus.Write(0xC007, value: 0);
        bus.ReadArea(0xC700).Should().Be(Apple2MemoryArea.SystemRom);
        bus.PeekArea(Apple2MemoryArea.Slot7Rom, 0xC701, out byte next).Should().BeTrue();
        bus.Write(0xC006, value: 0);
        next.Should().Be(bus.Peek(0xC701));

        // Without the Disk II's firmware slot 6 has no ROM, and a slot's ROM is only its own page.
        bus.PeekArea(Apple2MemoryArea.Slot6Rom, 0xC600, out _).Should().BeFalse();
        bus.PeekArea(Apple2MemoryArea.Slot7Rom, 0xC800, out _).Should().BeFalse();
        bus.PokeArea(Apple2MemoryArea.Slot7Rom, 0xC700, value: 0).Should().BeFalse();
    }

    private static Apple2Bus Bus() => new(new Apple2Roms(new byte[16384], new byte[4096]));
}
