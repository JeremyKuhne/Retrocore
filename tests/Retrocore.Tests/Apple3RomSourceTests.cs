// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for the Apple III boot ROM, <c>BootRom.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no ROM is needed. With the dump (MAME's <c>apple3</c> set in
///   <c>RETROCORE_APPLE3_ROMS</c> or <c>%USERPROFILE%\Retrocore\apple3-roms\mame\apple3</c>), the build also compares
///   byte for byte, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class Apple3RomSourceTests
{
    // The SHA-256 of the 4K boot ROM, apple3.rom (SHA-1 8043f914ebdcdab9838dbb78f8a2ee3867d210d2).
    private const string BootRomHash = "370BE5F0C1B57B606D6C7312F99E5F6064BF405B22430AB53D9BEC9BCC0F7520";

    private const int BootRomOrigin = 0xF000;
    private const int BootRomSize = 0x1000;

    /// <summary>
    ///  The source assembles without diagnostics to the boot ROM's 4K.
    /// </summary>
    [TestMethod]
    public void BootRomMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(BootRomSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(BootRomHash);
    }

    /// <summary>
    ///  With the dump, the source compares byte for byte.
    /// </summary>
    [TestMethod]
    public void BootRomMatchesTheDump()
    {
        string path = Path.Join(Apple3MachineTests.RomDirectory, Apple3Roms.BootRomFile);
        if (!File.Exists(path)) { Assert.Inconclusive($"The Apple III boot ROM ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        expected.Should().HaveCount(BootRomSize);
        ReadOnlySpan<byte> actual = Assemble().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(BootRomSize, $"the first difference is at ${BootRomOrigin + first:X4}");
    }

    /// <summary>
    ///  The source and its equates pass the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void BootRomDocumentationIsClean()
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
    ///  Assembles the boot ROM from the SDK's source.
    /// </summary>
    /// <returns>The assembly, its one section the ROM's 4K.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, BootRomOrigin, BootRomSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // The test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath()
    {
        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "BootRom.asm");
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("BootRom.asm is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Apple3", "Roms", "BootRom.asm"));
    }
}
