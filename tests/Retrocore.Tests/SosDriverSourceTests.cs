// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for SOS's drivers, in <c>Sos/Drivers</c>: each builds the driver's code as Apple's
///  SOS.DRIVER files hold it, with the same relocation table and comment.
/// </summary>
/// <remarks>
///  <para>
///   A driver's code is assembled for address 0, as SOS.DRIVER stores it, after its comment record when it has one.
///   The words SOS relocates are those that move when the driver is assembled elsewhere. A digest pins each build, so
///   no disk is needed; with Apple's disks (<c>RETROCORE_APPLE3_DISKS</c>), each also compares with the driver in that
///   disk's SOS.DRIVER, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class SosDriverSourceTests
{
    private const string Basic = "Apple3BusBasic1.23.dsk";
    private const string Utilities = "Apple3SOS1.3SysUtils.dsk";

    // Titan's startup disk, whose RAMDISK.DRIVER is a driver code file for the System Configuration Program.
    private const string Titan = "Titan III Plus IIe Startup Disk.dsk";

    /// <summary>
    ///  Each driver build's code matches its digest.
    /// </summary>
    /// <param name="folder">The driver's folder, which holds its root of the same name.</param>
    /// <param name="define">A symbol to set for a build other than the default, or empty.</param>
    /// <param name="disk">The disk whose SOS.DRIVER has this build.</param>
    /// <param name="device">The driver's first device.</param>
    /// <param name="hash">The SHA-256 of the driver's code.</param>
    /// <param name="length">The driver's code length.</param>
    [TestMethod]
    [DynamicData(nameof(Builds))]
    public void DriverMatchesItsDigest(string folder, string define, string disk, string device, string hash, int length)
    {
        _ = disk;
        _ = device;
        (byte[] Code, int[] Relocations, string Comment) driver = Build(folder, define, length);
        Convert.ToHexString(SHA256.HashData(driver.Code)).Should().Be(hash);
    }

    /// <summary>
    ///  With Apple's disk, each driver build compares with that disk's driver: code, relocations and comment.
    /// </summary>
    /// <param name="folder">The driver's folder.</param>
    /// <param name="define">A symbol to set for a build other than the default, or empty.</param>
    /// <param name="disk">The disk whose SOS.DRIVER has this build.</param>
    /// <param name="device">The driver's first device.</param>
    /// <param name="hash">The SHA-256 of the driver's code.</param>
    /// <param name="length">The driver's code length.</param>
    [TestMethod]
    [DynamicData(nameof(Builds))]
    public void DriverMatchesTheDisk(string folder, string define, string disk, string device, string hash, int length)
    {
        _ = hash;
        SosVolume volume = SosVolumeTests.Volume(disk);
        SosDriver expected = disk == Titan ? SosDriverCodeFile.Read(volume.ReadFile("RAMDISK.DRIVER")) : FromDriverFile();
        (byte[] Code, int[] Relocations, string Comment) actual = Build(folder, define, length);

        int first = actual.Code.AsSpan().CommonPrefixLength(expected.Code);
        first.Should().Be(expected.Code.Length, $"the first difference is at offset ${first:X4}");
        actual.Code.Should().HaveCount(expected.Code.Length);
        actual.Relocations.Should().Equal(expected.Relocations);
        actual.Comment.Should().Be(expected.Comment);

        SosDriver FromDriverFile()
        {
            SosDriverFile file = SosDriverFile.Read(volume.ReadFile("SOS.DRIVER"));
            return file.Drivers.Single(driver => driver.Name == device);
        }
    }

    /// <summary>
    ///  Each driver's sources pass the documentation lint as the editor runs it.
    /// </summary>
    /// <param name="folder">The driver's folder.</param>
    /// <param name="define">Unused.</param>
    /// <param name="disk">Unused.</param>
    /// <param name="device">Unused.</param>
    /// <param name="hash">Unused.</param>
    /// <param name="length">Unused.</param>
    [TestMethod]
    [DynamicData(nameof(Builds))]
    public void DriverDocumentationIsClean(string folder, string define, string disk, string device, string hash, int length)
    {
        _ = (define, disk, device, hash, length);
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath(folder), _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            [],
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Check()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Gets the driver builds: folder, symbol, disk, device, and the digest and length of its code.
    /// </summary>
    public static IEnumerable<object[]> Builds =>
    [
        ["Console", "", Utilities, ".CONSOLE", "253233F62F018CC414979EB3E20697AE18F464B3E7725858177FE483692E373E", 4003],
        ["Console", "RELEASE_130", Basic, ".CONSOLE", "DBA2F45DE8826D6FC190B7378250B772B33546403DEFB387FFCA516C38E01DC3", 4007],
        ["Rs232", "", Basic, ".RS232", "41DCCD6404C16C93BFFFF07C5EFE73EA5BE3810F00B98D7FD4FB4D204B45EA2A", 1887],
        ["Printer", "", Basic, ".PRINTER", "4AF9B8303D91AB816F53C8BB0AD3F2BF0EDE4901E97573CF9EC8427A371AE77A", 746],
        ["Profile", "", Utilities, ".PROFILE", "B6AEBBA0490D3091553CA7998EC8F0183A741F608FC02AC69CCF2B4FF08BBDFB", 1981],
        ["Fmtd1", "", Utilities, ".FMTD1", "C8719107C4D9A6376F4ABFE673774CE4F3BA19F8B8E53922A6D396E76B83EE2E", 1127],
        ["Audio", "", Basic, ".AUDIO", "C01264A4BD4AEE7EBE07D92F163518CBC7837BF79A32CFBC9575699D34DB13E2", 552],
        ["Grafix", "", Basic, ".GRAFIX", "390AAA55691B29F435235AE8DCA2D4132B50A62316FA8FCD4A062CC1CE4C5896", 4513],
        ["Silentype", "", Basic, ".SILENTYPE", "9D2AF575EEBB97A1D3F28ECB13D880EB3B4AD4852A1EE9C0767A3ED0F331790A", 3756],
        ["Ram", "", Utilities, ".RAM", "B66781AB32607257F05FEA51A0C670EA7AD457872E54F9DA47434260EC8E66CF", 1400],
        ["TitanRam", "", Titan, ".RAM", "0EEFA6FE35511C1CE2AAC5CF602D1CE4057CCDC99F72F2A200B4BDA88F21238D", 12943],
    ];

    // Assembles the driver at two origins: its code from the first, and the words that move between them.
    private static (byte[] Code, int[] Relocations, string Comment) Build(string folder, string define, int length)
    {
        (byte[] code, string comment) = Code(Assemble(folder, define, 0), length);
        (byte[] moved, _) = Code(Assemble(folder, define, 0x1000), length);
        List<int> relocations = [];
        for (int offset = 1; offset < code.Length; offset++)
        {
            if ((byte)(moved[offset] - code[offset]) == 0x10 && moved[offset - 1] == code[offset - 1])
            {
                relocations.Add(offset - 1);
            }
        }

        return (code, [.. relocations], comment);
    }

    // The code: its length after the comment record ($FFFF, the comment's length and its text) when there is one.
    // The source must emit nothing past it.
    private static (byte[] Code, string Comment) Code(AssemblyResult result, int length)
    {
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        int start = 0;
        string comment = "";
        if (bytes[0] == 0xFF && bytes[1] == 0xFF)
        {
            int size = bytes[2] | (bytes[3] << 8);
            comment = Encoding.ASCII.GetString(bytes.Slice(4, size));
            start = 4 + size;
        }

        int end = result.SourceMap.Where(entry => entry.Section == 0).Max(entry => entry.Offset + entry.Size);
        end.Should().BeLessThanOrEqualTo(start + length, "the source ends where the driver does");
        return (bytes.Slice(start, length).ToArray(), comment);
    }

    private static AssemblyResult Assemble(string folder, string define, int origin)
    {
        string root = SourcePath(folder);
        string text = File.ReadAllText(root);
        string path = root;
        if (define.Length != 0)
        {
            path = Path.Join(Path.GetDirectoryName(root), $"_{define}.asm");
            text = $"{define} = 1\n.include \"{Path.GetFileName(root)}\"\n";
        }

        return new Assembler.Assembler().Assemble(
            new AssemblySource(text, path),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin, 0x8000)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // The test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath(string folder)
    {
        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "Sos", "Drivers", folder, folder + ".asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive($"{folder}.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Apple3", "Roms", "Sos", "Drivers", folder, folder + ".asm"));
    }
}
