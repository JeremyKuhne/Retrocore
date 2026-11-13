// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's SOS sources: the SOS 1.3 kernel, <c>Sos/SosKernel.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no disk is needed. With Apple's Business BASIC 1.23 disk (in
///   <c>RETROCORE_APPLE3_DISKS</c> or <c>%USERPROFILE%\Retrocore\apple3-disks</c>), the build also compares byte for
///   byte with its <c>SOS.KERNEL</c>, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class SosSourceTests
{
    // The SHA-256 of SOS 1.3's SOS.KERNEL, the same file on the Business BASIC 1.23 and System Utilities disks.
    private const string KernelHash = "6A8593274AF167B2BFD48CE556C907F5E30C0749EB1221BEE0970B3E19CB2F2D";

    // The file loads at $1E00, and the source places it at $2000, where Apple's build did.
    private const int KernelOrigin = 0x2000;
    private const int KernelSize = 22016;

    /// <summary>
    ///  The kernel assembles without diagnostics to SOS.KERNEL's 22,016 bytes.
    /// </summary>
    [TestMethod]
    public void KernelMatchesItsDigest()
    {
        AssemblyResult result = AssembleKernel();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        bytes.Length.Should().Be(KernelSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(KernelHash);
    }

    /// <summary>
    ///  With Apple's disk, the kernel compares byte for byte with its SOS.KERNEL.
    /// </summary>
    [TestMethod]
    public void KernelMatchesTheDisk()
    {
        byte[] expected = SosVolumeTests.Volume("Apple3BusBasic1.23.dsk").ReadFile("SOS.KERNEL");
        expected.Should().HaveCount(KernelSize);
        ReadOnlySpan<byte> actual = AssembleKernel().Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(KernelSize, $"the first difference is at file offset ${first:X4}");
    }

    /// <summary>
    ///  The kernel's sources pass the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void KernelDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath("SosKernel.asm"), _ => null);
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
    ///  The bootstrap loader assembles to block 0 of the SOS disks: Apple's loader 1.1, the System Demo's copy of it
    ///  with <c>SYSTEM_DEMO = 1</c>, and On Three's 2.2 from the SOS 1.3 System Utilities with <c>ON_THREE = 1</c>.
    /// </summary>
    /// <param name="symbol">The build's symbol, or empty for Apple's loader.</param>
    /// <param name="hash">The SHA-256 of the block.</param>
    [TestMethod]
    [DataRow("", "A35DD52286214F981D9D819C01B3D4CCC30B54E4A2DF5B750F96F05828BF889C")]
    [DataRow("SYSTEM_DEMO", "D6A567FAB3A130FF9E947A599DFA0903DEBFB6CBA6C75AFBA0DC99A8F442D19A")]
    [DataRow("ON_THREE", "4D75BF504EA31A510E9D41F374BFD5FB0FA5F0A3644AD0BAE87E3473ABAF51C1")]
    public void BootLoaderMatchesItsDigest(string symbol, string hash) =>
        Convert.ToHexString(SHA256.HashData(AssembleBoot(symbol))).Should().Be(hash);

    /// <summary>
    ///  With the disks, each bootstrap loader build compares byte for byte with its block 0.
    /// </summary>
    /// <param name="symbol">The build's symbol, or empty for Apple's loader.</param>
    /// <param name="disk">The disk.</param>
    [TestMethod]
    [DataRow("", "Apple3BusBasic1.23.dsk")]
    [DataRow("SYSTEM_DEMO", "Apple3SystemDemoUnProtected.dsk")]
    [DataRow("ON_THREE", "Apple3SOS1.3SysUtils.dsk")]
    public void BootLoaderMatchesTheDisk(string symbol, string disk)
    {
        byte[] expected = SosVolumeTests.Volume(disk).Block(0);
        int first = AssembleBoot(symbol).AsSpan().CommonPrefixLength(expected);
        first.Should().Be(BootSize, $"the first difference is at ${BootOrigin + first:X4}");
    }

    /// <summary>
    ///  The bootstrap loader's source passes the documentation lint as the editor runs it, its hardware names'
    ///  links reaching the boot ROM's routines.
    /// </summary>
    [TestMethod]
    public void BootLoaderDocumentationIsClean()
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(SourcePath("SosBoot.asm"), _ => null);
        string bootRom = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(SourcePath("SosBoot.asm"))), "BootRom.asm");
        DocumentationResolver resolver = new(
            analysis.Documentation,
            [SourceAnalysis.Assemble(bootRom, _ => null).Documentation],
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Check()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    private const int BootOrigin = 0xA000;
    private const int BootSize = 512;

    // Block 0, at $A000 where the boot ROM reads it.
    private static byte[] AssembleBoot(string symbol)
    {
        string root = SourcePath("SosBoot.asm");
        string text = symbol.Length != 0 ? $"{symbol} = 1\n.include \"SosBoot.asm\"\n" : File.ReadAllText(root);
        string path = symbol.Length != 0 ? Path.Join(Path.GetDirectoryName(root), $"_{symbol}.asm") : root;
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(text, path),
            new AssemblyOptions(ProcessorVariant.Mos6502, BootOrigin, BootSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes.ToArray();
    }

    private static AssemblyResult AssembleKernel()
    {
        string path = SourcePath("SosKernel.asm");
        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, KernelOrigin, KernelSize)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });
    }

    // The test inputs' copy when the project links one, otherwise the repository's.
    private static string SourcePath(string file)
    {
        string input = Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "Sos", file);
        if (File.Exists(input)) { return Path.GetFullPath(input); }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null) { Assert.Inconclusive($"{file} is not in the test inputs or the repository."); }

        return Path.GetFullPath(Path.Join(root, "src", "Retrocore.Machines.Apple3", "Roms", "Sos", file));
    }
}
