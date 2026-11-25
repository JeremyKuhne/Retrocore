// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Atari;
using Retrocore.Media.Atari;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the 810's firmware, <c>Atari810.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins each build, so no ROM is needed. With MAME's <c>atari810</c> set beside the OS ROMs, each build
///   also compares byte for byte, which names the first difference. <c>RETROCORE_ATARI_810_SOURCE</c> points the tests
///   at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class Atari810SourceTests
{
    private const int Origin = 0x0800;
    private const int Size = Atari810.RomSize;

    private const int VersionB = 2;
    private const int VersionC = 3;

    /// <summary>
    ///  Each build assembles without diagnostics to its 2K, whose SHA-256 is its ROM's.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="hash">The ROM's SHA-256.</param>
    [TestMethod]
    [DataRow(VersionC, "2259550B171B54E409050DBDF25E0F7C88D840E93923789BC91B3D2EC92EE488")]
    [DataRow(VersionB, "50A3F924764D61853752BA561823ACAF7BB480E6304470F9009195CC4762A21D")]
    public void BuildMatchesItsDigest(int version, string hash)
    {
        AssemblyResult result = Assemble(version);
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Size);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(hash);
    }

    /// <summary>
    ///  With MAME's <c>atari810</c> set, each build compares byte for byte.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="file">The ROM's file in the set.</param>
    [TestMethod]
    [DataRow(VersionC, Atari810Firmware.RevisionCFile)]
    [DataRow(VersionB, Atari810Firmware.RevisionBFile)]
    public void BuildMatchesTheRom(int version, string file)
    {
        string path = Path.Join(Path.GetDirectoryName(AtariMachineTests.RomDirectory), "atari810", file);
        if (!File.Exists(path)) { Assert.Inconclusive($"The 810's firmware isn't at {path}."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Length.Should().Be(Size);
        ReadOnlySpan<byte> actual = Assemble(version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(Size, $"the first difference is at ${Origin + first:X4}");
    }

    /// <summary>
    ///  Each build tells the emulator which revision it is, and a disk is laid out in its format's order.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="revision">Its revision.</param>
    [TestMethod]
    [DataRow(VersionC, 'C')]
    [DataRow(VersionB, 'B')]
    public void LayoutFollowsTheBuildsOrder(int version, char revision)
    {
        byte[] rom = Assemble(version).Sections[0].Bytes.ToArray();
        Atari810Firmware.Revision(rom).Should().Be(revision);

        byte[] order = [18, .. rom.AsSpan(0x6F, 17).ToArray().Select(value => (byte)~value)];
        Atari810Disk disk = new(AtariDisk.Create(), revision);
        disk.Floppy.Track(0, 0).Select(sector => sector.Sector).Should().Equal(order);
    }

    /// <summary>
    ///  An 800 with an 810 boots a disk on the SDK's OS, floating point package and 810 firmware, with no dumps: the
    ///  drive reads the boot sector, whose code marks memory, then parks its head on track 39 and stops its motor.
    /// </summary>
    [TestMethod]
    public void DiskBootsOnTheSources()
    {
        byte[] image =
        [
            .. AtariFloatingPointSourceTests.Assemble().Sections[0].Bytes.Span,
            .. AtariOsSourceTests.Assemble().Sections[0].Bytes.Span
        ];

        AtariMachine machine = new(
            new AtariRoms(image, Assemble().Sections[0].Bytes.Span),
            diskDrives: 1);

        // One boot sector loaded at $0700: its code at $0706 stores $A5 at $0600 and loops.
        byte[] boot = new byte[128];
        byte[] header = [0x00, 0x01, 0x00, 0x07, 0x0B, 0x07];
        byte[] code = [0xA9, 0xA5, 0x8D, 0x00, 0x06, 0x4C, 0x0B, 0x07];
        header.CopyTo(boot, 0);
        code.CopyTo(boot, 6);
        AtariDisk disk = AtariDisk.Create();
        disk.WriteSector(1, boot);

        Atari810 drive = (Atari810)machine.Drives[0];
        drive.Revision.Should().Be('C');
        drive.Insert(disk, "boot.atr");

        for (int tenth = 0; tenth < 200 && machine.Bus.Peek(0x0600) != 0xA5; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        machine.Bus.Peek(0x0600).Should().Be(0xA5, "the boot sector's code ran");

        machine.Run(TimeSpan.FromSeconds(10));
        drive.Track.Should().Be(39);
        drive.Motor.Should().BeFalse();
    }

    /// <summary>
    ///  Each build of the source passes the documentation lint as the editor runs it.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    [TestMethod]
    [DataRow(VersionC)]
    [DataRow(VersionB)]
    public void DocumentationIsClean(int version)
    {
        string path = SourcePath();
        string root = path;
        DirectoryInfo? temporary = null;
        if (version != VersionC)
        {
            // The lint reads a build's VERSION from the source, so a wrapper sets it.
            temporary = Directory.CreateTempSubdirectory();
            root = Path.Join(temporary.FullName, "Atari810.asm");
            File.WriteAllText(root, $"VERSION = {version}\n.include \"{path.Replace('\\', '/')}\"\n");
        }

        SourceAnalysis analysis;
        try
        {
            analysis = SourceAnalysis.Assemble(root, _ => null);
        }
        finally
        {
            temporary?.Delete(recursive: true);
        }

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
    ///  Assembles the 810's firmware from the SDK's source.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>: 2 for revision B, 3 for revision C (the default).</param>
    /// <returns>The assembly, its one section the ROM's 2K.</returns>
    internal static AssemblyResult Assemble(int version = VersionC)
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, Origin, Size)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = new Dictionary<string, long> { ["VERSION"] = version }
            });
    }

    // RETROCORE_ATARI_810_SOURCE, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_ATARI_810_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("Atari810.asm is not in the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Atari", "Roms", "Atari810.asm"));
    }
}
