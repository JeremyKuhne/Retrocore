// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Debug;
using Retrocore.Machines.Altair;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Altair;

namespace Retrocore.Tests;

/// <summary>
///  The Altair's 88-DCDD floppy controller and FD-400 drives: the status, sector position and data ports at the cycles
///  the FDC+ firmware gives, stepping and head loading, reading and writing sectors; the disk images; the DBL and MBL
///  PROMs from their SDK sources; and CP/M 2.2, Disk BASIC and Altair DOS booting through DBL.
/// </summary>
/// <remarks>
///  <para>
///   The PROM dumps and disks are in <c>RETROCORE_ALTAIR_DISK</c> or the external test data's <c>altair-disk</c> folder:
///   <c>dbl.bin</c> and <c>mbl.bin</c> (from deramp.com's DBL.HEX and MBL.HEX), <c>cpm22b-56k.dsk</c> (Mike Douglas's
///   CP/M 2.2b), <c>burcon-cpm-56k.dsk</c>, <c>disk-basic-5.0.dsk</c> and <c>altair-dos.dsk</c>. The tests that need
///   them are inconclusive without them; the timing tests need nothing.
///  </para>
/// </remarks>
[TestClass]
public sealed class AltairDiskTests
{
    private const string DblHash = "9BC8CF7E8C3A26818C8C2DD56B0AC4A0B47DA54862AD518804F030BF4B6D7BD1";
    private const string MblHash = "041E7316EBD945F4F31534E2D332BC5338FA6CD20E44484EDC7FB506FB218B3B";

    private static string Inputs => Path.Join(AppContext.BaseDirectory, "Inputs", "Altair");

    private static string External => Environment.GetEnvironmentVariable("RETROCORE_ALTAIR_DISK")
        ?? Path.Join(ExternalTestData.Root, "altair-disk");

    /// <summary>
    ///  DBL's and MBL's sources assemble to the PROMs' bytes.
    /// </summary>
    [TestMethod]
    public void PromSourcesMatchThePromDigests()
    {
        Hash(AltairSdkModules.AssembleDbl(Path.Join(Inputs, AltairSdkModules.DblSource))).Should().Be(DblHash);
        Hash(AltairSdkModules.AssembleMbl(Path.Join(Inputs, AltairSdkModules.MblSource))).Should().Be(MblHash);
    }

    /// <summary>
    ///  With the dumps present, each source is byte for byte its PROM.
    /// </summary>
    /// <param name="source">The source's file name.</param>
    /// <param name="dump">The dump's file name.</param>
    [TestMethod]
    [DataRow(AltairSdkModules.DblSource, "dbl.bin")]
    [DataRow(AltairSdkModules.MblSource, "mbl.bin")]
    public void PromSourcesMatchTheDumps(string source, string dump)
    {
        byte[] prom = Fixture(dump);
        AssemblyResult result = source == AltairSdkModules.DblSource
            ? AltairSdkModules.AssembleDbl(Path.Join(Inputs, source))
            : AltairSdkModules.AssembleMbl(Path.Join(Inputs, source));

        ReadOnlySpan<byte> built = result.Sections[0].Bytes.Span;
        built.CommonPrefixLength(prom).Should().Be(prom.Length, "the source should assemble to the PROM");
        built.Length.Should().Be(prom.Length);
    }

