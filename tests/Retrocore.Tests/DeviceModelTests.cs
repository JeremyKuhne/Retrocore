// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;
using Retrocore.Media;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Each machine lists its installed devices, with metadata and live state.
/// </summary>
[TestClass]
public class DeviceModelTests
{
    private const ushort Command = 0x37EC;
    private const ushort SectorRegister = 0x37EE;
    private const ushort DataRegister = 0x37EF;

    /// <summary>
    ///  A Model I lists its cassette and, with the disk controller, four drives.
    /// </summary>
    [TestMethod]
    public void ModelIListsItsDevices()
    {
        Trs80Machine machine = Trs80MachineTests.Create(new() { Doubler = Trs80Doubler.Tandy });
        machine.Devices.Select(device => device.Id).Should().Equal("cassette", "disk0", "disk1", "disk2", "disk3");
        machine.Devices.Select(device => device.Kind).Should().Equal(
            DeviceKind.TapeDrive,
            DeviceKind.FloppyDrive,
            DeviceKind.FloppyDrive,
            DeviceKind.FloppyDrive,
            DeviceKind.FloppyDrive);

        DeviceInfo drive = machine.Drives[0].Info;
        drive.Name.Should().Be("Drive 0");
        drive.Controller.Should().Contain("Radio Shack");
        drive.Formats.Should().Contain("jv3");
        drive.Operations.Should().HaveFlag(MediaOperations.WriteProtect);
        drive.Sides.Should().Be(2);
        machine.Drives[3].Info.Sides.Should().Be(1, "drive 3's select is the other drives' side select");
        machine.Cassette.Info.Operations.Should().HaveFlag(MediaOperations.Record);
        machine.Drives.Should().AllSatisfy(candidate => candidate.Media.Should().BeNull());

        Trs80Machine bare = Trs80MachineTests.Create(new() { DiskController = false });
        bare.Devices.Select(device => device.Id).Should().Equal("cassette");
    }

    /// <summary>
    ///  A drive reports its media, its head and what the controller does with it: seeking, reading, then a
    ///  write that marks the disk changed.
    /// </summary>
    [TestMethod]
    public void ModelIDriveReportsItsState()
    {
        Trs80Machine machine = Trs80MachineTests.Create(new());
        Trs80Bus bus = machine.Bus;
        FloppyDisk disk = new();
        for (int track = 0; track < 3; track++)
        {
            for (byte sector = 0; sector < 10; sector++)
            {
                disk.Add(track, 0, new((byte)track, 0, sector, new byte[256], doubleDensity: false));
            }
        }

        Trs80FloppyDrive drive = machine.Drives[0];
        drive.Insert(disk, "games.dsk", "JV1");
        drive.Media.Should().Be(new MediaState("games.dsk", "JV1", WriteProtected: false, Changed: false));
        drive.Head.Motor.Should().BeFalse();

        bus.Write(0x37E1, 0x01);
        drive.Head.Should().Be(new DiskHead(Motor: true, Selected: true, Track: 0, Side: 0, Sector: null));
        machine.Drives[1].Head.Selected.Should().BeFalse();

        // Seek to track 2: the head steps, then rests.
        bus.Write(DataRegister, 2);
        bus.Write(Command, 0x10);
        bus.Tick();
        drive.Activity.Should().Be(DeviceActivity.Seeking);
        Run(bus);
        drive.Activity.Should().Be(DeviceActivity.Idle);
        drive.Head.Track.Should().Be(2);

        // Read sector 4: the controller shows the sector while it reads.
        bus.Write(SectorRegister, 4);
        bus.Write(Command, 0x88);
        bus.Tick();
        drive.Activity.Should().Be(DeviceActivity.Reading);
        drive.Head.Sector.Should().Be(4);
        Run(bus);

        // Write sector 5: the disk has changed.
        bus.Write(SectorRegister, 5);
        bus.Write(Command, 0xA8);
        bus.Tick();
        drive.Activity.Should().Be(DeviceActivity.Writing);
        Run(bus);
        drive.Media?.Changed.Should().BeTrue();

        drive.SetWriteProtected(writeProtected: true);
        disk.WriteProtected.Should().BeTrue();
        drive.Media?.WriteProtected.Should().BeTrue();

        bus.Write(0x37E1, 0x09);
        drive.Head.Side.Should().Be(1, "bit 3 with drive 0 selects side 1");
        drive.Eject().Should().BeSameAs(disk);
        drive.Media.Should().BeNull();
    }

