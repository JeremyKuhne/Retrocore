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
///  Verifies the SDK's native source for the SAA5050's characters, <c>Saa5050.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (MAME's <c>saa5050</c> in <c>RETROCORE_BBC_ROMS</c>
///   or <c>%USERPROFILE%\Retrocore\bbc-roms\extract\bbcb</c>), the build also compares byte for byte.
///   <c>RETROCORE_SAA5050_SOURCE</c> points the tests at another copy of the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcSaa5050SourceTests
{
    // The SHA-256 of MAME's saa5050 (SHA-1 6c8daba70374e5aa3a6402f24cdc5f8677d58a0f).
    private const string CharactersHash = "9706945B02DD0E30823186FF0D73A49C0D98ED573499A057BAB471ADD7EE28FB";

    private const int CharactersSize = 960;

    /// <summary>
    ///  The source assembles without diagnostics to the 96 characters.
    /// </summary>
    [TestMethod]
    public void CharactersMatchTheirDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(CharactersSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(CharactersHash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void CharactersMatchTheDump()
    {
        string path = Path.Join(BbcMachineTests.RomDirectory, "saa5050");
        if (!File.Exists(path)) { Assert.Inconclusive($"The SAA5050's characters ({path}) are missing."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Should().HaveCount(CharactersSize);
        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(CharactersSize, $"the first difference is at ${first:X3}");
    }

    /// <summary>
    ///  A Model B with the characters from the source's build draws mode 7 exactly as it does with the dump.
    /// </summary>
    [TestMethod]
    public void MachineDrawsTeletextFromTheSource()
    {
        if (!File.Exists(Path.Join(BbcMachineTests.RomDirectory, "os12.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_BBC_ROMS to a folder with MAME's bbcb set unzipped.");
        }

        BbcRoms dumps = BbcRoms.LoadFromDirectory(BbcMachineTests.RomDirectory, filingSystem: null);
        BbcRoms roms = new(dumps.Mos, Assemble().Sections[0].Bytes.Span);
        roms.Fit(3, dumps.Socket(3));

        byte[] fromSource = Frame(new BbcMachine(roms));
        byte[] fromDump = Frame(new BbcMachine(dumps));
        fromSource.AsSpan().SequenceEqual(fromDump).Should().BeTrue("the two frames should be the same");
    }

    /// <summary>
    ///  The source passes the documentation lint as the editor runs it, with the MOS's source for its links.
    /// </summary>
    [TestMethod]
    public void CharactersDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath(), _ => null);
        SourceAnalysis mos = SourceAnalysis.Assemble(Path.Join(Path.GetDirectoryName(SourcePath()), "Mos.asm"), _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules([mos]).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Check()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Assembles the SAA5050's characters from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the 960 bytes.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, CharactersSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // Starts the machine, prints every character in each colour's text, and renders a frame.
    private static byte[] Frame(BbcMachine machine)
    {
        BbcMachineTests.RunToPrompt(machine);
        BbcMachineTests.Type(machine, "FOR I%=32 TO 126:VDU I%:NEXT:PRINT CHR$131;\"Yellow \";CHR$141;\"Tall\"\r");
        return machine.Video.RenderBitmap();
    }

    // RETROCORE_SAA5050_SOURCE, then the test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_SAA5050_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn", "Saa5050.asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("Saa5050.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Acorn", "Roms", "Saa5050.asm"));
    }
}
