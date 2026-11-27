// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;
using Retrocore.Pascal.Source;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's Pascal source for Apple Pascal 1.3's Compiler, <c>Pascal/Compiler/apple2-1.3</c>, with the
///  system's globals it includes from <c>Pascal/System/apple2-1.3</c>.
/// </summary>
/// <remarks>
///  <para>
///   Without disks, its code's shape is pinned (<see cref="PascalCodeShape"/>): names and comments can change, the code
///   can't. With Apple Pascal 1.3's disks (<c>UCSD Pascal 1.3_1.DSK</c> to <c>_3.DSK</c>, or the WOZ images, in
///   <c>RETROCORE_APPLE2_PASCAL_DISKS</c>), it is compiled with APPLE2's Compiler, its assembled procedures assembled
///   and linked, and the result has the same segments as APPLE2's <c>SYSTEM.COMPILER</c>; that takes about two
///   minutes.
///  </para>
/// </remarks>
[TestClass]
public sealed class PascalCompilerSourceTests
{
    // The shape of SYSTEM.COMPILER's decompiled source, which this one keeps.
    private const string Shape = "8DA3303C3A1F2AFC2155010AEB1834C090318E729ED9A205E5FC26D2EDE0482A";

    // The SHA-256 of SYSTEM.COMPILER on Apple Pascal 1.3's APPLE2.
    private const string CompilerHash = "D18595C2EA04F9B5CDD84C7EEBF3DC871FE8D850173CF86DE8339BEF2E7F0E51";

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The source's code has the shape of SYSTEM.COMPILER's decompiled source.
    /// </summary>
    [TestMethod]
    public void CompilerKeepsItsCode()
    {
        PascalProgram program = Analyze();
        program.Includes.Select(include => include.Path).Should().NotContainNulls();
        PascalCodeShape.Digest(program).Should().Be(Shape);
    }

    /// <summary>
    ///  With Apple Pascal 1.3's disks, the source compiles, assembles and links to the same segments as APPLE2's
    ///  SYSTEM.COMPILER.
    /// </summary>
    [TestMethod]
    public void CompilerRebuildsSystemCompiler()
    {
        string apple1 = PascalMediaTests.Apple2Pascal13Disk(1);
        string apple2 = PascalMediaTests.Apple2Pascal13Disk(2);
        string apple3 = PascalMediaTests.Apple2Pascal13Disk(3);
        if (!File.Exists(apple1) || !File.Exists(apple2) || !File.Exists(apple3))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.3's disks.");
        }

        byte[] original = PascalVolume.Read(PascalCompilerRoundTripTests.Sectors(apple2), proDosOrder: false)
            .ReadFile("SYSTEM.COMPILER");

        Convert.ToHexString(SHA256.HashData(original)).Should().Be(CompilerHash);

        (string compiler, string system) = Folders();
        Dictionary<string, string> included = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (string file in Directory.EnumerateFiles(compiler, "*.TEXT").Concat(Directory.EnumerateFiles(system, "*.TEXT")))
        {
            string name = Path.GetFileName(file);
            if (name is not ("COMPILER.TEXT" or "ASSEMBLED.TEXT")) { included[name] = File.ReadAllText(file); }
        }

        string boot = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-APPLE1-128K.dsk");
        try
        {
            File.WriteAllBytes(boot, PascalCompilerRoundTripTests.Boot128K(apple1, apple3));
            (byte[]? compiled, string screen) = EmulatedPascalCompiler.CompileFiles(
                File.ReadAllText(Path.Join(compiler, "COMPILER.TEXT")),
                included,
                boot,
                apple2,
                s_inputs,
                Apple2Model.IIeEnhanced);

            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            string assembly = File.ReadAllText(Path.Join(compiler, "ASSEMBLED.TEXT"));
            (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, apple1, apple2, s_inputs, Apple2Model.IIeEnhanced);
            if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}"); }

            (byte[]? linked, string linking) = EmulatedPascalTools.Link(compiled, [assembled], apple1, apple2, s_inputs, Apple2Model.IIeEnhanced);
            if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(linked)).Should().BeEmpty();
        }
        finally
        {
            File.Delete(boot);
        }
    }

    private static PascalProgram Analyze()
    {
        (string compiler, _) = Folders();
        string main = Path.Join(compiler, "COMPILER.TEXT");
        return PascalProgram.Analyze(
            main,
            path => File.Exists(path) ? File.ReadAllText(path) : null,
            PascalIncludeFolders.For(main));
    }

    // The source's folders in the repository.
    private static (string Compiler, string System) Folders()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !Directory.Exists(Path.Join(root, "src", "Retrocore.Pascal", "Sdk")))
        {
            root = Path.GetDirectoryName(root);
        }

        string sdk = Path.Join(root ?? throw new AssertFailedException("src/Retrocore.Pascal/Sdk is not above the test's folder."), "src", "Retrocore.Pascal", "Sdk");
        return (Path.Join(sdk, "Compiler", "apple2-1.3"), Path.Join(sdk, "System", "apple2-1.3"));
    }
}
