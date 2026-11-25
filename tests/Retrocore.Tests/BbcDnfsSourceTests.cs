// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Acorn;
using Retrocore.Media.Acorn;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the BBC Micro's DNFS 1.20, <c>Dnfs.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (MAME's <c>bbcb</c> set in <c>RETROCORE_BBC_ROMS</c>
///   or <c>%USERPROFILE%\Retrocore\bbc-roms\extract\bbcb</c>), the build also compares byte for byte, which names the
///   first difference. <c>RETROCORE_DNFS_SOURCE</c> points the tests at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcDnfsSourceTests
{
    // The SHA-256 of DNFS 1.20, dnfs120.rom (SHA-1 7e3c536baeae84d6498a14e8405319e01ee78232).
    private const string DnfsHash = "E745E34895225A6650B712C1DD0656CB0B0B15F072A8AE6D9EA8D1AC257EB3D6";

    private const int DnfsOrigin = 0x8000;
    private const int DnfsSize = 0x4000;

    /// <summary>
    ///  The source assembles without diagnostics to the ROM's 16K.
    /// </summary>
    [TestMethod]
    public void DnfsMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(DnfsSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(DnfsHash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void DnfsMatchesTheDump()
    {
        string path = Path.Join(BbcMachineTests.RomDirectory, "dnfs120.rom");
        if (!File.Exists(path)) { Assert.Inconclusive($"DNFS 1.20 ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Should().HaveCount(DnfsSize);
        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(DnfsSize, $"the first difference is at ${DnfsOrigin + first:X4}");
    }

    /// <summary>
    ///  A Model B with the DFS from the source's build saves a program to a blank disk, loads it back and runs it, and
    ///  catalogues the Welcome disk.
    /// </summary>
    [TestMethod]
    public void MachineUsesDisksWithTheSource()
    {
        if (!File.Exists(Path.Join(BbcMachineTests.RomDirectory, "os12.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_BBC_ROMS to a folder with MAME's bbcb set unzipped.");
        }

        BbcRoms roms = BbcRoms.LoadFromDirectory(BbcMachineTests.RomDirectory, filingSystem: null);
        roms.Fit(0, Assemble().Sections[0].Bytes.Span);
        BbcMachine machine = new(roms);
        machine.Drives[0].Insert(AcornDiskImage.Read(BbcDiskTests.Welcome(), doubleSided: false), "welcome.ssd", "SSD");
        machine.Drives[1].Insert(AcornDiskImage.Blank(80), "blank.ssd", "SSD");
        BbcMachineTests.RunToPrompt(machine).Should().Contain(line => line.TrimEnd() == "Acorn DFS");

        BbcDiskTests.Command(machine, "*DRIVE 1\r10 PRINT \"SAVED OK\"\rSAVE \"PROG\"\r");
        string[] screen = BbcDiskTests.Command(machine, "NEW\rLOAD \"PROG\"\rRUN\r*CAT 0\r");
        string text = string.Join('\n', screen);
        screen.Should().Contain("SAVED OK", text);
        screen.Should().Contain("WELCOME-DISK (04)", text);
    }

    /// <summary>
    ///  The source, its parts and its equates pass the documentation lint as the editor runs it, with the MOS's
    ///  source for the names it links to.
    /// </summary>
    [TestMethod]
    public void DnfsDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath(), _ => null);
        SourceAnalysis mos = SourceAnalysis.Assemble(Path.Join(Path.GetDirectoryName(SourcePath()), "Mos.asm"), _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules([mos]).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Lint()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Assembles DNFS 1.20 from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the ROM's 16K.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, DnfsOrigin, DnfsSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // RETROCORE_DNFS_SOURCE, then the test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_DNFS_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn", "Dnfs.asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("Dnfs.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Acorn", "Roms", "Dnfs.asm"));
    }
}
