// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Atari;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the Atari 400/800's OS, <c>Os.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dumps (MAME's <c>a800</c> set in
///   <c>RETROCORE_ATARI_ROMS</c> or <c>%USERPROFILE%\Retrocore\atari8-roms\extract\a800</c>), the build also compares
///   byte for byte, which names the first difference. <c>RETROCORE_ATARI_OS_SOURCE</c> points the tests at another
///   copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class AtariOsSourceTests
{
    private const int Origin = 0xE000;
    private const int Size = 0x2000;

    private const int VersionA = 1;
    private const int VersionB = 2;
    private const int VersionPal = 3;

    /// <summary>
    ///  Each build assembles without diagnostics to its 8K, whose SHA-256 is that of its two chips in address order.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="hash">The chips' SHA-256.</param>
    [TestMethod]
    [DataRow(VersionB, "C360F85832D56B377F51533C2B2E00179E8D61361BF2CB53BC0B546425D6F766")]
    [DataRow(VersionA, "0838DA6141ECFE8555FE75E7A04F8C4111257E154D41DEFDC2D4D45D264090F5")]
    [DataRow(VersionPal, "13DB31CCFE5432BFEAED7D89F09638D9E6C08888B0DADAB5527A9E3DEEA88C4D")]
    public void BuildMatchesItsDigest(int version, string hash)
    {
        AssemblyResult result = Assemble(version);
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Size);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(hash);
    }

    /// <summary>
    ///  With the dumps, each build compares byte for byte.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="set">The MAME set's folder, beside <c>a800</c>.</param>
    /// <param name="low">The $E000 chip.</param>
    /// <param name="high">The $F000 chip.</param>
    [TestMethod]
    [DataRow(VersionB, "a800", "co12499b.rom", "co14599b.rom")]
    [DataRow(VersionA, "a800", "co12499a.rom", "co14599a.rom")]
    [DataRow(VersionPal, "a800pal", "co15199.rom", "co15299.rom")]
    public void BuildMatchesTheDump(int version, string set, string low, string high)
    {
        byte[] expected = Dump(set, low, high);
        ReadOnlySpan<byte> actual = Assemble(version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(Size, $"the first difference is at ${Origin + first:X4}");
    }

    /// <summary>
    ///  An 800 with no cartridge starts from the source's build, with the floating point chip from the dump, to Memo
    ///  Pad.
    /// </summary>
    [TestMethod]
    public void MachineStartsFromTheSource()
    {
        byte[] floatingPoint = Dump("a800", "co12399b.rom");
        byte[] image = [.. floatingPoint, .. Assemble().Sections[0].Bytes.Span];
        AtariMachine machine = new(new AtariRoms(image));
        string[] screen = AtariMachineTests.RunUntil(machine, line => line.Contains("MEMO PAD", StringComparison.Ordinal));
        screen.Should().Contain(line => line.Trim() == "ATARI COMPUTER - MEMO PAD");
    }

    /// <summary>
    ///  The source, its parts and its equates pass the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void OsDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath(), _ => null);
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
    ///  Assembles the OS from the SDK's source.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>: 1 for rev. A, 2 for rev. B (the default), 3 for PAL.</param>
    /// <returns>The assembly, its one section the OS's 8K.</returns>
    internal static AssemblyResult Assemble(int version = VersionB)
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

    // The chips from a MAME set's folder beside a800's, in order, or inconclusive without them.
    private static byte[] Dump(string set, params string[] files)
    {
        List<byte> bytes = [];
        foreach (string file in files)
        {
            string path = Path.Join(Path.GetDirectoryName(AtariMachineTests.RomDirectory), set, file);
            if (!File.Exists(path)) { Assert.Inconclusive($"The OS chip {path} is missing."); }
            bytes.AddRange(File.ReadAllBytes(path));
        }

        return [.. bytes];
    }

    // RETROCORE_ATARI_OS_SOURCE, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_ATARI_OS_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("Os.asm is not in the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Atari", "Roms", "Os.asm"));
    }
}
