// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Expansion Interface's disk controller, driven through its registers as a DOS drives it, and the JV1 and
///  JV3 image formats.
/// </summary>
[TestClass]
public class Trs80DiskTests
{
    private const ushort Command = 0x37EC;
    private const ushort TrackRegister = 0x37ED;
    private const ushort SectorRegister = 0x37EE;
    private const ushort DataRegister = 0x37EF;

    /// <summary>
    ///  Restore and seek move the head; read sector returns the sector's bytes through DRQ.
    /// </summary>
    [TestMethod]
    public void ReadsSectorsAfterSeeking()
    {
        Trs80Bus bus = Bus(Jv1(35));
        Issue(bus, 0x03);
        Wait(bus);
        (bus.Read(Command) & 0x04).Should().NotBe(0, "track 0");

        bus.Write(DataRegister, 5);
        Issue(bus, 0x13);
        Wait(bus);
        bus.Disks.Cylinder(0).Should().Be(5);
        bus.Read(TrackRegister).Should().Be(5);

        bus.Write(SectorRegister, 3);
        Issue(bus, 0x88);
        (byte[] data, byte status) = Transfer(bus, read: true);
        data.Should().Equal(Pattern(5, 3));
        status.Should().Be(0);
        bus.Disks.InterruptRequest.Should().BeTrue();
        (bus.Read(0x37E0) & 0x40).Should().NotBe(0, "the latch shows the controller's interrupt");
        bus.Read(Command);
        bus.Disks.InterruptRequest.Should().BeFalse("reading status clears it");
    }

    /// <summary>
    ///  A missing sector ends with record not found; an unread byte is lost data; track 17 reports its mark.
    /// </summary>
    [TestMethod]
    public void ReportsReadErrorsAndRecordTypes()
    {
        Trs80Bus bus = Bus(Jv1(35));
        bus.Write(SectorRegister, 12);
        Issue(bus, 0x88);
        Wait(bus);
        (bus.Read(Command) & 0x10).Should().NotBe(0, "record not found");

        bus.Write(SectorRegister, 0);
        Issue(bus, 0x88);
        Wait(bus);
        (bus.Read(Command) & 0x04).Should().NotBe(0, "lost data");

        bus.Write(DataRegister, 17);
        Issue(bus, 0x13);
        Wait(bus);
        bus.Write(SectorRegister, 0);
        Issue(bus, 0x88);
        (_, byte status) = Transfer(bus, read: true);
        (status & 0x60).Should().Be(0x20, "the directory's $FA mark");
    }

    /// <summary>
    ///  Write sector stores the program's bytes and mark; a protected disk refuses.
    /// </summary>
    [TestMethod]
    public void WritesSectors()
    {
        FloppyDisk disk = Jv1(35);
        Trs80Bus bus = Bus(disk);
        byte[] data = [.. Enumerable.Range(0, 256).Select(index => (byte)(255 - index))];
        bus.Write(SectorRegister, 7);
        Issue(bus, 0xA9);
        Transfer(bus, read: false, data).Status.Should().Be(0);
        FloppySector sector = disk.Track(0, 0).Single(candidate => candidate.Sector == 7);
        sector.Data.Should().Equal(data);
        sector.DataAddressMark.Should().Be(0xFA, "a1 a0 = 01");

        disk.WriteProtected = true;
        Issue(bus, 0xA8);
        Wait(bus);
        (bus.Read(Command) & 0x40).Should().NotBe(0);
    }

    /// <summary>
    ///  Read address returns the next ID field and copies its track into the sector register.
    /// </summary>
    [TestMethod]
    public void ReadsAddresses()
    {
        Trs80Bus bus = Bus(Jv1(35));
        bus.Write(DataRegister, 2);
        Issue(bus, 0x13);
        Wait(bus);
        Issue(bus, 0xC4);
        (byte[] id, byte status) = Transfer(bus, read: true);
        status.Should().Be(0);
        id[0].Should().Be(2);
        id[3].Should().Be(1, "256-byte sectors");
        bus.Read(SectorRegister).Should().Be(2);
    }

    /// <summary>
    ///  Write track formats a track from the program's stream of marks and data.
    /// </summary>
    [TestMethod]
    public void FormatsTracks()
    {
        FloppyDisk disk = Jv1(35);
        Trs80Bus bus = Bus(disk);
        List<byte> stream = [];
        for (byte sector = 0; sector < 5; sector++)
        {
            stream.AddRange(Enumerable.Repeat((byte)0xFF, 10));
            stream.AddRange([0xFE, 0, 0, sector, 1, 0xF7]);
            stream.AddRange(Enumerable.Repeat((byte)0xFF, 11));
            stream.Add(0xFB);
            stream.AddRange(Enumerable.Repeat((byte)(0xE0 + sector), 256));
            stream.Add(0xF7);
        }

        Issue(bus, 0xF4);
        Transfer(bus, read: false, [.. stream], padding: 0xFF).Status.Should().Be(0);
        IReadOnlyList<FloppySector> track = disk.Track(0, 0);
        track.Should().HaveCount(5);
        track[3].Data.Should().AllSatisfy(value => value.Should().Be(0xE3));
    }

