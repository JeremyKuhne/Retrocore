// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Apple II's ProFile card: its firmware's identification, its ProDOS block driver run on each model's
///  processor against the emulated ProFile, and booting from it.
/// </summary>
[TestClass]
public sealed class Apple2ProFileTests
{
    private const ushort Caller = 0x2000;
    private const ushort Buffer = 0x4000;
    private const uint Blocks = 1600;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The card's page carries ProDOS's identification bytes and points ProDOS at its driver, in whatever slot.
    /// </summary>
    /// <param name="slot">The card's slot.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(5)]
    [DataRow(7)]
    public void FirmwareIdentifiesABlockDevice(int slot)
    {
        (Apple2Machine machine, _) = Machine(Apple2Model.IIeEnhanced, slot);
        ushort page = (ushort)(0xC000 | (slot << 8));
        machine.Bus.Peek((ushort)(page + 1)).Should().Be(0x20);
        machine.Bus.Peek((ushort)(page + 3)).Should().Be(0x00);
        machine.Bus.Peek((ushort)(page + 5)).Should().Be(0x03);
        machine.Bus.Peek((ushort)(page + 7)).Should().Be(0x3C, "not a SmartPort");
        machine.Bus.Peek((ushort)(page + 0xFF)).Should().Be(ProFileRom.Driver & 0xFF);
        machine.Bus.Peek((ushort)(page + 0xFE)).Should().Be(0x0F, "status, read, write and format, one volume");
        machine.Bus.ReadArea(page).Should().Be(Apple2MemoryArea.Slot1Rom + (slot - 1));
        machine.Bus.IsSlotFree(slot).Should().BeFalse();
        ProFileRom.Bytes.Length.Should().Be(256);
    }

    /// <summary>
    ///  STATUS gives the ProFile's size in X and Y; READ fills the buffer with the block; WRITE stores the buffer.
    /// </summary>
    /// <param name="model">The model, whose processor runs the firmware.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    [DataRow(Apple2Model.IIPlus)]
    public void ReadsWritesAndReportsStatus(Apple2Model model)
    {
        (Apple2Machine machine, MemoryBlockDevice image) = Machine(model, slot: 5);

        ProcessorRegisters status = Call(machine, command: 0, unit: 0x50, block: 0);
        status.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        status.Accumulator.Should().Be(0);
        (status.X | (status.Y << 8)).Should().Be((int)Blocks);

        ProcessorRegisters read = Call(machine, command: 1, unit: 0x50, block: 1234);
        read.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        byte[] expected = new byte[512];
        image.ReadBlock(1234, expected);
        Memory(machine, Buffer, 512).Should().Equal(expected);
        Memory(machine, 0x44, 2).Should().Equal([0x00, 0x40], "the buffer pointer is left as it was");

        for (int i = 0; i < 512; i++) { machine.Bus.SetRam(auxiliary: false, (ushort)(Buffer + i), (byte)(i ^ 0x3C)); }
        ProcessorRegisters write = Call(machine, command: 2, unit: 0x50, block: 77);
        write.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        byte[] written = new byte[512];
        image.ReadBlock(77, written);
        written.Should().Equal(Memory(machine, Buffer, 512));

        ProFileDrive drive = Drive(machine, 5);
        drive.LastBlock.Should().Be(77);
        drive.Media.GetValueOrDefault().Changed.Should().BeTrue();
    }

    /// <summary>
    ///  FORMAT succeeds and does nothing; a block past the end, a read-only image's write and a slot with no
    ///  ProFile cabled each answer with ProDOS's error.
    /// </summary>
    [TestMethod]
    public void ReportsErrors()
    {
        (Apple2Machine machine, _) = Machine(Apple2Model.IIeEnhanced, slot: 5);
        Error(Call(machine, command: 3, unit: 0x50, block: 0)).Should().Be(0);
        Error(Call(machine, command: 1, unit: 0x50, block: (ushort)Blocks)).Should().Be(0x27, "the block is past the end");
        Error(Call(machine, command: 1, unit: 0x50, block: 0)).Should().Be(0, "the ProFile is ready again");

        ProFileDrive drive = Drive(machine, 5);
        drive.Insert(new MemoryBlockDevice(new byte[512 * 8]), "read-only", "PO");
        Error(Call(machine, command: 2, unit: 0x50, block: 0)).Should().Be(0x27);

        drive.Eject();
        Error(Call(machine, command: 1, unit: 0x50, block: 0)).Should().Be(0x28);
    }

