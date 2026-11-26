// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Media;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native source for Apple Pascal 1.1's interpreter, <c>Pascal/Interpreter/1.1/SYSTEM.APPLE.asm</c>.
/// </summary>
/// <remarks>
///  <para>
///   A digest pins the build, so no disk is needed. With Apple Pascal 1.1's APPLE1 and APPLE3 (<c>UCSD Pascal
///   1.1_1.dsk</c> and <c>1.1_3.dsk</c> in <c>RETROCORE_APPLE2_PASCAL_DISKS</c>), the build also compares byte for byte
///   with their <c>SYSTEM.APPLE</c>, which names the first difference.
///  </para>
/// </remarks>
[TestClass]
public sealed class PascalInterpreterSourceTests
{
    // The SHA-256 of SYSTEM.APPLE on Apple Pascal 1.1's APPLE1 and APPLE3 (SHA-1 b87851c389c5325da55cfbea5f16401c4e881832).
    private const string InterpreterHash = "2443C23E7538EBFC0227525E4A80878DFAE0B96A8A445CB1C4B4332F433A8AE6";

    private const int InterpreterSize = 0x4000;

    /// <summary>
    ///  The source assembles without diagnostics to SYSTEM.APPLE's 16K.
    /// </summary>
    [TestMethod]
    public void InterpreterMatchesItsDigest()
    {
        AssemblyResult result = Assemble();
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = SourceBuild.OutputBytes(result).Span;
        bytes.Length.Should().Be(InterpreterSize);
        Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(InterpreterHash);
    }

    /// <summary>
    ///  With Apple Pascal 1.1's disks, the source compares byte for byte with SYSTEM.APPLE on APPLE1 and on APPLE3,
    ///  which hold the same file.
    /// </summary>
    /// <param name="volume">The disk's number: 1 for APPLE1, 3 for APPLE3.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(3)]
    public void InterpreterMatchesTheDisk(int volume)
    {
        string disk = Path.Join(PascalMediaTests.Apple2Disks, $"UCSD Pascal 1.1_{volume}.dsk");
        if (!File.Exists(disk))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with {Path.GetFileName(disk)}.");
        }

        byte[] expected = PascalVolume.Read(DiskImageFile.Sectors(disk), proDosOrder: false).ReadFile("SYSTEM.APPLE");
        expected.Should().HaveCount(InterpreterSize);
        ReadOnlySpan<byte> actual = SourceBuild.OutputBytes(Assemble()).Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(InterpreterSize, $"the first difference is at file offset ${first:X4}");
    }

    /// <summary>
    ///  The source passes the documentation lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void InterpreterDocumentationIsClean()
    {
        // Its links reach the IIe's SDK modules, as the editor's do: IIeEquates.asm names the Monitor's routines.
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs");
        List<SourceAnalysis> sdk = [.. SdkDocumentationTests.SdkRoots(roms).Select(Analyze)];
        SourceAnalysis analysis = Analyze(SourcePath());
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules(sdk).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Lint()
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}")
            .Order()];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Assembles SYSTEM.APPLE from the SDK's source, with its linker configuration.
    /// </summary>
    /// <returns>The assembly: bank 2, $E000-$FFFF and bank 1, in the file's order.</returns>
    internal static AssemblyResult Assemble()
    {
        string path = SourcePath();
        return SourceBuild.Assemble(
            path,
            AssemblyDialect.Native,
            "Mos6502",
            origin: 0xD000,
            Path.Join(Path.GetDirectoryName(path), "SYSTEM.APPLE.cfg"));
    }

    private static SourceAnalysis Analyze(string path) => SourceAnalysis.Assemble(path, _ => null);

    // The SDK's copy beside the tests.
    private static string SourcePath() =>
        Path.GetFullPath(Path.Join(SdkModules.SdkDirectory, "Pascal", "Interpreter", "1.1", "SYSTEM.APPLE.asm"));
}
