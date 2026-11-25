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
///  Verifies the SDK's native source for Atari BASIC, <c>AtariBasic.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins each build, so no ROM is needed. With the cartridges (<c>basic-reva.rom</c> to
///   <c>basic-revc.rom</c> in <c>%USERPROFILE%\Retrocore\atari8-media\basic</c>), each build also compares byte for
///   byte, which names the first difference. <c>RETROCORE_ATARI_BASIC_SOURCE</c> points the tests at another copy of
///   the source.
///  </para>
/// </remarks>
[TestClass]
public sealed class AtariBasicSourceTests
{
    private const int Origin = 0xA000;
    private const int Size = 0x2000;

    private const int VersionA = 1;
    private const int VersionB = 2;
    private const int VersionC = 3;

    /// <summary>
    ///  Each build assembles without diagnostics to its 8K, whose SHA-256 is its cartridge's.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="hash">The cartridge's SHA-256.</param>
    [TestMethod]
    [DataRow(VersionC, "4988CB41121921F997AB17A59DD1909FECE9273699EBA0C6FBAAFAE104AA27B0")]
    [DataRow(VersionB, "43DE6502B77D3E7058FCE6F4ED261CAFBEC37926B797BB1AE24470D39C998EA9")]
    [DataRow(VersionA, "0ACE07D4ED099D700D63B3220A7F6BCFC5E2627975B2B0BB3157796BB12852DA")]
    public void BuildMatchesItsDigest(int version, string hash)
    {
        AssemblyResult result = Assemble(version);
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(Size);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(hash);
    }

    /// <summary>
    ///  With the cartridges, each build compares byte for byte.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    /// <param name="revision">The cartridge's revision letter.</param>
    [TestMethod]
    [DataRow(VersionC, 'c')]
    [DataRow(VersionB, 'b')]
    [DataRow(VersionA, 'a')]
    public void BuildMatchesTheCartridge(int version, char revision)
    {
        string path = Path.Join(AtariMachineTests.BasicDirectory, $"basic-rev{revision}.rom");
        if (!File.Exists(path)) { Assert.Inconclusive($"Atari BASIC isn't at {path}."); }

        ReadOnlySpan<byte> actual = Assemble(version).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(File.ReadAllBytes(path));
        first.Should().Be(Size, $"the first difference is at ${Origin + first:X4}");
    }

    /// <summary>
    ///  An 800 runs a program in the SDK's BASIC on the SDK's OS and floating point package, with no dumps.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    [TestMethod]
    [DataRow(VersionC)]
    [DataRow(VersionA)]
    public void ProgramRunsOnTheSources(int version)
    {
        byte[] image =
        [
            .. AtariFloatingPointSourceTests.Assemble().Sections[0].Bytes.Span,
            .. AtariOsSourceTests.Assemble().Sections[0].Bytes.Span
        ];

        AtariMachine machine = new(
            new AtariRoms(image),
            left: new AtariCartridge(Assemble(version).Sections[0].Bytes.Span));

        AtariMachineTests.RunToReady(machine);
        AtariMachineTests.Type(machine, "10 FOR I=1 TO 3:PRINT I*7;\"X\":NEXT I\r");
        AtariMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "7X");
        screen.Should().Contain(line => line.Trim() == "21X");
    }

    /// <summary>
    ///  Each build of the source, its parts and its equates passes the documentation lint as the editor runs it, with
    ///  the OS's and the floating point package's sources for the names it inherits.
    /// </summary>
    /// <param name="version">The build's <c>VERSION</c>.</param>
    [TestMethod]
    [DataRow(VersionC)]
    [DataRow(VersionB)]
    [DataRow(VersionA)]
    public void DocumentationIsClean(int version)
    {
        string path = SourcePath();
        string root = path;
        DirectoryInfo? temporary = null;
        if (version != VersionC)
        {
            // The lint reads a build's VERSION from the source, so a wrapper sets it.
            temporary = Directory.CreateTempSubdirectory();
            root = Path.Join(temporary.FullName, "AtariBasic.asm");
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

        string roms = Path.GetDirectoryName(path) ?? ".";
        SourceAnalysis os = SourceAnalysis.Assemble(Path.Join(roms, "Os.asm"), _ => null);
        SourceAnalysis floatingPoint = SourceAnalysis.Assemble(Path.Join(roms, "FloatingPoint.asm"), _ => null);

        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules([os, floatingPoint]).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Check()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Assembles Atari BASIC from the SDK's source.
    /// </summary>
    /// <param name="version">
    ///  The build's <c>VERSION</c>: 1 for rev. A, 2 for rev. B, 3 for rev. C (the default).
    /// </param>
    /// <returns>The assembly, its one section the cartridge's 8K.</returns>
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

    // RETROCORE_ATARI_BASIC_SOURCE, otherwise the repository's.
    private static string SourcePath()
    {
        string? overridden = Environment.GetEnvironmentVariable("RETROCORE_ATARI_BASIC_SOURCE");
        if (!string.IsNullOrEmpty(overridden)) { return Path.GetFullPath(overridden); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive("AtariBasic.asm is not in the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Atari", "Roms", "AtariBasic.asm"));
    }
}