    /// <summary>
    ///  With nothing in slots 6 and 7, the IIe's startup scan finds the ProFile in slot 5 and boots it: block 0 runs at
    ///  $0801 with X = the slot times 16.
    /// </summary>
    [TestMethod]
    public void BootsFromTheStartupScan()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        byte[] blocks = new byte[512 * 280];
        byte[] boot =
        [
            0x01,                   // ProDOS's boot blocks start with a 1
            0x86, 0x06,             // STX $06
            0xA9, 0xA5,             // LDA #$A5
            0x85, 0x07,             // STA $07
            0x4C, 0x07, 0x08        // JMP *
        ];

        boot.CopyTo(blocks, 0);
        machine.Bus.InstallProFile(5).Drive.Insert(new MemoryBlockDevice(blocks), "boot", "PO");
        machine.Reset();

        for (int second = 0; second < 5 && machine.Bus.Peek(0x07) != 0xA5; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0x07).Should().Be(0xA5, "block 0 ran");
        machine.Bus.Peek(0x06).Should().Be(0x50, "the firmware passes slot * 16 in X");
    }

    /// <summary>
    ///  A ProFile with no image fails its boot and the startup scan goes on to the next lower slot, as for an empty
    ///  Disk II drive: here it boots the Disk II in slot 6.
    /// </summary>
    [TestMethod]
    public void FailedBootGoesOnWithTheScan()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.InstallProFile(7);
        machine.Bus.InstallDiskII(6, SdkModules.BuildDiskII(sectors: 16, s_inputs));
        byte[] image = new byte[35 * 16 * 256];
        byte[] boot =
        [
            0x01,                   // one sector to read
            0x86, 0x06,             // STX $06
            0xA9, 0xA5,             // LDA #$A5
            0x85, 0x07,             // STA $07
            0x4C, 0x07, 0x08        // JMP *
        ];

        boot.CopyTo(image, 0);
        machine.Drives[0].Insert(SectorDiskConverter.Convert(image, proDosOrder: false), "boot", "DSK");
        machine.Reset();

        for (int second = 0; second < 5 && machine.Bus.Peek(0x07) != 0xA5; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0x07).Should().Be(0xA5, "the Disk II's boot sector ran");
        machine.Bus.Peek(0x06).Should().Be(0x60, "slot 6 booted");
    }

    /// <summary>
    ///  ProDOS boots from the ProFile and lists it among its devices, with A2DeskTop's first disk as the ProFile's
    ///  image (in <c>%USERPROFILE%\Retrocore\disks\a2desktop</c>).
    /// </summary>
    [TestMethod]
    public void BootsProDos()
    {
        string path = Path.Join(ExternalTestData.Root, "disks", "a2desktop", "A2DeskTop-1.5-en_140k_disk1.po");
        if (!File.Exists(path)) { Assert.Inconclusive($"{path} is missing."); }

        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.InstallProFile(7).Drive.Insert(new MemoryBlockDevice(File.ReadAllBytes(path), isReadOnly: false), path, "PO");
        machine.Reset();

        // ProDOS's global page: a JMP at $BF00 and the device list at $BF32, which ProDOS fills from the slots' ROMs.
        for (int second = 0; second < 10 && !Listed(machine); second++) { machine.Run(BasicMachines.IIeClock); }
        machine.Bus.Peek(0xBF00).Should().Be(0x4C, "ProDOS is in memory");
        Listed(machine).Should().BeTrue("ProDOS lists slot 7, drive 1");
        Drive(machine, 7).LastBlock.Should().BeGreaterThan(1, "ProDOS read on past the boot block");

        static bool Listed(Apple2Machine machine)
        {
            if (machine.Bus.Peek(0xBF00) != 0x4C) { return false; }
            int count = machine.Bus.Peek(0xBF31) + 1;
            for (int i = 0; i < count && i < 14; i++)
            {
                if ((machine.Bus.Peek((ushort)(0xBF32 + i)) & 0xF0) == 0x70) { return true; }
            }

            return false;
        }
    }

    /// <summary>
    ///  A card goes in only a free slot, lists its ProFile among the machine's devices, and comes out with it.
    /// </summary>
    [TestMethod]
    public void InstallsAndRemoves()
    {
        (Apple2Machine machine, _) = Machine(Apple2Model.IIeEnhanced, slot: 2);
        Action again = () => machine.Bus.InstallProFile(2);
        again.Should().Throw<InvalidOperationException>();
        machine.Devices.Select(device => device.Id).Should().Equal("slot2profile");

        machine.Bus.RemoveProFile(2);
        machine.Devices.Should().BeEmpty();
        machine.Bus.Peek(0xC2FF).Should().Be(0xFF);
        machine.Bus.IsSlotFree(2).Should().BeTrue();
        Action empty = () => machine.Bus.RemoveProFile(2);
        empty.Should().Throw<InvalidOperationException>();
    }

    private static (Apple2Machine Machine, MemoryBlockDevice Image) Machine(Apple2Model model, int slot)
    {
        byte[] system = new byte[16384];
        system[0xFF58 - 0xC000] = 0x60;    // IORTS, an RTS
        Apple2Machine machine = new(model, new Apple2Roms(system, new byte[4096]));
        machine.Run(cycles: 7);

        byte[] bytes = new byte[Blocks * 512];
        for (int i = 0; i < bytes.Length; i++) { bytes[i] = (byte)((i >> 9) + (i * 7)); }
        MemoryBlockDevice image = new(bytes, isReadOnly: false);
        machine.Bus.InstallProFile(slot).Drive.Insert(image, "test.po", "PO");
        return (machine, image);
    }

    private static ProFileDrive Drive(Apple2Machine machine, int slot) =>
        machine.Bus.ProFileIn(slot)?.Drive ?? throw new InvalidOperationException("The slot has no ProFile card.");

    private static int Error(ProcessorRegisters registers) =>
        registers.Status.HasFlag(StatusRegister.Carry) ? registers.Accumulator : 0;

    // Calls the driver as ProDOS does, with the request in the zero-page mailbox and the buffer at $4000.
    private static ProcessorRegisters Call(Apple2Machine machine, byte command, byte unit, ushort block)
    {
        int slot = (unit >> 4) & 7;
        ushort driver = (ushort)(((0xC0 | slot) << 8) | machine.Bus.Peek((ushort)(((0xC0 | slot) << 8) | 0xFF)));
        machine.Bus.SetRam(auxiliary: false, 0x42, command);
        machine.Bus.SetRam(auxiliary: false, 0x43, unit);
        machine.Bus.SetRam(auxiliary: false, 0x44, Buffer & 0xFF);
        machine.Bus.SetRam(auxiliary: false, 0x45, Buffer >> 8);
        machine.Bus.SetRam(auxiliary: false, 0x46, (byte)block);
        machine.Bus.SetRam(auxiliary: false, 0x47, (byte)(block >> 8));
        machine.Bus.SetRam(auxiliary: false, Caller, 0x20);
        machine.Bus.SetRam(auxiliary: false, Caller + 1, (byte)driver);
        machine.Bus.SetRam(auxiliary: false, Caller + 2, (byte)(driver >> 8));
        machine.Processor.Registers = new()
        {
            ProgramCounter = Caller,
            StackPointer = 0xF0,
            Status = StatusRegister.Unused
        };

        for (int i = 0; i < 20_000; i++)
        {
            machine.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            if (machine.Processor.Registers.ProgramCounter == Caller + 3)
            {
                machine.Processor.Registers.StackPointer.Should().Be(0xF0);
                return machine.Processor.Registers;
            }
        }

        throw new InvalidOperationException("The driver did not return.");
    }

    private static byte[] Memory(Apple2Machine machine, ushort address, int count)
    {
        byte[] bytes = new byte[count];
        for (int i = 0; i < count; i++) { bytes[i] = machine.Bus.Peek((ushort)(address + i)); }
        return bytes;
    }
}
