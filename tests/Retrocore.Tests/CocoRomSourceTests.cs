// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Coco;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native sources for the Color Computer's Color BASIC, versions 1.0 to 1.3, Extended Color
///  BASIC, versions 1.0 and 1.1, Disk Extended Color BASIC, versions 1.0 and 1.1, and the CoCo 3's ROM.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps in <c>RETROCORE_COCO_ROMS</c> or
///   <c>%USERPROFILE%\Retrocore\coco-roms\extract</c>, each also compares byte for byte, which names the first
///   difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class CocoRomSourceTests
{
    /// <summary>
    ///  Color BASIC builds byte-identically for each version.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="expectedHash">The SHA-256 of that version's 8K ROM.</param>
    [TestMethod]
    [DataRow(10, "384183ABB962AA298C38A4DE7F86B6712FEDDF6BA4C85B49E05E3C76318335DC")]
    [DataRow(11, "F772EE5EC3CE3BFC455098C0C9ACA2B5C42B6AA1F998BB5113CA2250BFBF2C27")]
    [DataRow(12, "40413D0F8BC1BB345FFE49404B3BF645A5417B02F32266536F6566DBF9CA70FB")]
    [DataRow(13, "5375B1CAEF9DF815B781D9CD6DF81ECDADDD2642B06A01ADAC521E40F1329751")]
    public void ColorBasicMatchesTheVersion(int version, string expectedHash)
    {
        AssemblyResult result = CocoSdkModules.AssembleColorBasic(Source("ColorBasic.asm"), version);
        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
        CocoSdkModules.VersionOf(result.Sections[0].Bytes.Span).Should().Be(version);
    }

    /// <summary>
    ///  With the dumps, each version compares byte for byte.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="dump">The dump, under MAME's name.</param>
    [TestMethod]
    [DataRow(10, "coco/bas10.rom")]
    [DataRow(11, "coco/bas11.rom")]
    [DataRow(12, "coco/bas12.rom")]
    [DataRow(13, "coco2b/bas13.rom")]
    public void ColorBasicMatchesTheDump(int version, string dump)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
            ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

        string path = Path.Join(directory, dump);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"The Color BASIC dump ({path}) is missing.");
        }

        byte[] expected = File.ReadAllBytes(path);
        ReadOnlySpan<byte> actual = CocoSdkModules.AssembleColorBasic(Source("ColorBasic.asm"), version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(actual.Length, $"the first difference is at ${CocoSdkModules.ColorBasicOrigin + first:X4}");
    }

    /// <summary>
    ///  Extended Color BASIC builds byte-identically for each version.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="expectedHash">The SHA-256 of that version's 8K ROM.</param>
    [TestMethod]
    [DataRow(10, "36CE538D261FA727152C41F66FE6B310268EFE19F3EF7365E0BBC6D84A5A957E")]
    [DataRow(11, "A18F270D3495D82B9F515DE049F46253A623A2D9B1BB226C9AD338508344C5EE")]
    public void ExtendedBasicMatchesTheVersion(int version, string expectedHash)
    {
        AssemblyResult result = CocoSdkModules.AssembleExtendedBasic(Source("ExtendedBasic.asm"), version);
        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
        CocoSdkModules.ExtendedVersionOf(result.Sections[0].Bytes.Span).Should().Be(version);
    }

    /// <summary>
    ///  With the dumps, each Extended BASIC version compares byte for byte.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="dump">The dump, under MAME's name.</param>
    [TestMethod]
    [DataRow(10, "coco/extbas10.rom")]
    [DataRow(11, "coco/extbas11.rom")]
    public void ExtendedBasicMatchesTheDump(int version, string dump)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
            ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

        string path = Path.Join(directory, dump);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"The Extended BASIC dump ({path}) is missing.");
        }

        byte[] expected = File.ReadAllBytes(path);
        ReadOnlySpan<byte> actual = CocoSdkModules.AssembleExtendedBasic(Source("ExtendedBasic.asm"), version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(actual.Length, $"the first difference is at ${CocoSdkModules.ExtendedBasicOrigin + first:X4}");
    }

    /// <summary>
    ///  A Color Computer runs on Color BASIC built from the source alone, with no dumps: it signs on and runs a line.
    /// </summary>
    [TestMethod]
    public void ColorBasicBootsFromTheSource()
    {
        AssemblyResult result = CocoSdkModules.AssembleColorBasic(Source("ColorBasic.asm"), 12);
        CocoMachine machine = new(
            new() { Model = CocoModel.Coco2, RamKilobytes = 16 },
            CocoRoms.ForCoco12(result.Sections[0].Bytes.Span, []));

        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Screen(machine).Should().Contain("COLOR BASIC 1.2").And.Contain("OK");
        CocoMachineTests.Type(machine, "PRINT 6*7\r");
        CocoMachineTests.Screen(machine).Should().Contain(" 42 ");
    }

    /// <summary>
    ///  A Color Computer runs on Color BASIC and Extended Color BASIC built from the sources, with no dumps, for the
    ///  pairings they shipped in: Extended BASIC signs on, and its functions, PRINT USING and graphics work.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Color BASIC 1.0 predates 64K boards: it never drives PIA 0's columns, so it reads a 64K board's RAM size
    ///   jumper as 4K chips, and the SAM then repeats RAM every 4K. It runs with 16K.
    ///  </para>
    /// </remarks>
    /// <param name="color">Color BASIC's version.</param>
    /// <param name="extended">Extended BASIC's version.</param>
    /// <param name="ramKilobytes">The RAM fitted.</param>
    [TestMethod]
    [DataRow(10, 10, 16)]
    [DataRow(11, 10, 64)]
    [DataRow(12, 11, 64)]
    [DataRow(13, 11, 64)]
    public void ExtendedBasicBootsFromTheSource(int color, int extended, int ramKilobytes)
    {
        AssemblyResult colorBasic = CocoSdkModules.AssembleColorBasic(Source("ColorBasic.asm"), color);
        AssemblyResult extendedBasic = CocoSdkModules.AssembleExtendedBasic(Source("ExtendedBasic.asm"), extended);
        CocoMachine machine = new(
            new() { Model = CocoModel.Coco2, RamKilobytes = ramKilobytes },
            CocoRoms.ForCoco12(colorBasic.Sections[0].Bytes.Span, extendedBasic.Sections[0].Bytes.Span));

        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Screen(machine).Should().Contain($"EXTENDED COLOR BASIC 1.{extended - 10}").And.Contain("OK");
        CocoMachineTests.Type(machine, "PRINT HEX$(&HBEEF);SQR(16);INSTR(\"ABCD\",\"C\")\r");
        CocoMachineTests.Screen(machine).Should().Contain("BEEF 4  3 ");
        CocoMachineTests.Type(machine, "PRINT USING \"##.##\";3.14159\r");
        CocoMachineTests.Screen(machine).Should().Contain(" 3.14");
        CocoMachineTests.Type(machine, "PMODE 4,1:PCLS:LINE(0,0)-(10,0),PSET:PRINT PPOINT(5,0);PPOINT(5,1)\r");
        CocoMachineTests.Screen(machine).Should().Contain(" 1  0 ");
    }

    /// <summary>
    ///  Disk Extended Color BASIC builds byte-identically for each version.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="expectedHash">The SHA-256 of that version's 8K ROM.</param>
    [TestMethod]
    [DataRow(10, "8C86C83720043525029797DD3DEFD0FD285651549A373117304CC470E8E61F91")]
    [DataRow(11, "1C40C5A74E72EDAEECC2511FEE1AAB347EAE2C3D5FC6778CB622E3DF14D63157")]
    public void DiskBasicMatchesTheVersion(int version, string expectedHash)
    {
        AssemblyResult result = CocoSdkModules.AssembleDiskBasic(Source("DiskBasic.asm"), version);
        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
        CocoSdkModules.DiskVersionOf(result.Sections[0].Bytes.Span).Should().Be(version);
    }

    /// <summary>
    ///  With the dumps, each Disk BASIC version compares byte for byte.
    /// </summary>
    /// <param name="version">The version.</param>
    /// <param name="dump">The dump, under MAME's name.</param>
    [TestMethod]
    [DataRow(10, "coco_fdc/disk10.rom")]
    [DataRow(11, "coco_fdc/disk11.rom")]
    public void DiskBasicMatchesTheDump(int version, string dump)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
            ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

        string path = Path.Join(directory, dump);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"The Disk BASIC dump ({path}) is missing.");
        }

        byte[] expected = File.ReadAllBytes(path);
        ReadOnlySpan<byte> actual = CocoSdkModules.AssembleDiskBasic(Source("DiskBasic.asm"), version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(actual.Length, $"the first difference is at ${CocoSdkModules.DiskBasicOrigin + first:X4}");
    }

    /// <summary>
    ///  A Color Computer with the disk controller runs on all three BASICs built from the sources, with no dumps:
    ///  Disk BASIC signs on, and saves, lists, loads and runs a program on a formatted disk.
    /// </summary>
    /// <param name="color">Color BASIC's version.</param>
    /// <param name="extended">Extended BASIC's version.</param>
    /// <param name="disk">Disk BASIC's version.</param>
    [TestMethod]
    [DataRow(11, 10, 10)]
    [DataRow(12, 11, 11)]
    public void DiskBasicBootsFromTheSource(int color, int extended, int disk)
    {
        AssemblyResult colorBasic = CocoSdkModules.AssembleColorBasic(Source("ColorBasic.asm"), color);
        AssemblyResult extendedBasic = CocoSdkModules.AssembleExtendedBasic(Source("ExtendedBasic.asm"), extended);
        AssemblyResult diskBasic = CocoSdkModules.AssembleDiskBasic(Source("DiskBasic.asm"), disk);
        CocoMachine machine = new(
            new() { Model = CocoModel.Coco2, RamKilobytes = 64 },
            CocoRoms.ForCoco12(colorBasic.Sections[0].Bytes.Span, extendedBasic.Sections[0].Bytes.Span),
            new CocoDiskController(diskBasic.Sections[0].Bytes.Span));

        machine.Bus.DiskController?.Drives[0].Insert(JvcFormat.Formatted(), "formatted", "dsk");
        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Screen(machine).Should().Contain($"DISK EXTENDED COLOR BASIC 1.{disk - 10}");

        CocoMachineTests.Type(machine, "10 print \"saved\";6*7\rsave \"hello\"\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        CocoMachineTests.Type(machine, "new\rdir\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        CocoMachineTests.Screen(machine).Should().Contain("HELLO").And.Contain("BAS");
        CocoMachineTests.Type(machine, "load \"hello\"\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        CocoMachineTests.Type(machine, "run\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        CocoMachineTests.Screen(machine).Should().Contain("SAVED 42");
        CocoMachineTests.Type(machine, "print free(0)\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        CocoMachineTests.Screen(machine).Should().Contain(" 67 ");
    }

    /// <summary>
    ///  The CoCo 3's 32 KB ROM builds byte-identically from Extended and Color BASIC with <c>COCO3</c> set and
    ///  <c>Coco3.asm</c>.
    /// </summary>
    [TestMethod]
    public void Coco3MatchesTheRom()
    {
        Coco3Assembly rom = CocoSdkModules.AssembleCoco3(Path.Join(AppContext.BaseDirectory, "Inputs", "Coco"));
        rom.ExtendedBasic.Diagnostics.Should().BeEmpty();
        rom.ColorBasic.Diagnostics.Should().BeEmpty();
        rom.Coco3.Diagnostics.Should().BeEmpty();
        rom.Image.Should().HaveCount(CocoRoms.Coco3Size);
        string hash = Convert.ToHexString(SHA256.HashData(rom.Image));
        hash.Should().Be("AD358430568250EB8330A37F85361D9CE67E5AE6D5A28C17B31802CD3953A5D2");
        CocoSdkModules.IsCoco3Rom(rom.Image).Should().BeTrue();
    }

    /// <summary>
    ///  With the dump, the CoCo 3's ROM compares byte for byte.
    /// </summary>
    [TestMethod]
    public void Coco3MatchesTheDump()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
            ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

        string path = Path.Join(directory, "coco3", "coco3.rom");
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"The CoCo 3 dump ({path}) is missing.");
        }

        byte[] expected = File.ReadAllBytes(path);
        byte[] actual = CocoSdkModules.AssembleCoco3(Path.Join(AppContext.BaseDirectory, "Inputs", "Coco")).Image;
        int first = actual.AsSpan().CommonPrefixLength(expected);
        first.Should().Be(actual.Length, $"the first difference is at ${CocoSdkModules.ExtendedBasicOrigin + first:X4}");
    }

    /// <summary>
    ///  A CoCo 3 runs on its ROM built from the sources, with no dumps: it signs on as Extended Color BASIC 2.0, and
    ///  Super Extended BASIC's text and graphics commands work.
    /// </summary>
    [TestMethod]
    public void Coco3BootsFromTheSource()
    {
        Coco3Assembly rom = CocoSdkModules.AssembleCoco3(Path.Join(AppContext.BaseDirectory, "Inputs", "Coco"));
        CocoMachine machine = new(new() { Model = CocoModel.Coco3, RamKilobytes = 128 }, CocoRoms.ForCoco3(rom.Image));

        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Screen(machine).Should().Contain("EXTENDED COLOR BASIC 2.0").And.Contain("OK");
        CocoMachineTests.Type(machine, "HSCREEN 2:HSET(10,10,3):A=HPOINT(10,10):HSCREEN 0:PRINT A;LPEEK(&H7A000)\r");
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Screen(machine).Should().Contain(" 3 ");
        CocoMachineTests.Type(machine, "WIDTH 40\rPRINT 6*7\r");
        machine.Bus.Gime?.CompatibleVideo.Should().BeFalse();
        CocoMachineTests.Screen(machine).Should().Contain("42");
    }

    private static string Source(string name) => Path.Join(AppContext.BaseDirectory, "Inputs", "Coco", name);
}