    /// <summary>
    ///  A Percom doubler's $FF selects double density, which reads double-density sectors twice as fast.
    /// </summary>
    [TestMethod]
    public void DoublerReadsDoubleDensity()
    {
        FloppyDisk disk = new();
        for (byte sector = 0; sector < 18; sector++)
        {
            disk.Add(0, 0, new(0, 0, sector, [.. Enumerable.Repeat((byte)sector, 256)], doubleDensity: true));
        }

        Trs80Bus bus = Bus(disk, Trs80Doubler.Percom);
        bus.Write(SectorRegister, 9);
        Issue(bus, 0x88);
        Wait(bus);
        (bus.Read(Command) & 0x10).Should().NotBe(0, "single density finds no double-density sector");

        Issue(bus, 0xFF);
        bus.Disks.DoubleDensity.Should().BeTrue();
        Issue(bus, 0x88);
        (byte[] data, byte status) = Transfer(bus, read: true);
        status.Should().Be(0);
        data.Should().AllSatisfy(value => value.Should().Be(9));
    }

    /// <summary>
    ///  The Radio Shack doubler selects its WD1791 with $80 in the sector register and the FD1771 with $A0; a
    ///  Percom select means nothing to it.
    /// </summary>
    [TestMethod]
    public void TandyDoublerSelectsThroughTheSectorRegister()
    {
        FloppyDisk disk = new();
        for (byte sector = 0; sector < 18; sector++)
        {
            disk.Add(0, 0, new(0, 0, sector, [.. Enumerable.Repeat((byte)sector, 256)], doubleDensity: true));
        }

        Trs80Bus bus = Bus(disk, Trs80Doubler.Tandy);
        Issue(bus, 0xFF);
        bus.Disks.DoubleDensity.Should().BeFalse("the Percom select is a command to this doubler's FD1771");
        Issue(bus, 0xD0);
        bus.Write(SectorRegister, 0x80);
        bus.Disks.DoubleDensity.Should().BeTrue();
        bus.Write(SectorRegister, 4);
        Issue(bus, 0x88);
        (byte[] data, byte status) = Transfer(bus, read: true);
        status.Should().Be(0);
        data.Should().AllSatisfy(value => value.Should().Be(4));

        bus.Write(SectorRegister, 0xA0);
        bus.Disks.DoubleDensity.Should().BeFalse();
        bus.Disks.Sector.Should().Be(0xA0, "the value still reaches the sector register");

        Trs80Bus both = Bus(disk, Trs80Doubler.Both);
        Issue(both, 0xFF);
        both.Disks.DoubleDensity.Should().BeTrue();
        both.Write(SectorRegister, 0xA0);
        both.Disks.DoubleDensity.Should().BeFalse();
    }

    /// <summary>
    ///  Bit 3 of the select latch with drive 0, 1 or 2 selects side 1 of that drive; alone it selects drive 3.
    /// </summary>
    [TestMethod]
    public void SelectLatchBitThreeSelectsSideOne()
    {
        FloppyDisk disk = new();
        disk.Add(0, 0, new(0, 0, 1, [.. Enumerable.Repeat((byte)0x10, 256)], doubleDensity: false));
        disk.Add(0, 1, new(0, 1, 1, [.. Enumerable.Repeat((byte)0x11, 256)], doubleDensity: false));
        Trs80Bus bus = Bus(disk);
        bus.Disks.Insert(3, Jv1(35));

        bus.Write(0x37E1, 0x09);
        bus.Disks.SelectedDrive.Should().Be(0);
        bus.Disks.Side.Should().Be(1);
        bus.Write(SectorRegister, 1);
        bus.Write(Command, 0x88);
        bus.Tick();
        (byte[] data, byte status) = SideTransfer(bus, latch: 0x09);
        status.Should().Be(0);
        data.Should().AllSatisfy(value => value.Should().Be(0x11));

        bus.Write(0x37E1, 0x01);
        bus.Disks.Side.Should().Be(0);
        bus.Write(Command, 0x88);
        bus.Tick();
        (data, _) = SideTransfer(bus, latch: 0x01);
        data.Should().AllSatisfy(value => value.Should().Be(0x10));

        bus.Write(0x37E1, 0x08);
        bus.Disks.SelectedDrive.Should().Be(3);
        bus.Disks.Side.Should().Be(0);
    }