    /// <summary>
    ///  A launch fits the PROMs its proms option lists, building only those, DBL by default with the 88-DCDD and none
    ///  without, and refuses anything else.
    /// </summary>
    [TestMethod]
    public void LaunchesFitThePromsTheyList()
    {
        string directory = JsonSerializer.Serialize(Inputs);

        AltairRoms mbl = Roms($$"""{ "proms": ["mbl"], "sdkRoms": {{directory}} }""");
        mbl.Dbl.Should().BeNull();
        mbl.Mbl.Should().HaveCount(AltairRoms.PromSize);
        AltairRoms fitted = Roms($$"""{ "diskController": true, "sdkRoms": {{directory}} }""");
        fitted.Dbl.Should().HaveCount(AltairRoms.PromSize);
        fitted.Mbl.Should().BeNull();
        AltairRoms none = Roms("{}");
        none.Dbl.Should().BeNull();
        none.Mbl.Should().BeNull();

        Action text = () => Roms("""{ "proms": "dbl" }""");
        text.Should().Throw<ArgumentException>("proms is a list");
        Action other = () => Roms("""{ "proms": ["hdbl"] }""");
        other.Should().Throw<ArgumentException>();
        Action number = () => Roms("""{ "proms": [1] }""");
        number.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  With no drive selected, or a drive with no disk, the status and sector position read $FF; selecting a drive
    ///  with a disk shows it enabled, on track 0, with its head unloaded and free to step, and deselecting it disables
    ///  the controller's interrupts.
    /// </summary>
    [TestMethod]
    public void SelectingADriveEnablesTheController()
    {
        AltairMachine machine = Machine();
        machine.Bus.In(Status).Should().Be(0xFF);
        machine.Bus.In(Sector).Should().Be(0xFF);
        machine.Bus.Out(Status, 1);
        machine.Bus.In(Status).Should().Be(0xFF, "drive 1 is empty, so it is not ready");
        machine.Bus.In(Sector).Should().Be(0xFF);
        machine.Bus.Out(Status, 0);
        machine.Bus.In(Status).Should().Be(0xA5, "NRDA, INTE and head status off; track 0 and move-head on; bits 3 and 4 zero");
        machine.Bus.In(Sector).Should().Be(0xFF, "the head is not loaded");
        machine.Bus.Out(Control, 0x10);
        machine.Bus.Disk?.InterruptEnabled.Should().BeTrue();
        machine.Bus.Out(Status, 0x80);
        machine.Bus.In(Status).Should().Be(0xFF, "bit 7 deselects");
        machine.Bus.Disk?.InterruptEnabled.Should().BeFalse("deselecting disables the controller's interrupts");
    }

    /// <summary>
    ///  The status shows the 8080's INTE, as the controller reads it from the bus.
    /// </summary>
    [TestMethod]
    public void StatusShowsTheProcessorsInterruptEnable()
    {
        AltairMachine machine = Machine();
        machine.Bus.Out(Status, 0);
        I8080Registers registers = machine.Processor.Registers;
        registers.InterruptEnable = true;
        machine.Processor.Registers = registers;
        (machine.Bus.In(Status) & 0x20).Should().Be(0);
    }

    /// <summary>
    ///  A loaded head settles after 50 ms, and the sector position then shows from the next sector's start: Sector
    ///  True for its first 32 µs, then the sector number alone.
    /// </summary>
    [TestMethod]
    public void HeadLoadsAndTheSectorPositionFollowsTheDisk()
    {
        AltairMachine machine = Machine();
        machine.Bus.Out(Status, 0);
        ulong loaded = machine.Processor.CycleCount;
        machine.Bus.Out(Control, 0x04);
        RunTo(machine, loaded + AltairDiskTiming.HeadLoadCycles - 1);
        (machine.Bus.In(Status) & 0x04).Should().Be(0x04, "the head is still settling");
        RunTo(machine, loaded + AltairDiskTiming.HeadLoadCycles);
        (machine.Bus.In(Status) & 0x04).Should().Be(0, "the head has settled");

        ulong next = NextSector(machine.Processor.CycleCount);
        machine.Bus.In(Sector).Should().Be(0xFF, "the position shows only from a sector that began with the head settled");
        RunTo(machine, next);
        int sector = (int)(next / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        machine.Bus.In(Sector).Should().Be((byte)(0xC0 | (sector << 1)), "Sector True is low");
        RunTo(machine, next + AltairDiskTiming.SectorTrueCycles);
        machine.Bus.In(Sector).Should().Be((byte)(0xC1 | (sector << 1)));
    }

    /// <summary>
    ///  A step holds off head movement for 10.5 ms, when track 0 also follows it, allows another step for 1 ms, then
    ///  holds off movement again, until 43.5 ms after the step.
    /// </summary>
    [TestMethod]
    public void SteppingFollowsTheDrivesTiming()
    {
        AltairMachine machine = Machine();
        AltairDiskDrive drive = Drives(machine)[0];
        machine.Bus.Out(Status, 0);
        ulong stepped = machine.Processor.CycleCount;
        machine.Bus.Out(Control, 0x01);
        drive.Track.Should().Be(1);
        int status = machine.Bus.In(Status);
        (status & 0x02).Should().Be(0x02, "movement is held off");
        (status & 0x40).Should().Be(0, "track 0 shows until the first period ends");
        RunTo(machine, stepped + AltairDiskTiming.StepCycles);
        status = machine.Bus.In(Status);
        (status & 0x02).Should().Be(0, "another step is allowed");
        (status & 0x40).Should().Be(0x40, "the head has left track 0");
        RunTo(machine, stepped + AltairDiskTiming.StepCycles + AltairDiskTiming.StepWindowCycles);
        (machine.Bus.In(Status) & 0x02).Should().Be(0x02, "the head is settling");
        RunTo(machine, stepped + AltairDiskTiming.StepCycles + AltairDiskTiming.StepWindowCycles + AltairDiskTiming.SettleStepCycles - 1);
        (machine.Bus.In(Status) & 0x02).Should().Be(0x02, "until 43.5 ms after the step");
        RunTo(machine, stepped + AltairDiskTiming.StepCycles + AltairDiskTiming.StepWindowCycles + AltairDiskTiming.SettleStepCycles);
        (machine.Bus.In(Status) & 0x02).Should().Be(0);

        machine.Bus.Out(Control, 0x02);
        machine.Bus.Out(Control, 0x02);
        drive.Track.Should().Be(0, "stepping out stops at track 0");
    }

    /// <summary>
    ///  A sector's bytes come one a byte time from 452 µs into it, each asserting NRDA, which reading the data port
    ///  clears, and each holding the port until the next replaces it, as MITS's two-bytes-a-pass loop, which reads
    ///  the second without waiting for NRDA, relies on; a read a byte time late misses one. After the last, the port
    ///  keeps it.
    /// </summary>
    [TestMethod]
    public void BytesComeOneAByteTime()
    {
        AltairMachine machine = LoadedOnTrack0();
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        byte[] expected = SectorBytes(0, sector);

        RunTo(machine, start + AltairDiskTiming.FirstByteCycles - 1);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "no byte has come yet");
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles);
        (machine.Bus.In(Status) & 0x80).Should().Be(0, "NRDA: the first byte has come");
        machine.Bus.In(Data).Should().Be(expected[0]);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "reading it clears NRDA");

