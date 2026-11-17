// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Hardware-directed sequencer tests using original toy truth tables, not Apple firmware.
/// </summary>
[TestClass]
public class DiskControllerTests
{
    /// <summary>
    ///  Checks every latch operation is performed twice per CPU clock.
    /// </summary>
    /// <param name="operation">The P6 low-nibble command.</param>
    /// <param name="expected">The result of two sequencer clocks.</param>
    [TestMethod]
    [DataRow(0, 0)]
    [DataRow(8, 0xA5)]
    [DataRow(9, 0x94)]
    [DataRow(10, 0xE9)]
    [DataRow(11, 0xA5)]
    [DataRow(12, 0xA5)]
    [DataRow(13, 0x97)]
    [DataRow(14, 0xE9)]
    [DataRow(15, 0xA5)]
    public void SequencerExecutesBothHalfClocks(int operation, int expected)
    {
        DiskIIController controller = Controller((byte)operation);
        controller.Write(offset: 13, value: 0xA5);
        controller.Write(offset: 15, value: 0xA5);
        controller.Tick();
        controller.DataLatch.Should().Be(0xA5);
        controller.Read(offset: 14, floatingBus: 0);
        controller.Read(offset: 12, floatingBus: 0);
        controller.Tick();
        controller.DataLatch.Should().Be((byte)expected);
    }

    /// <summary>
    ///  Checks all even addresses expose the data latch and peeks do not activate switches.
    /// </summary>
    [TestMethod]
    public void EvenSwitchesExposeLatchAndPeeksAreSideEffectFree()
    {
        DiskIIController controller = Controller(operation: 8);
        controller.Write(offset: 13, value: 0xA5);
        controller.Write(offset: 15, value: 0xA5);
        controller.Tick();
        for (byte offset = 0; offset < 16; offset++)
        {
            controller.Peek(offset, floatingBus: 0x31).Should().Be((offset & 1) == 0 ? (byte)0xA5 : (byte)0x31);
        }

        controller.State(drive: 1).Motor.Should().BeFalse();
        controller.Read(offset: 8, floatingBus: 0x31).Should().Be(0xA5);
        controller.Read(offset: 9, floatingBus: 0x31).Should().Be(0x31);
        controller.State(drive: 1).Motor.Should().BeTrue();
    }

    /// <summary>
    ///  Checks one-second delayed motor-off and drive selection at the current clock.
    /// </summary>
    [TestMethod]
    public void MotorOffUsesExactlyOneSecondOfMachineClocks()
    {
        DiskIIController controller = Controller(operation: 8);
        controller.Read(offset: 9, floatingBus: 0);
        controller.Read(offset: 8, floatingBus: 0);
        for (int cycle = 0; cycle < 1_020_499; cycle++) { controller.Tick(); }
        controller.State(drive: 1).Motor.Should().BeTrue();
        controller.Tick();
        controller.State(drive: 1).Motor.Should().BeFalse();
        controller.Read(offset: 9, floatingBus: 0);
        controller.Read(offset: 11, floatingBus: 0);
        controller.State(drive: 1).Motor.Should().BeFalse();
        controller.State(drive: 2).Motor.Should().BeTrue();
    }

    /// <summary>
    ///  Checks adjacent coil pulls permit quarter-track motion and selected drives retain separate heads.
    /// </summary>
    [TestMethod]
    public void StepperMovesQuarterTracksAndPreservesAngularAlignment()
    {
        DiskIIController controller = Controller(operation: 8);
        WozDisk disk = WozDisk.CreateBlank();
        disk.SetTrack(quarterTrack: 0, new byte[16], bitCount: 128);
        disk.SetTrack(quarterTrack: 1, new byte[32], bitCount: 256);
        controller.Mount(drive: 1, disk);
        controller.Read(offset: 9, floatingBus: 0);
        for (int clock = 0; clock < 80; clock++) { controller.Tick(); }
        int oldPosition = controller.State(1).BitPosition;
        controller.Read(offset: 1, floatingBus: 0);
        controller.Read(offset: 3, floatingBus: 0);
        controller.State(1).QuarterTrack.Should().Be(1);
        controller.State(1).BitPosition.Should().Be(oldPosition * 2);
        controller.Read(offset: 0, floatingBus: 0);
        controller.State(1).QuarterTrack.Should().Be(2);
        controller.Read(offset: 11, floatingBus: 0);
        controller.State(2).QuarterTrack.Should().Be(0);
        controller.State(1).QuarterTrack.Should().Be(2);
    }

    /// <summary>
    ///  Checks physical write mode changes bit storage and respects caller write protection.
    /// </summary>
    [TestMethod]
    public void WriteSequencerPersistsBitsAndRespectsProtection()
    {
        WozDisk writable = WozDisk.CreateBlank();
        writable.SetTrack(quarterTrack: 0, [255, 255], bitCount: 16);
        writable.MarkSaved();
        DiskIIController controller = Controller(operation: 8);
        controller.Mount(drive: 1, writable);
        controller.Read(offset: 9, floatingBus: 0);
        controller.Read(offset: 15, floatingBus: 0);
        for (int clock = 0; clock < 64; clock++) { controller.Tick(); }
        controller.Read(offset: 14, floatingBus: 0);
        writable.IsDirty.Should().BeTrue();
        writable.Track(0)?.Bits.ToArray().Should().NotEqual([255, 255]);
        WozDisk readOnly = WozDisk.Load(writable.Export());
        byte[] original = readOnly.Export();
        controller.Mount(drive: 1, readOnly);
        controller.Read(offset: 15, floatingBus: 0);
        for (int clock = 0; clock < 64; clock++) { controller.Tick(); }
        controller.Read(offset: 14, floatingBus: 0);
        readOnly.Export().Should().Equal(original);
    }

