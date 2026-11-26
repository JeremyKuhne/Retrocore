// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple3;
using Retrocore.Media;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies SOS disks built from the SDK's sources: the bootstrap loader and SOS.KERNEL assembled and written to a
///  volume, which reads back and, under emulation, boots.
/// </summary>
/// <remarks>
///  <para>
///   The emulation tests need the Apple III's boot ROM dump (<c>RETROCORE_APPLE3_ROMS</c>) and are inconclusive without
///   it; the rest need nothing outside the repository.
///  </para>
/// </remarks>
[TestClass]
public sealed class SosBootDiskTests
{
    // The SHA-256 of Apple's SOS BOOT 1.1 and of SOS 1.3's SOS.KERNEL, as SosSourceTests pins them.
    private const string BootHash = "A35DD52286214F981D9D819C01B3D4CCC30B54E4A2DF5B750F96F05828BF889C";
    private const string KernelHash = "6A8593274AF167B2BFD48CE556C907F5E30C0749EB1221BEE0970B3E19CB2F2D";

    /// <summary>
    ///  The SDK builds the bootstrap loader and SOS.KERNEL as Apple's disks hold them.
    /// </summary>
    [TestMethod]
    public void SdkBuildsTheBootLoaderAndKernel()
    {
        byte[] boot = Apple3SdkModules.BuildSosBoot(SdkDirectory);
        boot.Should().HaveCount(512);
        Convert.ToHexString(SHA256.HashData(boot)).Should().Be(BootHash);

        byte[] kernel = Apple3SdkModules.BuildSosKernel(SdkDirectory);
        kernel.Should().HaveCount(22016);
        kernel.AsSpan(0, 8).SequenceEqual("SOS KRNL"u8).Should().BeTrue();
        Convert.ToHexString(SHA256.HashData(kernel)).Should().Be(KernelHash);
    }

    /// <summary>
    ///  A folder without the SOS sources is refused by name.
    /// </summary>
    [TestMethod]
    public void SdkWithoutTheSourcesIsRefused()
    {
        string empty = Path.Join(Path.GetTempPath(), Path.GetRandomFileName());
        Action kernel = () => Apple3SdkModules.BuildSosKernel(empty);
        kernel.Should().Throw<FileNotFoundException>().WithMessage("*SosKernel.asm*");
        Action boot = () => Apple3SdkModules.BuildSosBoot(empty);
        boot.Should().Throw<FileNotFoundException>().WithMessage("*SosBoot.asm*");
    }

    /// <summary>
    ///  A volume with the assembled loader and kernel reads back: block 0 is the loader, block 1 is zeros, and
    ///  SOS.KERNEL is the sapling the loader looks for, in either sector order.
    /// </summary>
    /// <param name="proDosOrder">Whether the image is in ProDOS's sector order.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void AssembledBootBlocksReadBack(bool proDosOrder)
    {
        byte[] boot = Apple3SdkModules.BuildSosBoot(SdkDirectory);
        byte[] kernel = Apple3SdkModules.BuildSosKernel(SdkDirectory);
        SosVolume volume = SosVolume.Read(KernelOnly(boot, kernel).Build(proDosOrder), proDosOrder);

        volume.Block(0).Should().Equal(boot);
        volume.Block(1).Should().OnlyContain(value => value == 0);
        SosFileEntry entry = volume.Files.Single();
        (entry.Name, entry.StorageType, entry.FileType).Should().Be(("SOS.KERNEL", 2, 0x0C));
        volume.ReadFile("SOS.KERNEL").Should().Equal(kernel);
    }

    /// <summary>
    ///  Two blocks fill blocks 0 and 1; a later loader replaces the whole of an earlier one; other sizes are refused.
    /// </summary>
    [TestMethod]
    public void BootFromBytesTakesOneOrTwoBlocks()
    {
        byte[] two = [.. Enumerable.Range(0, 1024).Select(index => (byte)(index + 1))];
        SosVolumeBuilder builder = new("TEST");
        builder.BootFrom(two);
        SosVolume volume = SosVolume.Read(builder.Build(proDosOrder: false), proDosOrder: false);
        volume.Block(0).Should().Equal(two[..512]);
        volume.Block(1).Should().Equal(two[512..]);

        builder.BootFrom(new byte[512]);
        volume = SosVolume.Read(builder.Build(proDosOrder: false), proDosOrder: false);
        volume.Block(1).Should().OnlyContain(value => value == 0, "a one-block loader clears block 1");

        Action shortLoader = () => builder.BootFrom(new byte[511]);
        shortLoader.Should().Throw<ArgumentException>();
        Action longLoader = () => builder.BootFrom(new byte[1536]);
        longLoader.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Under emulation, the boot ROM runs the assembled loader, which loads the assembled kernel; SOS's loader
    ///  starts and, with no SOS.INTERP on the disk, says so.
    /// </summary>
    [TestMethod]
    public void AssembledKernelBootsAndLooksForTheInterpreter()
    {
        Apple3Machine machine = Apple3MachineTests.Machine();
        SosVolumeBuilder builder = KernelOnly(Apple3SdkModules.BuildSosBoot(SdkDirectory), Apple3SdkModules.BuildSosKernel(SdkDirectory));
        byte[] image = builder.Build(proDosOrder: false);
        machine.Drives[0].Insert(SectorDiskConverter.Convert(image, proDosOrder: false), "sdk", "DSK");
        RunUntil(machine, "INTERPRETER FILE NOT FOUND", seconds: 30);
    }

    /// <summary>
    ///  Gets the SDK's ROM sources as the tests' inputs hold them.
    /// </summary>
    internal static string SdkDirectory => Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Runs the machine until the screen shows the text, or fails after the time given.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text.</param>
    /// <param name="seconds">The emulated seconds to wait.</param>
    internal static void RunUntil(Apple3Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        Screen(machine).Should().Contain(text);
    }

    private static string Screen(Apple3Machine machine) => string.Join('\n', machine.ReadTextScreen());

    private static SosVolumeBuilder KernelOnly(byte[] boot, byte[] kernel)
    {
        SosVolumeBuilder builder = new("SDK");
        builder.BootFrom(boot);
        builder.Add("SOS.KERNEL", 0x0C, 0, kernel);
        return builder;
    }
}
