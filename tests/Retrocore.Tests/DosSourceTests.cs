// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's DOS 3.3 sources.
/// </summary>
[TestClass]
public sealed class DosSourceTests
{
    private const string Master1983 = "DOS 3.3 System Master - 680-0210-A (1982).dsk";
    private const string Master1980 = "DOS 3.3 System Master - 680-0051-01 (1980).dsk";
    private const int SectorSize = 256;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Each build is pinned by digest, so no disk is needed: the System Master's image at $1B00, and DOS where it
    ///  runs at $9D00.
    /// </summary>
    /// <param name="master">Whether to build the master's image.</param>
    /// <param name="year">Which DOS 3.3: 1983 or 1980.</param>
    /// <param name="expectedHash">The SHA-256 of the build.</param>
    [TestMethod]
    [DataRow(true, 1983, "9D0B6F409670316185466A1BB134ADBBB45A8D7797DDE88606106044E9CC51EC")]
    [DataRow(false, 1983, "9C61CCD8982755420CA62DFCC2EFBD593404EF72A2C71F24FF5CE4B97B269E3D")]
    [DataRow(true, 1980, "BBE9AED7ABDC5F30F1BA133C6DD03BE7B10C17F9345A63C51F8DA5E5A6AD874F")]
    [DataRow(false, 1980, "58439F5BFE9F2916F5D76EB2B86031E3AF79F954A0B123A85585DCC23B0A8103")]
    public void BuildMatchesItsDigest(bool master, int year, string expectedHash)
    {
        AssemblyResult result = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master, year);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Length.Should().Be(master ? SdkModules.DosMasterSize : SdkModules.DosSize);
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  DOS 3.2's builds are pinned by digest too: the System Master's image at $1B00, which is its tracks 0 to 2
    ///  as they load, and DOS where it runs at $9D00.
    /// </summary>
    /// <param name="master">Whether to build the master's image.</param>
    /// <param name="expectedHash">The SHA-256 of the build.</param>
    [TestMethod]
    [DataRow(true, "4FF1541783B21A69942C248EB9202B04CBD26BF8A81F51721F47A7C76AD40AFA")]
    [DataRow(false, "1C99E125C8A90ACA5EAD5DB0C733C1936E7102FC12D8FA179442D2CF792E07E2")]
    public void Dos32BuildMatchesItsDigest(bool master, string expectedHash)
    {
        AssemblyResult result = SdkModules.AssembleDos(SdkModules.DosPath("Dos32.asm", s_inputs), master);

        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the System Masters in <c>%USERPROFILE%\Retrocore\iie-disks</c>, each year's master build compares
    ///  byte for byte with its master's tracks 0 to 2, which names the first difference.
    /// </summary>
    /// <param name="year">Which DOS 3.3: 1983 or 1980.</param>
    /// <param name="file">Its master's image.</param>
    [TestMethod]
    [DataRow(1983, Master1983)]
    [DataRow(1980, Master1980)]
    public void MasterBuildMatchesTheDisk(int year, string file)
    {
        byte[] disk = ReadMaster(file);
        ReadOnlySpan<byte> built = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master: true, year)
            .Sections[0]
            .Bytes
            .Span;

        byte[] expected = MasterImage(disk);
        int first = built.CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first difference is at ${SdkModules.DosMasterOrigin + first:X4}");
    }

    /// <summary>
    ///  DOS debugs at its own lines where it runs: the running build's bytes at $9D00 map RWTS's address-field
    ///  reader to its source.
    /// </summary>
    [TestMethod]
    public void RunningDosDebugsAtItsLines()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        ReadOnlySpan<byte> dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master: false)
            .Sections[0]
            .Bytes
            .Span;

        for (int offset = 0; offset < dos.Length; offset++)
        {
            machine.Bus.Write((ushort)(SdkModules.DosOrigin + offset), dos[offset]);
        }

        AssertMapped(machine, "RDADR16", "ReadAddressSeek.asm");
    }

    /// <summary>
    ///  With the System Masters, a IIe built from the SDK boots each to AppleSoft's prompt, and the DOS its
    ///  relocator moved to $9D00 debugs at the SDK's source lines.
    /// </summary>
    /// <param name="file">The master's image.</param>
    [TestMethod]
    [DataRow(Master1983)]
    [DataRow(Master1980)]
    public void BootedMasterDebugsAtItsLines(string file)
    {
        byte[] disk = ReadMaster(file);
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(sectors: 16, s_inputs));
        machine.Drives[0].Insert(SectorDiskConverter.Convert(disk, proDosOrder: false), "DOS 3.3", "DSK");
        for (int second = 0; second < 15 && !HasPrompt(machine); second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        HasPrompt(machine).Should().BeTrue("DOS loaded and AppleSoft is waiting at its prompt");
        AssertMapped(machine, "RDADR16", "ReadAddressSeek.asm");
        AssertMapped(machine, "DOSENT", "FileManagerEntry.asm");
    }

    // Asserts that a DOS label resolves where DOS runs and maps to its line in the named source.
    private static void AssertMapped(Apple2Machine machine, string label, string file)
    {
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);
        long address = debug.Resolve(label);
        address.Should().BeInRange(SdkModules.DosOrigin, SdkModules.DosOrigin + SdkModules.DosSize - 1);

        DebugPosition? position = debug.Position(new Apple2TestMemory(machine.Bus), (ushort)address);
        SourceLine line = position?.Chain[0] ?? throw new AssertFailedException($"No source for {label}.");
        line.Path.Should().Be(Path.GetFullPath(SdkModules.DosPath(file, s_inputs)));
        File.ReadAllLines(line.Path)
            .Take(line.Line)
            .Last(text => text.Length > 1 && text[^1] == ':' && text[..^1].All(char.IsAsciiLetterOrDigit))
            .Should()
            .Be($"{label}:");
    }

    // A System Master's image, or inconclusive.
    private static byte[] ReadMaster(string file)
    {
        string path = Path.Join(ExternalTestData.Root, "iie-disks", file);
        if (!File.Exists(path)) { Assert.Inconclusive($"The DOS 3.3 System Master ({path}) is missing."); }

        return File.ReadAllBytes(path);
    }

    // A master's DOS as BOOT 1 and BOOT 2 load it: track 0 sectors 0-9 at $3600-$3FFF, and the sectors after
    // them, through track 2 sector 4, at $1B00-$35FF. The image's sectors are in DOS order.
    private static byte[] MasterImage(byte[] disk)
    {
        byte[] image = new byte[SdkModules.DosMasterSize];
        for (int sector = 0; sector < 10; sector++)
        {
            disk.AsSpan(sector * SectorSize, SectorSize).CopyTo(image.AsSpan(0x1B00 + (sector * SectorSize)));
        }

        for (int page = 0; page < 0x1B; page++)
        {
            int sector = 10 + page;
            disk.AsSpan(sector * SectorSize, SectorSize).CopyTo(image.AsSpan(page * SectorSize));
        }

        return image;
    }

    // A line of the text screen starts with AppleSoft's ] prompt.
    private static bool HasPrompt(Apple2Machine machine) =>
        Enumerable.Range(0, 24).Any(row => machine.Bus.Peek((ushort)(0x0400 + (row % 8 * 128) + (row / 8 * 40))) == 0xDD);
}
