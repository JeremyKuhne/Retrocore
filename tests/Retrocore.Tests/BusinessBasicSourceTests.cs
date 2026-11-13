// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's Business BASIC source, <c>BusinessBasic/BusinessBasic.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin the builds, so no disk is needed. With Apple's Business BASIC 1.23 disk (in
///   <c>RETROCORE_APPLE3_DISKS</c> or <c>%USERPROFILE%\Retrocore\apple3-disks</c>), the 1.23 build also compares byte
///   for byte with its <c>SOS.INTERP</c>, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class BusinessBasicSourceTests
{
    // The SHA-256 of Business BASIC 1.23's SOS.INTERP, 25,963 bytes from its header to the end of the file.
    private const string InterpreterHash = "949D077761942CEDC4EBA053671ABBE8CD8D3C3A3520ED3E469D114F3ECCEC72";
    private const int InterpreterSize = 25963;

    // 1.23 loads at $5200, after the 14-byte header.
    private const int InterpreterOrigin = 0x51F2;

    // The 1.3 listing's build, unchecked against any binary: it pins the source's 1.3 paths.
    private const string ListingHash = "665DBAC677FCB0378350E305F9D6672106FD43780E507F9BAFD0969F90B1E752";
    private const int ListingSize = 14 + 0x6752;
    private const int ListingOrigin = 0x4FF2;

    /// <summary>
    ///  The source assembles without diagnostics to 1.23's SOS.INTERP.
    /// </summary>
    [TestMethod]
    public void InterpreterMatchesItsDigest()
    {
        byte[] bytes = Assemble("", InterpreterOrigin, InterpreterSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(InterpreterHash);
    }

    /// <summary>
    ///  With Apple's disk, the source compares byte for byte with 1.23's SOS.INTERP.
    /// </summary>
    [TestMethod]
    public void InterpreterMatchesTheDisk()
    {
        byte[] expected = SosVolumeTests.Volume("Apple3BusBasic1.23.dsk").ReadFile("SOS.INTERP");
        expected.Should().HaveCount(InterpreterSize);
        int first = Assemble("", InterpreterOrigin, InterpreterSize).AsSpan().CommonPrefixLength(expected);
        first.Should().Be(InterpreterSize, $"the first difference is at ${InterpreterOrigin + first:X4}");
    }

    /// <summary>
    ///  With <c>VERSION = 130</c>, the source assembles Apple's 1.3 listing as printed.
    /// </summary>
    [TestMethod]
    public void ListingMatchesItsDigest()
    {
        byte[] bytes = Assemble("VERSION = 130", ListingOrigin, ListingSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(ListingHash);
    }

    /// <summary>
    ///  The source passes the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void InterpreterDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath("BusinessBasic.asm"), _ => null);
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

    // Assembles the source with a definition ahead of it, as a build of another VERSION does.
    private static byte[] Assemble(string definition, int origin, int size)
    {
        string root = SourcePath("BusinessBasic.asm");
        string text = definition.Length != 0 ? $"{definition}\n.include \"BusinessBasic.asm\"\n" : File.ReadAllText(root);
        string path = definition.Length != 0 ? Path.Join(Path.GetDirectoryName(root), "_Build.asm") : root;
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(text, path),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin, size)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes[..size].ToArray();
    }

    // The test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath(string file)
    {
        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "BusinessBasic", file);
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive($"{file} is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Apple3", "Roms", "BusinessBasic", file));
    }
}
