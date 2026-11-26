// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Media;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies SOS.DRIVER files built from the SDK's sources: the header, <c>Sos/SosDriverHeader.asm</c>, each driver
///  as the build makes it, and the file <see cref="SosDriverFile.Write"/> writes.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin the builds, so no disk is needed. With Apple's disks (<c>RETROCORE_APPLE3_DISKS</c>), the header
///   also compares with each disk's, and the writer rewrites each disk's SOS.DRIVER from its parts byte for byte.
///  </para>
/// </remarks>
[TestClass]
public sealed class SosDriverHeaderTests
{
    private const string Basic = "Apple3BusBasic1.23.dsk";
    private const string Utilities = "Apple3SOS1.3SysUtils.dsk";

    /// <summary>
    ///  The header assembles to its 1,314 bytes, with each drive count, and matches its digest.
    /// </summary>
    /// <param name="drives">The drive count.</param>
    /// <param name="hash">The SHA-256 of the header.</param>
    [TestMethod]
    [DataRow(3, "2377B6EACF3A4AACF1399E3D897C32BED6970FF80B167792545594209630C559")]
    [DataRow(2, "E40081AEA8A7A030357E9555FDFD209A0142B8BA22199F7CED0EAB3DDA5D184B")]
    public void HeaderMatchesItsDigest(int drives, string hash)
    {
        byte[] header = Apple3SdkModules.BuildSosDriverHeader(SosBootDiskTests.SdkDirectory, drives);
        header.Should().HaveCount(SosDriverFile.HeaderSize);
        Convert.ToHexString(SHA256.HashData(header)).Should().Be(hash);
    }

    /// <summary>
    ///  With Apple's disks, the header compares byte for byte with each SOS.DRIVER's: three drives on the Business
    ///  BASIC disk and two on the System Utilities.
    /// </summary>
    /// <param name="drives">The drive count.</param>
    /// <param name="disk">The disk.</param>
    [TestMethod]
    [DataRow(3, Basic)]
    [DataRow(2, Utilities)]
    public void HeaderMatchesTheDisk(int drives, string disk)
    {
        SosDriverFile expected = SosDriverFile.Read(SosVolumeTests.Volume(disk).ReadFile("SOS.DRIVER"));
        byte[] actual = Apple3SdkModules.BuildSosDriverHeader(SosBootDiskTests.SdkDirectory, drives);
        int first = actual.AsSpan().CommonPrefixLength(expected.Header);
        first.Should().Be(expected.Header.Length, $"the first difference is at header offset ${first:X3}");
        actual.Should().HaveCount(expected.Header.Length);
    }

    /// <summary>
    ///  The header's fields read back by name: the drive count, STANDARD's glyphs and SHOLES's keys.
    /// </summary>
    [TestMethod]
    public void HeaderFieldsReadBack()
    {
        byte[] header = Apple3SdkModules.BuildSosDriverHeader(SosBootDiskTests.SdkDirectory, drives: 1);
        SosDriverFile file = SosDriverFile.Read(SosDriverFile.Write(header, [Apple3SdkModules.BuildSosDriver(SosBootDiskTests.SdkDirectory, "Console")]));
        file.Drives.Should().Be(1);
        file.CharacterSetName.Should().Be("STANDARD");
        file.KeyboardLayoutName.Should().Be("SHOLES");

        // A's glyph: its apex, one dot at column 3, then its sides at columns 1 and 5.
        file.CharacterSet.Length.Should().Be(SosDriverFile.CharacterSetSize);
        file.CharacterSet.Slice('A' * 8, 3).ToArray().Should().Equal(0x08, 0x14, 0x22);

        // The keyboard sends Q as $51, which folds to $D1: its key's entry types q, with Alpha Lock's bit; Q; and
        // Control-Q.
        ReadOnlySpan<byte> layout = file.KeyboardLayout;
        layout.Length.Should().Be(SosDriverFile.KeyboardLayoutSize);
        int key = layout[0xD1];
        layout.Slice(key, 4).ToArray().Should().Equal((byte)('q' | 0x80), (byte)'Q', 0x11, 0x11);
        layout.Slice(layout[0xE1], 2).ToArray().Should().Equal((byte)'1', (byte)'!');
    }

