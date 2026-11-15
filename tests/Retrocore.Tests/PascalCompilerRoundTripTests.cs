// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  An Apple Pascal Compiler decompiled and built again with itself, on the machine it runs on, to the same segments.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal 1.3's disks are WOZ images in <c>RETROCORE_APPLE2_PASCAL_DISKS</c> (<c>UCSD Pascal 1.3_APPLE1.woz</c>
///   to <c>APPLE3.woz</c>). Its Compiler, decompiled, compiles with <c>(*$S++*)</c> on a 128K IIe booted from APPLE1
///   with APPLE3's 128K system in place of the 64K one: the Apple II's 64K runs out in COMPINIT. Its two assembled
///   procedures, in PASCALCO, are assembled from their decompiled source and linked in. It takes about three minutes.
///  </para>
/// </remarks>
[TestClass]
public class PascalCompilerRoundTripTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Apple Pascal 1.3's Compiler, decompiled, compiled with itself, its assembled procedures assembled and linked,
    ///  has the same segments as Apple's.
    /// </summary>
    [TestMethod]
    public void ApplePascal13CompilerRebuildsItself()
    {
        string apple1 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.3_APPLE1.woz");
        string apple2 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.3_APPLE2.woz");
        string apple3 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.3_APPLE3.woz");
        if (!File.Exists(apple1) || !File.Exists(apple2) || !File.Exists(apple3))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.3's WOZ images.");
        }

        byte[] original = PascalVolume.Read(Sectors(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        string assembly = decompiled.Assembly ?? throw new AssertFailedException("PASCALCO has two assembled procedures.");

        string boot = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-APPLE1-128K.dsk");
        try
        {
            File.WriteAllBytes(boot, Boot128K(apple1, apple3));
            string source = $"(*$S++*)\n{decompiled.Source}";
            (byte[]? compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, boot, apple2, listing: null, s_inputs, files: null, Apple2Model.IIeEnhanced);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, apple1, apple2, s_inputs);
            if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}"); }

            (byte[]? linked, string linking) = EmulatedPascalTools.Link(compiled, [assembled], apple1, apple2, s_inputs);
            if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(linked)).Should().BeEmpty();
        }
        finally
        {
            File.Delete(boot);
        }
    }

    // APPLE1 with APPLE3's 128K system as its own, and without the Editor, which a compile does not need.
    private static byte[] Boot128K(string apple1, string apple3)
    {
        byte[] boot = Sectors(apple1);
        PascalVolume extras = PascalVolume.Read(Sectors(apple3), proDosOrder: false);
        foreach ((string from, string to, PascalFileKind kind) in (ReadOnlySpan<(string, string, PascalFileKind)>)
            [("128K.APPLE", "SYSTEM.APPLE", PascalFileKind.Data), ("128K.PASCAL", "SYSTEM.PASCAL", PascalFileKind.Code)])
        {
            PascalVolume.DeleteFile(boot, proDosOrder: false, to);
            PascalVolume.WriteFile(boot, proDosOrder: false, to, kind, extras.ReadFile(from));
        }

        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR");
        return boot;
    }

    private static byte[] Sectors(string path) => SectorDiskReader.Read(WozDisk.Load(File.ReadAllBytes(path)), proDosOrder: false);
}