        // The second byte, read 66 cycles after the first's NRDA, as DBL reads it.
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles + 66);
        machine.Bus.In(Data).Should().Be(expected[1]);

        // The fourth byte holds the port from its arrival until the fifth comes.
        ulong fourth = start + AltairDiskTiming.FirstByteCycles + (3 * AltairDiskTiming.ByteCycles);
        RunTo(machine, fourth + AltairDiskTiming.ByteCycles - 1);
        machine.Bus.In(Data).Should().Be(expected[3], "a read late in its byte time still gets it");
        RunTo(machine, fourth + AltairDiskTiming.ByteCycles);
        machine.Bus.In(Data).Should().Be(expected[4], "the fifth has replaced it");

        // The last byte, then nothing more until the next sector.
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles + (136 * AltairDiskTiming.ByteCycles));
        machine.Bus.In(Data).Should().Be(expected[136]);
        RunTo(machine, start + AltairDiskTiming.EndOfSectorCycles);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "the sector has ended");
        machine.Bus.In(Data).Should().Be(expected[136], "the port keeps the last byte");
    }

    /// <summary>
    ///  A sector whose first byte lacks bit 7, as a blank one's does, reads from its first one bit, as the controller
    ///  assembles bytes from there.
    /// </summary>
    [TestMethod]
    public void ASectorReadsFromItsFirstOneBit()
    {
        AltairDisk disk = Disk();
        byte[] shifted = new byte[AltairDisk.SectorBytes];
        shifted[0] = 0x01;
        shifted[1] = 0x23;
        for (int sector = 0; sector < AltairDisk.SectorsPerTrack; sector++) { disk.WriteSector(0, sector, shifted); }

        AltairMachine machine = LoadedOnTrack0(disk);
        ulong start = NextSector(machine.Processor.CycleCount);
        ulong first = start + AltairDiskTiming.FirstByteCycles + (7 * AltairDiskTiming.BitCycles);
        RunTo(machine, first - 1);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "the bytes come seven bit times late");
        RunTo(machine, first);
        (machine.Bus.In(Status) & 0x80).Should().Be(0);
        machine.Bus.In(Data).Should().Be(0x91, "$01 $23 from bit 7 of the first byte is 1001 0001 ...");
        RunTo(machine, first + AltairDiskTiming.ByteCycles);
        machine.Bus.In(Data).Should().Be(0x80);
    }

    /// <summary>
    ///  A head command does not give back a byte already read: NRDA comes again only with the next byte.
    /// </summary>
    [TestMethod]
    public void AHeadCommandKeepsAByteRead()
    {
        AltairMachine machine = LoadedOnTrack0();
        ulong start = NextSector(machine.Processor.CycleCount);
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles);
        machine.Bus.In(Data);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "reading the port cleared NRDA");
        machine.Bus.Out(Control, 0x04);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "the head load gives nothing back");
        machine.Bus.Out(Control, 0x01);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "nor does a step");
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles + AltairDiskTiming.ByteCycles);
        (machine.Bus.In(Status) & 0x80).Should().Be(0, "the next byte has come");
    }

    /// <summary>
    ///  The data register holds the last byte to arrive whether or not anything reads it: before a sector's first byte
    ///  it still has the last of the sector before, and a peek at the port changes nothing.
    /// </summary>
    [TestMethod]
    public void TheDataRegisterFollowsTheDiskAlone()
    {
        AltairMachine machine = LoadedOnTrack0();
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles);
        machine.Bus.In(Data).Should().Be(SectorBytes(0, sector)[0]);
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles + (60 * AltairDiskTiming.ByteCycles));
        machine.Bus.PeekPort((byte)Data).Should().Be(SectorBytes(0, sector)[60], "a peek sees the byte arriving");
        RunTo(machine, start + AltairDiskTiming.SectorCycles + 100);
        machine.Bus.PeekPort((byte)Data).Should().Be(SectorBytes(0, sector)[136], "the last of the sector before");
        machine.Bus.In(Data).Should().Be(SectorBytes(0, sector)[136], "the peeks changed nothing");

        machine.Bus.Out(Control, 0x08);
        RunTo(machine, start + (2 * AltairDiskTiming.SectorCycles) + AltairDiskTiming.FirstByteCycles);
        machine.Bus.In(Data).Should().Be(SectorBytes(0, sector)[136], "an unloaded head keeps the byte it had");
    }

    /// <summary>
    ///  A disk put in mid-sector gives its own bytes as they are assembled; until then, and while the head is
    ///  loaded or stepped between them, the port keeps the byte it had, from the last disk.
    /// </summary>
    [TestMethod]
    public void ANewDiskGivesItsOwnBytes()
    {
        AltairMachine machine = LoadedOnTrack0();
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        int before = (sector + AltairDisk.SectorsPerTrack - 1) % AltairDisk.SectorsPerTrack;
        byte held = SectorBytes(0, before)[136];
        RunTo(machine, start + 100);
        machine.Bus.PeekPort((byte)Data).Should().Be(held);

        AltairDisk other = Disk();
        byte[] marked = new byte[AltairDisk.SectorBytes];
        Array.Fill(marked, (byte)0x99);
        other.WriteSector(0, sector, marked);
        other.WriteSector(1, before, marked);
        byte[] earlier = new byte[AltairDisk.SectorBytes];
        Array.Fill(earlier, (byte)0x88);
        other.WriteSector(0, before, earlier);
        Drives(machine)[0].Insert(other, "other.dsk", AltairDiskCodec.Name);
        machine.Bus.Out(Status, 0);
        machine.Bus.Out(Control, 0x04);
        machine.Bus.PeekPort((byte)Data).Should().Be(held, "nothing has been assembled from the new disk");
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80);
        machine.Bus.Out(Control, 0x01);
        machine.Bus.PeekPort((byte)Data).Should().Be(held, "nor from the track it stepped to");
        machine.Bus.Out(Control, 0x02);
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles);
        (machine.Bus.In(Status) & 0x80).Should().Be(0, "a byte has come");
        machine.Bus.In(Data).Should().Be(0x99, "from the new disk");
    }

    /// <summary>
    ///  A head loaded mid-sector reads from the next byte to be assembled: NRDA waits for it.
    /// </summary>
    [TestMethod]
    public void AHeadLoadedMidSectorWaitsForTheNextByte()
    {
        AltairMachine machine = Machine();
        machine.Bus.Out(Status, 0);
        ulong start = NextSector(machine.Processor.CycleCount + AltairDiskTiming.HeadLoadCycles);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        ulong fifth = start + AltairDiskTiming.FirstByteCycles + (5 * AltairDiskTiming.ByteCycles);
        RunTo(machine, fifth + 10);
        machine.Bus.Out(Control, 0x04);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "nothing has been assembled since the load");
        RunTo(machine, fifth + AltairDiskTiming.ByteCycles);
        (machine.Bus.In(Status) & 0x80).Should().Be(0);
        machine.Bus.In(Data).Should().Be(SectorBytes(0, sector)[6]);
    }

    /// <summary>
    ///  A step mid-sector keeps a byte waiting to be read, with NRDA, and the new track's bytes come from the next;
    ///  a step out at track 0, which cannot move the head, leaves the waiting byte and what the head reads alone.
    /// </summary>
    [TestMethod]
    public void AStepKeepsAWaitingByte()
    {
        AltairMachine machine = LoadedOnTrack0();
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        ulong fifth = start + AltairDiskTiming.FirstByteCycles + (5 * AltairDiskTiming.ByteCycles);
        RunTo(machine, fifth + 10);
        machine.Bus.Out(Control, 0x02);
        (machine.Bus.In(Status) & 0x80).Should().Be(0, "a step out at track 0 leaves byte 5 waiting");
        machine.Bus.Out(Control, 0x01);
        (machine.Bus.In(Status) & 0x80).Should().Be(0, "the step in leaves byte 5 waiting");
        machine.Bus.In(Data).Should().Be(SectorBytes(0, sector)[5]);
        (machine.Bus.In(Status) & 0x80).Should().Be(0x80);
        RunTo(machine, fifth + AltairDiskTiming.ByteCycles);
        machine.Bus.In(Data).Should().Be(SectorBytes(1, sector)[6], "the next byte is track 1's");
    }

    /// <summary>
    ///  A blank sector has no one bit to assemble bytes from, so it never gives one, and the register keeps the
    ///  byte it had from the track before.
    /// </summary>
    [TestMethod]
    public void ABlankSectorGivesNoBytes()
    {
        AltairDisk disk = Disk();
        byte[] blank = new byte[AltairDisk.SectorBytes];
        for (int sector = 0; sector < AltairDisk.SectorsPerTrack; sector++) { disk.WriteSector(1, sector, blank); }

        AltairMachine machine = LoadedOnTrack0(disk);
        ulong start = NextSector(machine.Processor.CycleCount);
        int first = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, start + AltairDiskTiming.FirstByteCycles + (10 * AltairDiskTiming.ByteCycles));
        byte held = machine.Bus.In(Data);
        held.Should().Be(SectorBytes(0, first)[10]);
        machine.Bus.Out(Control, 0x01);
        ulong next = start + AltairDiskTiming.SectorCycles;
        for (ulong offset = 0; offset < 2 * AltairDiskTiming.SectorCycles; offset += AltairDiskTiming.ByteCycles / 2)
        {
            RunTo(machine, next + offset);
            (machine.Bus.In(Status) & 0x80).Should().Be(0x80, "no byte at {0} cycles", offset);
        }

        machine.Bus.In(Data).Should().Be(held, "the register keeps the byte it had");
    }

    /// <summary>
    ///  A write enable in a sector's first 212 µs writes it: ENWD asks for each byte a byte time apart from 388 µs, and
    ///  the 137 bytes taken become the sector, the disk changed, and head movement waits for the trim erase to end in
    ///  the next sector. One given later in the sector is forgotten, and one after the sector's end writes the next.
    /// </summary>
    [TestMethod]
    public void WritingTakesAByteEachHandshake()
    {
        AltairMachine machine = LoadedOnTrack0();
        AltairDisk disk = Drives(machine)[0].Disk ?? throw new InvalidOperationException("The disk is missing.");
        long version = disk.Version;
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, start + 100);
        machine.Bus.Out(Control, 0x80);
        (machine.Bus.In(Status) & 0x01).Should().Be(0x01, "ENWD waits for the write clear time");
        (machine.Bus.In(Status) & 0x02).Should().Be(0x02, "no step while writing");

        byte[] written = new byte[AltairDisk.SectorBytes];
        for (int index = 0; index < written.Length; index++) { written[index] = (byte)(0x80 ^ (index * 3)); }
        for (int index = 0; index < written.Length; index++)
        {
            ulong handshake = start + AltairDiskTiming.WriteClearCycles + ((ulong)index * AltairDiskTiming.ByteCycles);
            RunTo(machine, handshake);
            (machine.Bus.In(Status) & 0x01).Should().Be(0, "ENWD asks for byte {0}", index);
            machine.Bus.Out(Data, written[index]);
            (machine.Bus.In(Status) & 0x01).Should().Be(0x01, "writing the port clears ENWD");
        }

        RunTo(machine, start + AltairDiskTiming.EndOfSectorCycles + AltairDiskTiming.ByteCycles);
        byte[] read = new byte[AltairDisk.SectorBytes];
        disk.ReadSector(0, sector, read);
        read.Should().Equal(written);
        disk.IsDirty.Should().BeTrue();
        disk.Version.Should().BeGreaterThan(version);
        (machine.Bus.In(Status) & 0x02).Should().Be(0x02, "the trim erase holds off a step");
        ulong trimmed = start + AltairDiskTiming.SectorCycles + AltairDiskTiming.TrimEraseCycles;
        RunTo(machine, trimmed - 1);
        (machine.Bus.In(Status) & 0x02).Should().Be(0x02, "until 452 µs into the next sector");
        RunTo(machine, trimmed);
        (machine.Bus.In(Status) & 0x02).Should().Be(0);

        // Later than 212 µs into a sector, a write enable is forgotten when the sector ends.
        ulong late = NextSector(machine.Processor.CycleCount) + 600;
        int lateSector = (int)(late / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, late);
        machine.Bus.Out(Control, 0x80);
        machine.Bus.Out(Data, 0x81);
        RunTo(machine, late + (2 * AltairDiskTiming.SectorCycles));
        for (int next = 0; next < 3; next++)
        {
            int unwritten = (lateSector + next) % AltairDisk.SectorsPerTrack;
            disk.ReadSector(0, unwritten, read);
            read.Should().Equal(SectorBytes(0, unwritten), "sector {0} is untouched", unwritten);
        }

        // After the sector's end, a write enable writes the next sector.
        ulong after = NextSector(machine.Processor.CycleCount) + AltairDiskTiming.EndOfSectorCycles + 50;
        int afterSector = (int)((after / AltairDiskTiming.SectorCycles) + 1) % AltairDisk.SectorsPerTrack;
        RunTo(machine, after);
        machine.Bus.Out(Control, 0x80);
        machine.Bus.Out(Data, 0x81);
        RunTo(machine, after + AltairDiskTiming.SectorCycles + AltairDiskTiming.ByteCycles);
        disk.ReadSector(0, afterSector, read);
        read.Should().AllBeEquivalentTo((byte)0x81, "the next sector took the port's byte at every handshake");
    }

    /// <summary>
    ///  Unloading the head during a write shows in the status at once, and the write still ends with its sector.
    /// </summary>
    [TestMethod]
    public void UnloadingDuringAWriteShowsAtOnce()
    {
        AltairMachine machine = LoadedOnTrack0();
        AltairDisk disk = Drives(machine)[0].Disk ?? throw new InvalidOperationException("The disk is missing.");
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, start + 100);
        machine.Bus.Out(Control, 0x80);
        machine.Bus.Out(Data, 0x42);
        RunTo(machine, start + 1_000);
        machine.Bus.Out(Control, 0x08);
        (machine.Bus.In(Status) & 0x04).Should().Be(0x04, "the head is not loaded");
        machine.Bus.In(Sector).Should().Be(0xFF);
        Drives(machine)[0].HeadLoaded.Should().BeFalse();
        RunTo(machine, start + AltairDiskTiming.EndOfSectorCycles + AltairDiskTiming.ByteCycles);
        byte[] read = new byte[AltairDisk.SectorBytes];
        disk.ReadSector(0, sector, read);
        read.Should().AllBeEquivalentTo((byte)0x42, "the write went on to the sector's end");
    }

    /// <summary>
    ///  Writes to a write-protected disk are lost.
    /// </summary>
    [TestMethod]
    public void AProtectedDiskKeepsItsSectors()
    {
        AltairMachine machine = LoadedOnTrack0();
        AltairDiskDrive drive = Drives(machine)[0];
        drive.SetWriteProtected(writeProtected: true);
        ulong start = NextSector(machine.Processor.CycleCount);
        int sector = (int)(start / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);
        RunTo(machine, start + 100);
        machine.Bus.Out(Control, 0x80);
        machine.Bus.Out(Data, 0x55);
        RunTo(machine, start + AltairDiskTiming.SectorCycles);
        byte[] read = new byte[AltairDisk.SectorBytes];
        drive.Disk?.ReadSector(0, sector, read);
        read.Should().Equal(SectorBytes(0, sector));
        drive.Disk?.IsDirty.Should().BeFalse();
    }

    /// <summary>
    ///  An image is 337,568 bytes, or 337,664 with the trailer many archive images have, which saves back as it was.
    /// </summary>
    [TestMethod]
    public void ImagesKeepTheirTrailer()
    {
        byte[] image = new byte[AltairDisk.ImageBytes + AltairDisk.TrailerBytes];
        image[^1] = 0xAA;
        image[0] = 0x80;
        (AltairDisk disk, AltairDiskCodec codec) = AltairDiskCodec.Load(image);
        disk.HasTrailer.Should().BeTrue();
        disk.IsDirty.Should().BeFalse();
        EncodedImage encoded = codec.Encode(disk.Snapshot());
        encoded.IsLossless.Should().BeTrue();
        encoded.Bytes.Should().Equal(image);
        Action wrong = () => AltairDisk.Load(new byte[76_720]);
        wrong.Should().Throw<InvalidDataException>("a Minidisk image is not an 8-inch disk");
        Action foreign = () => codec.Encode(new MediumSnapshot("woz2", 0, WriteProtected: false, Array.Empty<byte>()));
        foreign.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  A drive takes a new mount generation for each disk in and out, and a save takes the label and format it was
    ///  saved under.
    /// </summary>
    [TestMethod]
    public void DrivesHoldDisks()
    {
        AltairMachine machine = Machine();
        AltairDiskDrive drive = Drives(machine)[1];
        drive.Media.Should().BeNull();
        int empty = drive.MountGeneration;
        drive.Insert(Disk(), "/disks/a.dsk", AltairDiskCodec.Name);
        drive.MountGeneration.Should().NotBe(empty);
        drive.Media.Should().Be(new MediaState("/disks/a.dsk", "DSK", WriteProtected: false, Changed: false));
        drive.Info.SaveFormats.Should().Equal("dsk");
        int mounted = drive.MountGeneration;
        drive.Saved("/disks/b.dsk", "DSK", whole: true);
        drive.MountGeneration.Should().Be(mounted, "a save is not a new mount");
        drive.Media.Should().Be(new MediaState("/disks/b.dsk", "DSK", WriteProtected: false, Changed: false));
        drive.Eject().Should().NotBeNull();
        drive.MountGeneration.Should().NotBe(mounted);
        drive.Media.Should().BeNull();
    }

    /// <summary>
    ///  CP/M 2.2b, Burcon's CP/M 2.2, Disk BASIC 5.0 and Altair DOS boot through DBL from the SDK's source, from their
    ///  images.
    /// </summary>
    /// <param name="image">The disk image's file name.</param>
    /// <param name="banner">What the system shows once it has booted.</param>
    [TestMethod]
    [DataRow("cpm22b-56k.dsk", "56K CP/M 2.2b v2.3")]
    [DataRow("burcon-cpm-56k.dsk", "Copyright 1980 by Burcon Inc.")]
    [DataRow("disk-basic-5.0.dsk", "MEMORY SIZE?")]
    [DataRow("altair-dos.dsk", "MEMORY SIZE?")]
    public void BootsThroughDbl(string image, string banner)
    {
        AltairMachine machine = Booted(image);
        Screen(machine).Should().Contain(banner);
    }

    /// <summary>
    ///  CP/M 2.2b lists its disk, saves a file, which changes the disk, and STAT and ERA see the file.
    /// </summary>
    [TestMethod]
    public void CpmWritesAndReadsFiles()
    {
        AltairMachine machine = Booted("cpm22b-56k.dsk");
        Type(machine, "DIR");
        Screen(machine).Should().Contain("A: MBASIC   COM : PIP      COM : STAT     COM : DDT      COM");
        Type(machine, "SAVE 4 TEST.COM");
        Type(machine, "STAT TEST.COM");
        Screen(machine).Should().Contain("    8     2k    1 R/W A:TEST.COM");
        Drives(machine)[0].Disk?.IsDirty.Should().BeTrue();
        Type(machine, "ERA TEST.COM");
        Type(machine, "DIR TEST.COM");
        Screen(machine).Should().Contain("No file");
    }

    // The PROMs a launch with these arguments fits.
    private static AltairRoms Roms(string json)
    {
        JsonObject args = JsonNode.Parse(json) as JsonObject ?? throw new InvalidOperationException("Not an object.");
        return AltairDebugTarget.Launch(args).Machine.Roms;
    }

    private const ushort Status = AltairDiskController.Port;
    private const ushort Sector = AltairDiskController.Port + 1;
    private const ushort Control = AltairDiskController.Port + 1;
    private const ushort Data = AltairDiskController.Port + 2;

    private static AltairMachine Machine(AltairDisk? disk = null)
    {
        AltairMachine machine = new(new AltairConfiguration { DiskDrives = 2 });
        Drives(machine)[0].Insert(disk ?? Disk(), "test.dsk", AltairDiskCodec.Name);
        return machine;
    }

    private static IReadOnlyList<AltairDiskDrive> Drives(AltairMachine machine) =>
        (machine.Bus.Disk ?? throw new InvalidOperationException("The 88-DCDD is missing.")).Drives;

    // Drive 0 selected, on track 0, its head loaded and settled.
    private static AltairMachine LoadedOnTrack0(AltairDisk? disk = null)
    {
        AltairMachine machine = Machine(disk);
        machine.Bus.Out(Status, 0);
        machine.Bus.Out(Control, 0x04);
        RunTo(machine, machine.Processor.CycleCount + AltairDiskTiming.HeadLoadCycles);
        return machine;
    }

    // A disk whose every sector starts with its track and bit 7, then bytes that differ by track, sector and place.
    private static AltairDisk Disk()
    {
        AltairDisk disk = AltairDisk.Blank();
        for (int track = 0; track < AltairDisk.Tracks; track++)
        {
            for (int sector = 0; sector < AltairDisk.SectorsPerTrack; sector++)
            {
                disk.WriteSector(track, sector, SectorBytes(track, sector));
            }
        }

        disk.MarkSaved();
        return disk;
    }

    private static byte[] SectorBytes(int track, int sector)
    {
        byte[] bytes = new byte[AltairDisk.SectorBytes];
        bytes[0] = (byte)(0x80 | track);
        for (int index = 1; index < bytes.Length; index++)
        {
            bytes[index] = (byte)((track * 7) + (sector * 13) + index);
        }

        return bytes;
    }

    private static ulong NextSector(ulong cycle) =>
        ((cycle / AltairDiskTiming.SectorCycles) + 1) * AltairDiskTiming.SectorCycles;

    private static void RunTo(AltairMachine machine, ulong cycle)
    {
        ulong now = machine.Processor.CycleCount;
        if (cycle > now) { machine.Run(cycle - now); }
    }

    // Boots an image in drive 0 through DBL from the SDK's source, with the terminal on the 88-2SIO.
    private static AltairMachine Booted(string image)
    {
        byte[] bytes = Fixture(image);
        AssemblyResult dbl = AltairSdkModules.AssembleDbl(Path.Join(Inputs, AltairSdkModules.DblSource));
        AltairRoms roms = new() { Dbl = dbl.Sections[0].Bytes.ToArray() };
        AltairMachine machine = new(new AltairConfiguration { DiskDrives = 4, UpperCase = true }, roms);
        Drives(machine)[0].Insert(AltairDisk.Load(bytes), image, AltairDiskCodec.Name);
        I8080Registers registers = machine.Processor.Registers;
        registers.PC = AltairBus.DblAddress;
        machine.Processor.Registers = registers;
        machine.Run(4 * AltairTiming.ClockHertz);
        return machine;
    }

    private static void Type(AltairMachine machine, string line)
    {
        foreach (char key in line) { machine.Terminal.Type((byte)key); }
        machine.Terminal.Type(13);
        machine.Run(3 * AltairTiming.ClockHertz);
    }

    private static string Screen(AltairMachine machine) =>
        string.Join("\n", Enumerable.Range(0, AltairTerminal.Rows).Select(row => machine.Terminal.Line(row).TrimEnd()));

    private static byte[] Fixture(string name)
    {
        string path = Path.Join(External, name);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"Set RETROCORE_ALTAIR_DISK to the Altair disk files ({name}).");
        }

        return File.ReadAllBytes(path);
    }

    private static string Hash(AssemblyResult result) => Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span));
}