    // Reads a sector while the DOS keeps rewriting the select latch to hold the drive and side.
    private static (byte[] Data, byte Status) SideTransfer(Trs80Bus bus, byte latch)
    {
        List<byte> bytes = [];
        for (int cycle = 0; cycle < 10 * Trs80Timing.ClockHertz && bus.Disks.IsBusy; cycle++)
        {
            if (cycle % 100_000 == 0) { bus.Write(0x37E1, latch); }
            bus.Tick();
            if ((bus.Disks.Peek(0) & 0x02) != 0) { bytes.Add(bus.Read(DataRegister)); }
        }

        return ([.. bytes], bus.Disks.Peek(0));
    }

    /// <summary>
    ///  JV1 and JV3 images survive a round trip, JV3 with density, side, mark, error and protection.
    /// </summary>
    [TestMethod]
    public void ImagesRoundTrip()
    {
        byte[] jv1 = Jv1Format.Write(Jv1(40));
        jv1.Should().HaveCount(40 * 2560);
        Jv1Format.Write(Jv1Format.Read(jv1)).Should().Equal(jv1);
        Jv1Format.Read(jv1).Track(17, 0)[0].DataAddressMark.Should().Be(0xFA);

        FloppyDisk disk = new() { WriteProtected = true };
        disk.Add(0, 0, new(0, 0, 1, new byte[256], doubleDensity: false, 0xF8));
        disk.Add(0, 1, new(0, 1, 1, new byte[512], doubleDensity: true, 0xF8) { CrcError = true });
        disk.Add(1, 0, new(1, 0, 1, new byte[128], doubleDensity: false, 0xF9));
        byte[] jv3 = Jv3Format.Write(disk);
        jv3.Should().HaveCount(8704 + 256 + 512 + 128);
        FloppyDisk read = Jv3Format.Read(jv3);
        read.WriteProtected.Should().BeTrue();
        read.Track(0, 0)[0].DataAddressMark.Should().Be(0xF8);
        read.Track(0, 1)[0].DoubleDensity.Should().BeTrue();
        read.Track(0, 1)[0].CrcError.Should().BeTrue();
        read.Track(0, 1)[0].Data.Length.Should().Be(512);
        read.Track(1, 0)[0].DataAddressMark.Should().Be(0xF9);
        Jv3Format.Write(read).Should().Equal(jv3);

        Action truncated = () => Jv3Format.Read(jv3.AsSpan(0, jv3.Length - 1));
        truncated.Should().Throw<InvalidDataException>();
    }

    private static Trs80Bus Bus(FloppyDisk disk, Trs80Doubler doubler = Trs80Doubler.None)
    {
        Trs80Bus bus = Trs80MachineTests.Create(new() { Doubler = doubler }).Bus;
        bus.Disks.Insert(0, disk);
        bus.Write(0x37E1, 0x01);
        return bus;
    }

    // Writes a command, keeping the drive selected as a DOS does.
    private static void Issue(Trs80Bus bus, byte command)
    {
        bus.Write(0x37E1, 0x01);
        bus.Write(Command, command);
        bus.Tick();
    }

    private static void Wait(Trs80Bus bus)
    {
        for (int cycle = 0; cycle < 10 * Trs80Timing.ClockHertz && bus.Disks.IsBusy; cycle++) { bus.Tick(); }
        bus.Disks.IsBusy.Should().BeFalse();
    }

    // Moves bytes on each DRQ, as the DOS's polling loop does, until the command ends.
    private static (byte[] Data, byte Status) Transfer(Trs80Bus bus, bool read, byte[]? data = null, byte padding = 0)
    {
        List<byte> bytes = [];
        int next = 0;
        for (int cycle = 0; cycle < 10 * Trs80Timing.ClockHertz && bus.Disks.IsBusy; cycle++)
        {
            bus.Tick();
            if ((bus.Disks.Peek(0) & 0x02) == 0) { continue; }
            if (read) { bytes.Add(bus.Read(DataRegister)); }
            else { bus.Write(DataRegister, data is not null && next < data.Length ? data[next++] : padding); }
        }

        return ([.. bytes], bus.Disks.Peek(0));
    }

    private static FloppyDisk Jv1(int tracks)
    {
        byte[] image = new byte[tracks * 2560];
        for (int track = 0; track < tracks; track++)
        {
            for (int sector = 0; sector < 10; sector++)
            {
                Pattern(track, sector).CopyTo(image, (track * 2560) + (sector * 256));
            }
        }

        return Jv1Format.Read(image);
    }

    private static byte[] Pattern(int track, int sector) =>
        [.. Enumerable.Range(0, 256).Select(index => (byte)((track * 16) + sector + index))];
}
