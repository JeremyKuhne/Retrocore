// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Atari;
using Retrocore.Machines.Coco;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Machines.Kaypro;
using Retrocore.Machines.Trs80;
using Retrocore.Machines.Trs80Model100;

namespace Retrocore.Tests;

/// <summary>
///  The memory maps static analysis uses: each machine's areas by kind, and the maps captured from the machines in
///  the states their ROMs run in, against the machines' documentation (docs/Apple2.md, BbcMicro.md, Coco.md).
/// </summary>
[TestClass]
public class MachineMemoryMapTests
{
    /// <summary>
    ///  Every memory area of the Apple IIe, the BBC Micro, the CoCo, the Kaypro, the VIC-20, the Atari and the
    ///  Model 100 has the kind its name says: RAM (video memory and banks included), ROM, devices, or nothing.
    /// </summary>
    [TestMethod]
    public void AreasHaveTheirKinds()
    {
        Kinds(Apple2(Apple2Model.IIeEnhanced)).Should().Equal(
            ("None", MemoryKind.None), ("Io", MemoryKind.Io), ("MainRam", MemoryKind.Ram),
            ("AuxiliaryRam", MemoryKind.Ram), ("MainLanguageCard", MemoryKind.Ram),
            ("MainLanguageCardBank1", MemoryKind.Ram), ("AuxiliaryLanguageCard", MemoryKind.Ram),
            ("AuxiliaryLanguageCardBank1", MemoryKind.Ram), ("SystemRom", MemoryKind.Rom),
            ("Slot1Rom", MemoryKind.Rom), ("Slot2Rom", MemoryKind.Rom), ("Slot3Rom", MemoryKind.Rom),
            ("Slot4Rom", MemoryKind.Rom), ("Slot5Rom", MemoryKind.Rom), ("Slot6Rom", MemoryKind.Rom),
            ("Slot7Rom", MemoryKind.Rom));

        Kinds(new BbcMachine(BbcRoms())).Should().Equal(
            ("None", MemoryKind.None), ("Ram", MemoryKind.Ram), ("PagedRom0", MemoryKind.Rom),
            ("PagedRom1", MemoryKind.Rom), ("PagedRom2", MemoryKind.Rom), ("PagedRom3", MemoryKind.Rom),
            ("Mos", MemoryKind.Rom), ("OneMegahertzBus", MemoryKind.Io), ("Sheila", MemoryKind.Io));

        Kinds(Coco(CocoModel.Coco2)).Should().Equal(
            ("None", MemoryKind.None), ("Ram", MemoryKind.Ram), ("ExtendedBasic", MemoryKind.Rom),
            ("ColorBasic", MemoryKind.Rom), ("Cartridge", MemoryKind.Rom), ("Io", MemoryKind.Io));

        Kinds(new KayproMachine(new KayproRoms(new byte[KayproRoms.MonitorSize], new byte[KayproRoms.CharacterGeneratorSize]))).Should().Equal(
            ("Rom", MemoryKind.Rom), ("Video", MemoryKind.Ram), ("Ram", MemoryKind.Ram));

        // The VIC-20's colour RAM keeps four bits, so it is a device's.
        Kinds(new Vic20Machine(new Vic20Roms(new byte[0x2000], new byte[0x2000], new byte[0x1000]))).Should().Equal(
            ("None", MemoryKind.None), ("Ram", MemoryKind.Ram), ("ExpansionRam", MemoryKind.Ram),
            ("Cartridge", MemoryKind.Rom), ("CharacterRom", MemoryKind.Rom), ("Vic", MemoryKind.Io),
            ("Via", MemoryKind.Io), ("ColourRam", MemoryKind.Io), ("Basic", MemoryKind.Rom), ("Kernal", MemoryKind.Rom));

        Kinds(new AtariMachine(new AtariRoms(new byte[AtariRoms.Size]))).Should().Equal(
            ("Ram", MemoryKind.Ram), ("RightCartridge", MemoryKind.Rom), ("LeftCartridge", MemoryKind.Rom),
            ("Io", MemoryKind.Io), ("FloatingPoint", MemoryKind.Rom), ("OperatingSystem", MemoryKind.Rom),
            ("Empty", MemoryKind.None));

        Kinds(new Trs80Model100Machine(new Trs80Model100Configuration(), new Trs80Model100Roms(new byte[Trs80Model100Roms.RomSize]))).Should().Equal(
            ("None", MemoryKind.None), ("Rom", MemoryKind.Rom), ("OptionRom", MemoryKind.Rom), ("Ram", MemoryKind.Ram));
    }

