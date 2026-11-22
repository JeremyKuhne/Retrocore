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
///  Verifies the SDK's native source for BBC BASIC II, <c>BbcBasic.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (MAME's <c>bbcb</c> set in <c>RETROCORE_BBC_ROMS</c>
///   or <c>%USERPROFILE%\Retrocore\bbc-roms\extract\bbcb</c>), the build also compares byte for byte, which names the
///   first difference. <c>RETROCORE_BASIC_SOURCE</c> points the tests at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcBasicSourceTests
{
    // The SHA-256 of BASIC II, basic2.rom (SHA-1 4a7393f3a45ea309f744441c16723e2ef447a281).
    private const string BasicHash = "45BD55DC0F6F0F8F1FE9E2481DE7DEF206565EEC8F600BA3068B849CA4132079";

    private const int BasicOrigin = 0x8000;
    private const int BasicSize = 0x4000;

    /// <summary>
    ///  The source assembles without diagnostics to BASIC's 16K.
    /// </summary>
    [TestMethod]
    public void BasicMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(BasicSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(BasicHash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void BasicMatchesTheDump()
    {
        string path = Path.Join(BbcMachineTests.RomDirectory, "basic2.rom");
        if (!File.Exists(path)) { Assert.Inconclusive($"BASIC II ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Should().HaveCount(BasicSize);
        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(BasicSize, $"the first difference is at ${BasicOrigin + first:X4}");
    }

    /// <summary>
    ///  The Model B runs a program with BASIC from the source's build and the MOS from the dump.
    /// </summary>
    [TestMethod]
    public void MachineRunsBasicFromTheSource()
    {
        if (!File.Exists(Path.Join(BbcMachineTests.RomDirectory, "os12.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_BBC_ROMS to a folder with MAME's bbcb set unzipped.");
        }

        BbcRoms dumps = BbcRoms.LoadFromDirectory(BbcMachineTests.RomDirectory, filingSystem: null);
        BbcRoms roms = new(dumps.Mos, dumps.Characters);
        roms.Fit(3, Assemble().Sections[0].Bytes.Span);

        BbcMachine machine = new(roms);
        string[] screen = BbcMachineTests.RunToPrompt(machine);
        screen.Should().Contain(line => line.TrimEnd() == "BASIC");
        BbcMachineTests.Type(machine, "10 FOR I%=1 TO 3:PRINT I%*7,SQR(16)\r");
        BbcMachineTests.Type(machine, "20 NEXT\rRUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "        21         4");
    }

    /// <summary>
    ///  The source, its parts and its equates pass the documentation lint as the editor runs it, with the MOS's
    ///  source for the names it links to.
    /// </summary>
    [TestMethod]
    public void BasicDocumentationIsClean()
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
    ///  Assembles BASIC II from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the ROM's 16K.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, BasicOrigin, BasicSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // RETROCORE_BASIC_SOURCE, then the test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_BASIC_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn", "BbcBasic.asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("BbcBasic.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Acorn", "Roms", "BbcBasic.asm"));
    }
}
