// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies Disk II cards put in and taken out of the IIe's slots: where they answer, booting from one, and the
///  devices the machine lists.
/// </summary>
[TestClass]
public sealed class Apple2SlotTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  With slot 6 empty, the firmware's startup scan finds a Disk II in slot 5 and boots its disk, and the boot ROM
    ///  passes slot 5 to the boot sector.
    /// </summary>
    [TestMethod]
    public void BootsFromADiskIIInSlotFive()
    {
        Apple2Machine machine = Machine();
        machine.Bus.InstallDiskII(slot: 5, Firmware());
        machine.DrivesIn(5)[0].Insert(SectorDiskConverter.Convert(BootImage(), proDosOrder: false), "boot", "DSK");
        machine.Reset();

        machine.Bus.Peek(0xC5FF).Should().Be(0x00, "the 16-sector boot ROM is in slot five");
        for (int second = 0; second < 5 && machine.Bus.Peek(0x07) != 0xA5; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0x07).Should().Be(0xA5, "the boot sector ran");
        machine.Bus.Peek(0x06).Should().Be(0x50, "the boot ROM passes slot * 16 in X");
    }

    /// <summary>
    ///  A card answers at $C080 plus 16 times its slot and at its ROM page, and nowhere else.
    /// </summary>
    [TestMethod]
    public void AnswersAtItsSlotsAddresses()
    {
        Apple2Machine machine = Machine();
        DiskIIController card = machine.Bus.InstallDiskII(slot: 2, Firmware());
        machine.Bus.Peek(0xC2FF).Should().Be(0x00);
        machine.Bus.Peek(0xC6FF).Should().Be(0xFF, "slot six is empty");

        machine.Bus.Read(0xC0E9);
        card.State(drive: 1).Motor.Should().BeFalse("slot six's motor switch is not this card's");
        machine.Bus.Read(0xC0A9);
        card.State(drive: 1).Motor.Should().BeTrue("$C0A9 turns slot two's motor on");
        machine.Bus.ReadArea(0xC280).Should().Be(Apple2MemoryArea.Slot2Rom);
        machine.Bus.PeekArea(Apple2MemoryArea.Slot2Rom, 0xC2FF, out byte value).Should().BeTrue();
        value.Should().Be(0x00);
    }

    /// <summary>
    ///  Taking a card out ejects its disks and leaves its slot empty; its drives leave the machine's devices.
    /// </summary>
    [TestMethod]
    public void RemovingACardEjectsItsDisks()
    {
        Apple2Machine machine = Machine();
        machine.Bus.InstallDiskII(slot: 6, Firmware());
        machine.Bus.InstallDiskII(slot: 5, Firmware());
        machine.DrivesIn(5)[1].Insert(SectorDiskConverter.Convert(BootImage(), proDosOrder: false), "data", "DSK");
        Ids(machine).Should().Equal("slot5disk1", "slot5disk2", "disk1", "disk2");
        machine.DrivesIn(5)[1].Info.Name.Should().Be("Slot 5, drive 2");
        machine.DrivesIn(6).Should().Equal(machine.Drives, "slot six keeps its drives");

        DiskIIController card = machine.Bus.DiskIIIn(5) ?? throw new AssertFailedException("Slot 5 has no card.");
        machine.Bus.RemoveDiskII(slot: 5);
        card.State(drive: 2).Mounted.Should().BeFalse("its disk was ejected");
        machine.Bus.DiskIIIn(5).Should().BeNull();
        machine.Bus.Peek(0xC5FF).Should().Be(0xFF);
        Ids(machine).Should().Equal("disk1", "disk2");

        machine.Bus.RemoveDiskII(slot: 6);
        Ids(machine).Should().BeEmpty();
        machine.Bus.IsSlotFree(6).Should().BeTrue();
    }

    /// <summary>
    ///  Slots 3 and 4 are never free, nor slot 7 with the block device, nor a slot with a card.
    /// </summary>
    [TestMethod]
    public void OnlyFreeSlotsTakeACard()
    {
        Apple2Machine machine = Machine();
        int[] slots = [1, 2, 3, 4, 5, 6, 7];
        slots.Select(machine.Bus.IsSlotFree).Should().Equal(true, true, false, true, true, true, true);
        machine.Bus.InstallDiskII(slot: 1, Firmware());
        Action again = () => machine.Bus.InstallDiskII(slot: 1, Firmware());
        again.Should().Throw<InvalidOperationException>();
        machine.Bus.InstallMockingboard();
        machine.Bus.IsSlotFree(4).Should().BeFalse("the Mockingboard is in slot 4");
        Action mockingboard = () => machine.Bus.InstallDiskII(slot: 4, Firmware());
        mockingboard.Should().Throw<InvalidOperationException>();
        Action empty = () => machine.Bus.RemoveDiskII(slot: 2);
        empty.Should().Throw<InvalidOperationException>();

        Apple2Machine withBlocks = new(Apple2Model.IIeEnhanced, Roms(), new MemoryBlockDevice(new byte[512 * 280]));
        withBlocks.Bus.IsSlotFree(7).Should().BeFalse("slot 7 holds the block device");
    }

    private static Apple2Machine Machine() => new(Apple2Model.IIeEnhanced, Roms());

    private static Apple2Roms Roms() => SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs);

    private static DiskIIFirmware Firmware() => SdkModules.BuildDiskII(sectors: 16, s_inputs);

    private static string[] Ids(Apple2Machine machine) => [.. machine.Devices.Select(device => device.Id)];

    // A DOS-order image whose boot sector stores X and a mark, then waits.
    private static byte[] BootImage()
    {
        byte[] image = new byte[35 * 16 * 256];
        byte[] boot =
        [
            0x01,                   // one sector to read
            0x86, 0x06,             // stx $06
            0xA9, 0xA5,             // lda #$A5
            0x85, 0x07,             // sta $07
            0x4C, 0x07, 0x08        // jmp $0807
        ];

        boot.CopyTo(image, 0);
        return image;
    }
}