    /// <summary>
    ///  Areas whose kind depends on the machine's set-up: the IIe's slot 4 ROM space is the Mockingboard's devices
    ///  while it is in, and the TRS-80's video memory is RAM only with the lowercase modification, as without it
    ///  bit 6 is not stored.
    /// </summary>
    [TestMethod]
    public void KindsFollowTheSetUp()
    {
        Apple2Machine apple = Apple2(Apple2Model.IIeEnhanced);
        IMachine machine = apple;
        int slot4 = (int)Apple2MemoryArea.Slot4Rom;
        machine.AreaKind(slot4).Should().Be(MemoryKind.Rom);
        apple.Bus.InstallMockingboard();
        machine.AreaKind(slot4).Should().Be(MemoryKind.Io);

        Trs80Roms roms = new(new byte[0x3000], new byte[Trs80Roms.CharacterGeneratorSize]);
        IMachine plain = new Trs80Machine(new Trs80Configuration(), roms);
        IMachine lowercase = new Trs80Machine(new Trs80Configuration { LowercaseModification = true }, roms);
        plain.AreaKind((int)Trs80MemoryArea.Video).Should().Be(MemoryKind.Io);
        lowercase.AreaKind((int)Trs80MemoryArea.Video).Should().Be(MemoryKind.Ram);
    }

    /// <summary>
    ///  The maps after reset match the machines' documented memory maps.
    /// </summary>
    [TestMethod]
    public void ResetMapsMatchTheDocumentation()
    {
        // BbcMicro.md: RAM, paged ROM, the MOS, FRED and JIM, SHEILA, and the MOS's last page.
        Ranges(MemoryMap.Capture(new BbcMachine(BbcRoms()))).Should().Equal(
            "0000-7FFF Ram", "8000-FBFF Rom", "FC00-FEFF Io", "FF00-FFFF Rom");

        // Apple2.md: RAM, the soft switches and slot I/O, the empty slots' ROM space but slot 3's internal
        // firmware, and the system ROM, which reset maps over the language card.
        Ranges(MemoryMap.Capture(Apple2(Apple2Model.IIeEnhanced))).Should().Equal(
            "0000-BFFF Ram", "C000-C0FF Io", "C100-C2FF None", "C300-C3FF Rom", "C400-CFFF None", "D000-FFFF Rom");

        // Coco.md: RAM, Extended and Color BASIC, no cartridge, the PIAs, the SAM, and the vectors.
        Ranges(MemoryMap.Capture(Coco(CocoModel.Coco2))).Should().Equal(
            "0000-7FFF Ram", "8000-BFFF Rom", "C000-FEFF None", "FF00-FF3F Io", "FF40-FFBF None", "FFC0-FFDF Io",
            "FFE0-FFFF Rom");
    }

    /// <summary>
    ///  The states the ROMs run in: the IIe's firmware with its internal ROM switched over the slots, and a CoCo 3
    ///  running BASIC from RAM, as its reset leaves it.
    /// </summary>
    [TestMethod]
    public void RunningMapsFollowTheSwitches()
    {
        Apple2Machine apple = Apple2(Apple2Model.IIeEnhanced);
        apple.Bus.Write(0xC007, 0);                     // SETINTCXROM
        Ranges(MemoryMap.Capture(apple)).Should().Equal("0000-BFFF Ram", "C000-C0FF Io", "C100-FFFF Rom");

        CocoMachine coco3 = Coco(CocoModel.Coco3);
        coco3.Bus.Write(0xFF90, 0xCA);                  // INIT0: CoCo compatible, the MMU on, constant page, 32K ROM
        coco3.Bus.Write(0xFFDF, 0);                     // the SAM's all-RAM map type
        Ranges(MemoryMap.Capture(coco3)).Should().Equal("0000-FEFF Ram", "FF00-FFDF Io", "FFE0-FFFF Rom");
    }

    /// <summary>
    ///  A map from ranges leaves the rest unmapped, and a later range wins.
    /// </summary>
    [TestMethod]
    public void RangesBuildMaps()
    {
        MemoryMap map = MemoryMap.FromRanges([(0x0000, 0x7FFF, MemoryKind.Ram), (0x8000, 0xFFFF, MemoryKind.Rom), (0xC000, 0xC0FF, MemoryKind.Io)]);
        Ranges(map).Should().Equal("0000-7FFF Ram", "8000-BFFF Rom", "C000-C0FF Io", "C100-FFFF Rom");
        Ranges(MemoryMap.AllRam).Should().Equal("0000-FFFF Ram");
        Ranges(MemoryMap.FromRanges([(0x1000, 0x1FFF, MemoryKind.Rom)])).Should().Equal(
            "0000-0FFF None", "1000-1FFF Rom", "2000-FFFF None");
    }

    private static List<(string Name, MemoryKind Kind)> Kinds(IMachine machine) =>
        [.. machine.MemoryAreas.Select((name, area) => (name, machine.AreaKind(area)))];

    private static List<string> Ranges(MemoryMap map) =>
        [.. map.Ranges().Select(range => $"{range.First:X4}-{range.Last:X4} {range.Kind}")];

    private static Apple2Machine Apple2(Apple2Model model) => new(model, new Apple2Roms(new byte[16384], new byte[4096]));

    private static CocoMachine Coco(CocoModel model)
    {
        CocoConfiguration configuration = new() { Model = model };
        CocoRoms roms = model == CocoModel.Coco3
            ? CocoRoms.ForCoco3(new byte[32768])
            : CocoRoms.ForCoco12(new byte[8192], new byte[8192]);

        return new(configuration, roms);
    }

    private static BbcRoms BbcRoms()
    {
        BbcRoms roms = new(new byte[16384], new byte[960]);
        roms.Fit(0, new byte[16384]);
        roms.Fit(3, new byte[16384]);
        return roms;
    }
}
