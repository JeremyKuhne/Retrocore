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
///  Verifies the SDK's native source for the Atari 400/800's floating point package, <c>FloatingPoint.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (co12399b, the same chip in every OS), the build
///   also compares byte for byte, which names the first difference. <c>RETROCORE_ATARI_FP_SOURCE</c> points the tests
///   at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class AtariFloatingPointSourceTests
{
    // The SHA-256 of co12399b.
    private const string Hash = "B1F7774BAD07E02E03EF53ECE3C29A5B7546FE967A42A73D0A4F65CE6248BDE7";

    private const int Origin = 0xD800;
    private const int Size = 0x0800;

    /// <summary>
    ///  The source assembles without diagnostics to the chip's 2K.
    /// </summary>
    [TestMethod]
    public void BuildMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Size);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(Hash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void BuildMatchesTheDump()
    {
        string path = Path.Join(AtariMachineTests.RomDirectory, "co12399b.rom");
        if (!File.Exists(path)) { Assert.Inconclusive($"The floating point chip {path} is missing."); }

        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(File.ReadAllBytes(path));
        first.Should().Be(Size, $"the first difference is at ${Origin + first:X4}");
    }

    /// <summary>
    ///  An 800 runs from the SDK's builds alone, the floating point package and the OS, to Memo Pad.
    /// </summary>
    [TestMethod]
    public void MachineStartsFromTheSources()
    {
        byte[] image = [.. Assemble().Sections[0].Bytes.Span, .. AtariOsSourceTests.Assemble().Sections[0].Bytes.Span];
        AtariMachine machine = new(new AtariRoms(image));
        string[] screen = AtariMachineTests.RunUntil(machine, line => line.Contains("MEMO PAD", StringComparison.Ordinal));
        screen.Should().Contain(line => line.Trim() == "ATARI COMPUTER - MEMO PAD");
    }

    /// <summary>
    ///  The source and its parts pass the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void DocumentationIsClean()
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
    ///  Each of <c>FloatingPointEntries.asm</c>'s equates, which the sources that call the package include, has the
    ///  address of the package's label of the same name.
    /// </summary>
    [TestMethod]
    public void EntriesMatchTheSource()
    {
        string entries = Path.Join(Path.GetDirectoryName(SourcePath()), "FloatingPointEntries.asm");
        AtariOsSourceTests.EntryMismatches(entries, Assemble().Symbols).Should().BeEmpty();
    }

    /// <summary>
    ///  Assembles the floating point package from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the chip's 2K.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, Origin, Size)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // RETROCORE_ATARI_FP_SOURCE, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_ATARI_FP_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("FloatingPoint.asm is not in the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Atari", "Roms", "FloatingPoint.asm"));
    }
}
