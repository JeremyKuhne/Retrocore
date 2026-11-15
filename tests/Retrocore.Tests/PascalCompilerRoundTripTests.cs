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
///  <para>
///   Apple Pascal 1.0's Compiler, from <c>UCSD Pascal 1.0_2.DSK</c>, compiles with itself on Apple III Pascal 1.1,
///   whose system disk, <c>Apple3Pascal1.1Disk1.dsk</c>, is in <c>RETROCORE_APPLE3_DISKS</c>.
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

    /// <summary>
    ///  Apple Pascal 1.0's Compiler, decompiled and compiled with itself on Apple III Pascal 1.1, has the same segments
    ///  as Apple's.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   On a 64K Apple II the decompiled source runs out of memory in COMPINIT, and 1.0 has no 128K system: the Apple
    ///   III has the room. The Compiler goes on a tools volume of its own, /PASCAL2, its segments marked version 4, as
    ///   Apple III Pascal runs only its own code; the code it writes is its own, version 1. It takes about two
    ///   minutes.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void ApplePascal10CompilerRebuildsItself()
    {
        string apple2 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.0_2.DSK");
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        if (!File.Exists(apple2) || !File.Exists(system))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS and RETROCORE_APPLE3_DISKS to folders with Apple Pascal 1.0's and Apple III Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        decompiled.Warnings.Should().BeEmpty();

        string tools = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-PASCAL2.dsk");
        try
        {
            SosVolumeBuilder builder = new("PASCAL2");
            builder.Add("SYSTEM.COMPILER", fileType: 0x02, auxType: 0, AsVersion4(original));
            File.WriteAllBytes(tools, builder.Build(proDosOrder: false));

            string source = $"(*$S++*)\n{decompiled.Source}";
            (byte[]? compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, system, tools, listing: null, s_inputs);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(compiled)).Should().BeEmpty();
        }
        finally
        {
            File.Delete(tools);
        }
    }

    // A code file with each segment's version, bits 13 to 15 of its information word, 4, Apple III Pascal's.
    private static byte[] AsVersion4(byte[] code)
    {
        byte[] marked = (byte[])code.Clone();
        for (int slot = 0; slot < 16; slot++)
        {
            int at = 256 + (slot * 2);
            int information = marked[at] | (marked[at + 1] << 8);
            if (information == 0) { continue; }

            information = (information & 0x1FFF) | (4 << 13);
            marked[at] = (byte)information;
            marked[at + 1] = (byte)(information >> 8);
        }

        return marked;
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