    /// <summary>
    ///  The header source passes the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void HeaderDocumentationIsClean()
    {
        string path = Path.Join(SosBootDiskTests.SdkDirectory, "Apple3", "Sos", "SosDriverHeader.asm");
        SourceAnalysis analysis = SourceAnalysis.Assemble(path, _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            [],
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Lint()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Each of Apple's drivers the build makes from the SDK's source has the code SosDriverSourceTests pins: the code
    ///  after its comment record, to the last byte its source emits, padded to a word as Apple's SOS.DRIVER files
    ///  hold it.
    /// </summary>
    /// <param name="folder">The driver's folder.</param>
    /// <param name="define">A symbol to set for a build other than the default, or empty.</param>
    /// <param name="disk">Unused.</param>
    /// <param name="device">The driver's first device.</param>
    /// <param name="hash">The SHA-256 of the driver's code.</param>
    /// <param name="length">The driver's code length.</param>
    [TestMethod]
    [DynamicData(nameof(AppleBuilds))]
    public void BuiltDriverMatchesItsDigest(string folder, string define, string disk, string device, string hash, int length)
    {
        _ = disk;
        SosDriver driver = Apple3SdkModules.BuildSosDriver(SosBootDiskTests.SdkDirectory, folder, define);
        driver.Name.Should().Be(device);
        driver.Code.Should().HaveCount(length);
        Convert.ToHexString(SHA256.HashData(driver.Code)).Should().Be(hash);
        driver.Relocations.Should().BeInAscendingOrder().And.OnlyContain(offset => offset >= 0 && offset <= length - 2);
    }

    /// <summary>
    ///  Gets SosDriverSourceTests' builds of Apple's drivers, without Titan's RAM disk driver, which comes from a
    ///  driver code file rather than a SOS.DRIVER, so its length is not one the build pads.
    /// </summary>
    public static IEnumerable<object[]> AppleBuilds => SosDriverSourceTests.Builds.Where(build => (string)build[0] != "TitanRam");

    /// <summary>
    ///  With Apple's disks, each driver the build makes has the relocations and comment of the disk's driver.
    /// </summary>
    /// <param name="folder">The driver's folder.</param>
    /// <param name="define">A symbol to set for a build other than the default, or empty.</param>
    /// <param name="disk">The disk whose SOS.DRIVER has this build.</param>
    /// <param name="device">The driver's first device.</param>
    [TestMethod]
    [DataRow("Console", "", Utilities, ".CONSOLE")]
    [DataRow("Console", "RELEASE_130", Basic, ".CONSOLE")]
    [DataRow("Rs232", "", Basic, ".RS232")]
    [DataRow("Grafix", "", Basic, ".GRAFIX")]
    [DataRow("Profile", "", Utilities, ".PROFILE")]
    public void BuiltDriverMatchesTheDisk(string folder, string define, string disk, string device)
    {
        SosDriver expected = SosDriverFile.Read(SosVolumeTests.Volume(disk).ReadFile("SOS.DRIVER")).Drivers.Single(driver => driver.Name == device);
        SosDriver actual = Apple3SdkModules.BuildSosDriver(SosBootDiskTests.SdkDirectory, folder, define);
        actual.Code.Should().Equal(expected.Code);
        actual.Relocations.Should().Equal(expected.Relocations);
        actual.Comment.Should().Be(expected.Comment);
    }

    /// <summary>
    ///  A file the writer makes reads back to the same header and drivers: the console and the RS-232 drivers, in
    ///  order, each with its comment, code and relocations.
    /// </summary>
    [TestMethod]
    public void WrittenFileReadsBack()
    {
        string sdk = SosBootDiskTests.SdkDirectory;
        byte[] header = Apple3SdkModules.BuildSosDriverHeader(sdk, drives: 2);
        SosDriver[] drivers = [Apple3SdkModules.BuildSosDriver(sdk, "Console"), Apple3SdkModules.BuildSosDriver(sdk, "Rs232")];
        byte[] data = Apple3SdkModules.BuildSosDriverFile(sdk, drives: 2, ["Console", "Rs232"]);
        data.Should().Equal(SosDriverFile.Write(header, drivers));
        data.AsSpan(0, 8).SequenceEqual("SOS DRVR"u8).Should().BeTrue();
        data.AsSpan(^2).ToArray().Should().Equal(0xFF, 0xFF);

        SosDriverFile file = SosDriverFile.Read(data);
        file.Header.ToArray().Should().Equal(header);
        file.Drives.Should().Be(2);
        file.Drivers.Select(driver => driver.Name).Should().Equal(".CONSOLE", ".RS232");
        for (int index = 0; index < drivers.Length; index++)
        {
            file.Drivers[index].Comment.Should().Be(drivers[index].Comment);
            file.Drivers[index].Code.Should().Equal(drivers[index].Code);
            file.Drivers[index].Relocations.Should().Equal(drivers[index].Relocations);
        }

        file.Drivers[0].Comment.Should().StartWith("Console Driver");
    }

    /// <summary>
    ///  With Apple's disks, the writer rewrites each disk's SOS.DRIVER from its header and drivers byte for byte; the
    ///  file's blocks after the end mark are zeros.
    /// </summary>
    /// <param name="disk">The disk.</param>
    [TestMethod]
    [DataRow(Basic)]
    [DataRow(Utilities)]
    public void WriterRewritesTheDisksFile(string disk)
    {
        byte[] expected = SosVolumeTests.Volume(disk).ReadFile("SOS.DRIVER");
        SosDriverFile file = SosDriverFile.Read(expected);
        byte[] actual = SosDriverFile.Write(file.Header, file.Drivers);
        int first = actual.AsSpan().CommonPrefixLength(expected);
        first.Should().Be(actual.Length, $"the first difference is at ${first:X4}");
        expected.AsSpan(actual.Length).ToArray().Should().OnlyContain(value => value == 0);
    }

    /// <summary>
    ///  The writer refuses what SOS's loader cannot load: a short header, no drivers, code too short for the flags of
    ///  each DIB along its chain (or, for a page-aligned driver, its DCB's length), a relocation outside the code; and,
    ///  stricter than the loader, a drive count outside 1-4 and a comment that is not ASCII.
    /// </summary>
    [TestMethod]
    public void WriterRefusesWhatSosCannotLoad()
    {
        byte[] header = Apple3SdkModules.BuildSosDriverHeader(SosBootDiskTests.SdkDirectory, drives: 1);
        SosDriver console = Apple3SdkModules.BuildSosDriver(SosBootDiskTests.SdkDirectory, "Console");

        Action shortHeader = () => SosDriverFile.Write(header.AsSpan(1), [console]);
        shortHeader.Should().Throw<ArgumentException>().WithParameterName("header");
        byte[] five = [.. header];
        five[0] = 5;
        Action tooManyDrives = () => SosDriverFile.Write(five, [console]);
        tooManyDrives.Should().Throw<ArgumentException>().WithParameterName("header");
        Action none = () => SosDriverFile.Write(header, []);
        none.Should().Throw<ArgumentException>().WithParameterName("drivers");
        Action tiny = () => SosDriverFile.Write(header, [new SosDriver("", new byte[20], [])]);
        tiny.Should().Throw<ArgumentException>().WithParameterName("drivers");
        SosDriverFile.Read(SosDriverFile.Write(header, [new SosDriver("", new byte[21], [])])).Drivers.Should().ContainSingle();
        byte[] aligned = new byte[0x21];
        aligned[0x14] = 0xC0;
        Action unaligned = () => SosDriverFile.Write(header, [new SosDriver("", aligned, [])]);
        unaligned.Should().Throw<ArgumentException>().WithParameterName("drivers");
        byte[] reaches = new byte[0x22];
        reaches[0x14] = 0xC0;
        SosDriverFile.Read(SosDriverFile.Write(header, [new SosDriver("", reaches, [])])).Drivers.Should().ContainSingle();

        // The loader reads the DCB length at $20 for any active page-aligned DIB along the chain, not only the first.
        byte[] second = new byte[0x21];
        second[0] = 0x08;
        second[0x08 + 0x14] = 0xC0;
        Action chained = () => SosDriverFile.Write(header, [new SosDriver("", second, [])]);
        chained.Should().Throw<ArgumentException>().WithParameterName("drivers");
        byte[] past = new byte[0x21];
        past[0] = 0x10;
        Action pastCode = () => SosDriverFile.Write(header, [new SosDriver("", past, [])]);
        pastCode.Should().Throw<ArgumentException>().WithParameterName("drivers");

        // The loader ends a chain only at a link of 0: a DIB that links to itself, or a loop, never ends.
        byte[] chain = new byte[0x30];
        chain[0] = 0x10;
        SosDriverFile.Read(SosDriverFile.Write(header, [new SosDriver("", chain, [])])).Drivers.Should().ContainSingle();
        byte[] self = new byte[0x30];
        self[0x10] = 0x10;
        self[0] = 0x10;
        Action selfLink = () => SosDriverFile.Write(header, [new SosDriver("", self, [])]);
        selfLink.Should().Throw<ArgumentException>().WithParameterName("drivers");
        byte[] loop = new byte[0x30];
        loop[0] = 0x10;
        loop[0x10] = 0x08;
        loop[0x08] = 0x10;
        Action loops = () => SosDriverFile.Write(header, [new SosDriver("", loop, [])]);
        loops.Should().Throw<ArgumentException>().WithParameterName("drivers");
        Action outside = () => SosDriverFile.Write(header, [console with { Relocations = [console.Code.Length - 1] }]);
        outside.Should().Throw<ArgumentException>().WithParameterName("drivers");
        Action notAscii = () => SosDriverFile.Write(header, [console with { Comment = "café" }]);
        notAscii.Should().Throw<ArgumentException>().WithParameterName("drivers");

        Action drives = () => Apple3SdkModules.BuildSosDriverHeader(SosBootDiskTests.SdkDirectory, drives: 0);
        drives.Should().Throw<ArgumentOutOfRangeException>();
    }
}
