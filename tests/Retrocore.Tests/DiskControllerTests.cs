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
        long start = GC.GetAllocatedBytesForCurrentThread();
        for (int clock = 0; clock < 4082; clock++) { controller.Tick(); }
        (GC.GetAllocatedBytesForCurrentThread() - start).Should().Be(0);
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
