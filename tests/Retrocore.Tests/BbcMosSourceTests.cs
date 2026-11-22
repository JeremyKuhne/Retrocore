// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Acorn;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the BBC Micro's MOS 1.20, <c>Mos.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (MAME's <c>bbcb</c> set in <c>RETROCORE_BBC_ROMS</c>
///   or <c>%USERPROFILE%\Retrocore\bbc-roms\extract\bbcb</c>), the build also compares byte for byte, which names the
///   first difference. <c>RETROCORE_MOS_SOURCE</c> points the tests at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcMosSourceTests
{
    // The SHA-256 of MOS 1.20, os12.rom (SHA-1 0d9bcaf6a393c9ce2359ed700ddb53c232c2c45d).
    private const string MosHash = "2D9FEA69017864F6962704481829F95FEE08446C8C3A13826D5D4E44000AC9DE";

    private const int MosOrigin = 0xC000;
    private const int MosSize = 0x4000;

    /// <summary>
    ///  The source assembles without diagnostics to the MOS's 16K.
    /// </summary>
    [TestMethod]
    public void MosMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(MosSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(MosHash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void MosMatchesTheDump()
    {
        string path = Path.Join(BbcMachineTests.RomDirectory, "os12.rom");
        if (!File.Exists(path)) { Assert.Inconclusive($"MOS 1.20 ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Should().HaveCount(MosSize);
        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(MosSize, $"the first difference is at ${MosOrigin + first:X4}");
    }

    /// <summary>
    ///  The Model B starts from the source's build, with BASIC II from the dump, to BASIC's prompt.
    /// </summary>
    [TestMethod]
    public void MachineStartsFromTheSource()
    {
        if (!File.Exists(Path.Join(BbcMachineTests.RomDirectory, "basic2.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_BBC_ROMS to a folder with MAME's bbcb set unzipped.");
        }

        BbcRoms dumps = BbcRoms.LoadFromDirectory(BbcMachineTests.RomDirectory, filingSystem: null);
        BbcRoms roms = new(Assemble().Sections[0].Bytes.Span, dumps.Characters);
        roms.Fit(3, dumps.Socket(3));

        string[] screen = BbcMachineTests.RunToPrompt(new BbcMachine(roms));
        screen[1].Should().StartWith("BBC Computer 32K");
        screen.Should().Contain(line => line.StartsWith('>'));
    }

    /// <summary>
    ///  The source, its parts and its equates pass the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void MosDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath(), _ => null);
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
    ///  Assembles MOS 1.20 from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the ROM's 16K.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, MosOrigin, MosSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // RETROCORE_MOS_SOURCE, then the test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_MOS_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn", "Mos.asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("Mos.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Acorn", "Roms", "Mos.asm"));
    }
}