    /// <summary>
    ///  Checks half-clock rotation is observable independently of CPU I/O reads and allocates nothing.
    /// </summary>
    [TestMethod]
    public void RotationAdvancesWithoutReadsAndWithoutAllocations()
    {
        DiskIIController controller = Controller(operation: 8);
        WozDisk disk = WozDisk.CreateBlank();
        disk.SetTrack(quarterTrack: 0, new byte[128], bitCount: 1024);
        controller.Mount(drive: 1, disk);
        controller.Read(offset: 9, floatingBus: 0);
        controller.Tick();
        Allocations.During(() =>
        {
            for (int clock = 0; clock < 4082; clock++) { controller.Tick(); }
        }).Should().Be(0);

        controller.State(1).BitPosition.Should().BeGreaterThan(0);
    }

    /// <summary>
    ///  Checks no silent boot-ROM/sequencer substitute is created when firmware is absent.
    /// </summary>
    [TestMethod]
    public void MountRequiresExternalFirmwareAndValidDrive()
    {
        DiskIIController controller = new();
        Action mount = () => controller.Mount(drive: 1, WozDisk.CreateBlank());
        mount.Should().Throw<InvalidOperationException>();
        Action invalid = () => controller.State(drive: 3);
        invalid.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Checks stopped fixed points against uncached half clocks through control, input and clock changes.
    /// </summary>
    /// <param name="operation">The toy sequencer command.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(8)]
    [DataRow(9)]
    [DataRow(10)]
    [DataRow(11)]
    [DataRow(13)]
    [DataRow(14)]
    [DataRow(15)]
    public void IdleTicksMatchUncachedHalfClocksAcrossControlChanges(int operation)
    {
        DiskIIController controller = Controller((byte)operation);
        DiskIIController reference = Controller((byte)operation);
        WozDisk disk = WozDisk.CreateBlank();
        WozDisk referenceDisk = WozDisk.CreateBlank();
        controller.Mount(drive: 1, disk);
        reference.Mount(drive: 1, referenceDisk);
        Random random = new(Seed: 6502);
        for (int cycle = 0; cycle < 2048; cycle++)
        {
            if (cycle % 127 == 0)
            {
                byte offset = (byte)((cycle / 127) & 15);
                byte value = (byte)random.Next(256);
                controller.Write(offset, value);
                reference.Write(offset, value);
            }

            if (cycle == 700) { disk.IsWriteProtected = referenceDisk.IsWriteProtected = true; }
            if (cycle == 1000)
            {
                controller.Reset();
                reference.Reset();
            }

            if (cycle % 31 == 0)
            {
                controller.HalfTick();
                reference.HalfTick();
            }

            controller.Tick();
            reference.HalfTick();
            reference.HalfTick();
            controller.DataLatch.Should().Be(reference.DataLatch);
            controller.State(drive: 1).Should().Be(reference.State(drive: 1));
            controller.State(drive: 2).Should().Be(reference.State(drive: 2));
        }

        disk.Export().Should().Equal(referenceDisk.Export());
    }

    /// <summary>
    ///  Checks a stopped controller keeps sampling externally changed write protection after its latch settles.
    /// </summary>
    [TestMethod]
    public void IdleSequencerObservesUnlatchedWriteProtection()
    {
        DiskIIController controller = Controller(operation: 10);
        WozDisk disk = WozDisk.CreateBlank();
        controller.Mount(drive: 1, disk);
        for (int clock = 0; clock < 16; clock++) { controller.Tick(); }
        controller.DataLatch.Should().Be(0);
        disk.IsWriteProtected = true;
        controller.Tick();
        controller.DataLatch.Should().Be(0xC0);
        disk.IsWriteProtected = false;
        for (int clock = 0; clock < 16; clock++) { controller.Tick(); }
        controller.DataLatch.Should().Be(0);
        controller.Read(offset: 3, floatingBus: 0);
        controller.Tick();
        controller.DataLatch.Should().Be(0xC0);
    }

    /// <summary>
    ///  Checks fractional rotation, non-byte-aligned wrapping and multiple bit cells in a single half clock.
    /// </summary>
    /// <param name="timing">The media's bit-cell duration in 125 ns units.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(16)]
    [DataRow(32)]
    [DataRow(64)]
    [DataRow(255)]
    public void DriveClockAccountsForEveryFractionalBitCell(int timing)
    {
        byte[] image = WozDisk.CreateBlank().Export();
        image[59] = (byte)timing;
        image.AsSpan(8, 4).Clear();
        WozDisk disk = WozDisk.Load(image, writable: true);
        disk.SetTrack(quarterTrack: 0, new byte[17], bitCount: 131);
        DiskIIDrive drive = new();
        drive.SetMedia(disk);
        ulong fraction = 0;
        int position = 0;
        for (int cycle = 0; cycle < 8192; cycle++)
        {
            bool writing = (cycle & 256) != 0;
            ulong interval = (ulong)timing * (writing ? 250_000_000UL : 125UL * 2_041_000);
            fraction += 1_000_000_000;
            while (fraction >= interval)
            {
                fraction -= interval;
                position = (position + 1) % 131;
            }

            drive.Tick(writing, transition: (cycle & 4) != 0);
            drive.BitPosition.Should().Be(position);
        }
    }

    private static DiskIIController Controller(byte operation)
    {
        byte[] boot = new byte[256];
        Array.Fill(boot, (byte)0xEA);
        byte[] prom = new byte[256];
        for (int address = 0; address < prom.Length; address++)
        {
            prom[address] = (address & 12) == 12 ? (byte)11 : operation;
        }

        DiskIIController controller = new();
        controller.SetFirmware(new(boot, prom));
        return controller;
    }
}