    /// <summary>
    ///  The cassette reports its tape and transport, and reads while the motor runs.
    /// </summary>
    [TestMethod]
    public void ModelICassetteReportsItsTransport()
    {
        Trs80Machine machine = Trs80MachineTests.Create(new());
        Trs80CassetteDrive cassette = machine.Cassette;
        cassette.Media.Should().BeNull();
        cassette.Transport.Mode.Should().Be(TapeMode.Stopped);

        cassette.Play(new CassetteImage([0x00, 0x00, 0xA5, 0x55]), "program.cas");
        cassette.Media.Should().Be(new MediaState("program.cas", "CAS", WriteProtected: true, Changed: false));
        cassette.Transport.Should().Be(new TapeTransport(Motor: false, TapeMode.Playing, Position: 0, Length: 4));
        cassette.Activity.Should().Be(DeviceActivity.Idle);

        machine.Bus.Out(0xFF, 0x04);
        cassette.Activity.Should().Be(DeviceActivity.Reading);

        // Each pulse waits until the program clears the latch, as the ROM does by writing the port.
        for (int cycle = 0; cycle < machine.Bus.Cassette.CellCycles * 8 * 2; cycle++)
        {
            machine.Bus.Tick();
            if ((machine.Bus.In(0xFF) & 0x80) != 0) { machine.Bus.Out(0xFF, 0x04); }
        }

        cassette.Transport.Position.Should().BeGreaterThan(0);

        cassette.Record(new CassetteImage(), "out.cas");
        cassette.Activity.Should().Be(DeviceActivity.Writing);
        cassette.Media?.WriteProtected.Should().BeFalse();
        cassette.Eject().Should().NotBeNull();
        cassette.Media.Should().BeNull();
    }

    /// <summary>
    ///  A IIe lists its slot 7 block device, and the Disk II drives once the card's firmware is installed.
    /// </summary>
    [TestMethod]
    public void IIeListsItsDevices()
    {
        byte[] system = new byte[16384];
        Array.Fill(system, (byte)0xAA);
        MemoryBlockDevice image = new(new byte[280 * 512], isReadOnly: false);
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, new(system, new byte[4096]), image);
        machine.Devices.Select(device => device.Id).Should().Equal("slot7");
        Apple2BlockStorage storage = machine.BlockStorage ?? throw new AssertFailedException("slot 7 is empty");
        storage.Label = "boot.po";
        storage.Media.Should().Be(new MediaState("boot.po", "PO", WriteProtected: false, Changed: false));
        storage.BlockCount.Should().Be(280);
        storage.LastBlock.Should().BeNull();
        storage.Activity.Should().Be(DeviceActivity.Idle);
        storage.Info.Operations.Should().Be(MediaOperations.None);

        machine.Drives.Select(drive => drive.Info.Name).Should().Equal("Drive 1", "Drive 2");
        machine.Drives[0].Media.Should().BeNull();
        new Apple2Machine(Apple2Model.IIeEnhanced, new(system, new byte[4096])).Devices.Should().BeEmpty();
    }

    // Runs until the controller finishes, moving data on each request as a DOS does.
    private static void Run(Trs80Bus bus)
    {
        for (int cycle = 0; cycle < 10 * Trs80Timing.ClockHertz && bus.Disks.IsBusy; cycle++)
        {
            bus.Tick();
            if ((bus.Disks.Peek(0) & 0x02) == 0) { continue; }
            if ((bus.Disks.LastCommand & 0xE0) == 0xA0) { bus.Write(DataRegister, 0x5A); }
            else { bus.Read(DataRegister); }
        }

        bus.Disks.IsBusy.Should().BeFalse();
    }
}
