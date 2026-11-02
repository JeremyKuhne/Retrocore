// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies that disks built from the SDK's DOS sources boot.
/// </summary>
[TestClass]
public sealed class DosDiskTests
{
    private const ushort Marker = 0x07;
    private const byte MarkerValue = 0x5A;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Each DOS 3.3, written as INIT writes it (DOS where it runs) or as a System Master holds it (relocatable),
    ///  boots on a IIe built from the SDK, runs the greeting program, and that BRUNs a binary file.
    /// </summary>
    /// <param name="master">Whether to write the master's relocatable image.</param>
    /// <param name="year">Which DOS 3.3: 1983 or 1980.</param>
    [TestMethod]
    [DataRow(false, 1983)]
    [DataRow(true, 1983)]
    [DataRow(false, 1980)]
    [DataRow(true, 1980)]
    public void BuiltDiskBootsAndRunsHello(bool master, int year)
    {
        byte[] dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master, year)
            .Sections[0]
            .Bytes
            .ToArray();

        // lda #MarkerValue / sta Marker / rts
        byte[] program = [0xA9, MarkerValue, 0x85, (byte)Marker, 0x60];
        byte[] disk = DosDisk.Create(
            DosDisk.Dos33Tracks(dos),
            [Hello("PROGRAM"), DosFile.Binary("PROGRAM", address: 0x0300, program)]);

        Apple2Machine machine = Boot(disk);
        machine.Bus.Peek(Marker).Should().Be(MarkerValue, "HELLO ran and BRUN PROGRAM ran the binary");
    }

    /// <summary>
    ///  DOS 3.2, written as INIT writes it or as its System Master holds it, boots from a 13-sector disk on the
    ///  SDK's 13-sector card, runs the greeting program, and that BRUNs a binary file.
    /// </summary>
    /// <param name="master">Whether to write the master's relocatable image.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void BuiltDos32DiskBootsAndRunsHello(bool master)
    {
        byte[] dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos32.asm", s_inputs), master)
            .Sections[0]
            .Bytes
            .ToArray();

        byte[] program = [0xA9, MarkerValue, 0x85, (byte)Marker, 0x60];
        byte[] disk = DosDisk.Create(
            DosDisk.Dos32Tracks(dos),
            [Hello("PROGRAM"), DosFile.Binary("PROGRAM", address: 0x0300, program)],
            sectorsPerTrack: 13);

        Apple2Machine machine = Boot(disk, thirteen: true);
        machine.Bus.Peek(Marker).Should().Be(MarkerValue, "HELLO ran and BRUN PROGRAM ran the binary");
    }

    /// <summary>
    ///  The tracks of a master build land where the System Master has them: the boot sector, BOOT 2 and RWTS in
    ///  track 0 sectors 0-9, and the relocator and DOS from track 0 sector 10 to track 2 sector 4.
    /// </summary>
    [TestMethod]
    public void MasterTracksMatchTheMaster()
    {
        string path = Path.Join(ExternalTestData.Root, "iie-disks", "DOS 3.3 System Master - 680-0210-A (1982).dsk");
        if (!File.Exists(path)) { Assert.Inconclusive($"The DOS 3.3 System Master ({path}) is missing."); }

        byte[] master = File.ReadAllBytes(path);
        byte[] dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master: true)
            .Sections[0]
            .Bytes
            .ToArray();

        // Track 2 sectors 5-15 are not DOS's: the master leaves them as INIT formatted them.
        const int Used = ((2 * 16) + 5) * DosDisk.SectorSize;
        DosDisk.Dos33Tracks(dos).AsSpan(0, Used).SequenceEqual(master.AsSpan(0, Used)).Should().BeTrue();
    }

    /// <summary>
    ///  A built disk's catalog holds each file with its type, length and track/sector list, as DOS reads it.
    /// </summary>
    [TestMethod]
    public void CatalogListsTheFiles()
    {
        byte[] data = new byte[300];
        byte[] disk = DosDisk.Create(new byte[3 * 16 * 256], [DosFile.Binary("DATA", address: 0x2000, data)]);

        Span<byte> vtoc = disk.AsSpan(17 * 16 * 256, 256);
        vtoc[1].Should().Be(17);
        vtoc[2].Should().Be(15);
        vtoc[0x35].Should().Be(16);

        Span<byte> catalog = disk.AsSpan(((17 * 16) + 15) * 256, 256);
        catalog[0x0B + 2].Should().Be((byte)DosFileType.Binary);
        catalog[0x0B + 3].Should().Be((byte)('D' | 0x80));
        catalog[0x0B + 33].Should().Be(3, "one track/sector list and two data sectors hold 304 bytes");

        int listTrack = catalog[0x0B];
        int listSector = catalog[0x0B + 1];
        Span<byte> list = disk.AsSpan(((listTrack * 16) + listSector) * 256, 256);
        int dataTrack = list[0x0C];
        int dataSector = list[0x0D];
        Span<byte> first = disk.AsSpan(((dataTrack * 16) + dataSector) * 256, 4);
        first.ToArray().Should().Equal(0x00, 0x20, 0x2C, 0x01);
    }

    // A greeting program that BRUNs the named binary.
    private static DosFile Hello(string program)
    {
        BasicParseResult parsed = BasicProgram.Parse($"10 PRINT CHR$(4);\"BRUN {program}\"\n", BasicDialect.AppleSoft);
        BasicProgram basic = parsed.Program ?? throw new AssertFailedException("The greeting program doesn't parse.");
        return DosFile.AppleSoft("HELLO", basic.ToImage(address: 0x0801));
    }

    // Boots an image on an Enhanced IIe built from the SDK, until the marker is set or 15 seconds pass.
    private static Apple2Machine Boot(byte[] disk, bool thirteen = false)
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(thirteen ? 13 : 16, s_inputs));
        machine.Drives[0].Insert(
            thirteen ? SectorDiskConverter.ConvertThirteenSector(disk) : SectorDiskConverter.Convert(disk, proDosOrder: false),
            "built",
            thirteen ? "D13" : "DSK");

        for (int second = 0; second < 15 && machine.Bus.Peek(Marker) != MarkerValue; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        return machine;
    }
}
