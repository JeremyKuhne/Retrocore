// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Reading SOS volumes and their driver files, from Apple's Apple III disks when they are present.
/// </summary>
[TestClass]
public class SosVolumeTests
{
    /// <summary>
    ///  Gets the folder of Apple's Apple III disks.
    /// </summary>
    internal static string Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple3-disks");

    /// <summary>
    ///  Reads a volume from one of Apple's disks, or ends the test as inconclusive without it.
    /// </summary>
    /// <param name="disk">The disk's file name.</param>
    /// <returns>The volume.</returns>
    internal static SosVolume Volume(string disk)
    {
        string path = Path.Join(Disks, disk);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disk}."); }
        return SosVolume.Read(File.ReadAllBytes(path), proDosOrder: false);
    }

    /// <summary>
    ///  The Business BASIC disk's volume directory lists SOS's three files, and the kernel and driver file read whole.
    /// </summary>
    [TestMethod]
    public void BusinessBasicDiskListsAndReadsSosFiles()
    {
        SosVolume volume = Volume("Apple3BusBasic1.23.dsk");
        volume.Name.Should().Be("BASIC");
        volume.Files.Select(file => file.Name).Should().StartWith(["SOS.KERNEL", "SOS.DRIVER", "SOS.INTERP"]);

        byte[] kernel = volume.ReadFile("sos.kernel");
        kernel.Should().HaveCount(22016);
        kernel.AsSpan(0, 8).ToArray().Should().Equal("SOS KRNL"u8.ToArray());

        SosDriverFile drivers = SosDriverFile.Read(volume.ReadFile("SOS.DRIVER"));
        drivers.Drivers.Select(driver => driver.Name).Should().Equal(".CONSOLE", ".RS232", ".GRAFIX", ".SILENTYPE", ".AUDIO", ".PRINTER");
        drivers.Drivers[0].Code.Should().HaveCount(4007);
        drivers.Drivers[0].Relocations.Should().HaveCount(570);
        drivers.Drivers[0].Comment.Should().StartWith("Console Driver -- Copyright (C) 1983 by Apple Computer");
    }

    /// <summary>
    ///  The same kernel is on the Business BASIC and System Utilities disks.
    /// </summary>
    [TestMethod]
    public void BusinessBasicAndUtilitiesShareTheKernel()
    {
        byte[] basic = Volume("Apple3BusBasic1.23.dsk").ReadFile("SOS.KERNEL");
        byte[] utilities = Volume("Apple3SOS1.3SysUtils.dsk").ReadFile("SOS.KERNEL");
        utilities.Should().Equal(basic);
    }

    /// <summary>
    ///  A driver code file for the System Configuration Program reads as its driver: its code, from its DIB, and the
    ///  code's procedure-relative relocations. The Utilities Data disk's console driver predates comment records.
    /// </summary>
    [TestMethod]
    public void DriverCodeFileReadsItsDriver()
    {
        SosDriver console = SosDriverCodeFile.Read(Volume("Apple3SystemUtilData.dsk").ReadFile("CONSOLE.DRIVER"));
        console.Name.Should().Be(".CONSOLE");
        console.Comment.Should().BeEmpty();
        console.Relocations.Should().NotBeEmpty().And.BeInAscendingOrder();
        console.Relocations[^1].Should().BeLessThan(console.Code.Length - 1);
    }

    /// <summary>
    ///  A driver file without its signature is refused.
    /// </summary>
    [TestMethod]
    public void DriverFileNeedsItsSignature()
    {
        Action read = () => SosDriverFile.Read("SOS KRNL\0\0"u8);
        read.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A driver file's fields read in order: the file's comment, then each driver's comment, code and relocations.
    /// </summary>
    [TestMethod]
    public void DriverFileReadsItsFields()
    {
        byte[] code = new byte[20];
        code[4] = 4;
        ".ABC"u8.CopyTo(code.AsSpan(5));
        byte[] file = [.. "SOS DRVR"u8, 2, 0, (byte)'h', (byte)'i', 1, 0, (byte)'c', 20, 0, .. code, 2, 0, 3, 0, 0xFF, 0xFF];

        SosDriverFile drivers = SosDriverFile.Read(file);
        drivers.Comment.Should().Be("hi");
        drivers.Drivers.Should().ContainSingle();
        drivers.Drivers[0].Name.Should().Be(".ABC");
        drivers.Drivers[0].Comment.Should().Be("c");
        drivers.Drivers[0].Relocations.Should().Equal(3);
    }
}
