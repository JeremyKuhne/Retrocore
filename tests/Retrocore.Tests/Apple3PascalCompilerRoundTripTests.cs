// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Apple III Pascal's Compilers, decompiled and built again with themselves on an emulated Apple III, to the same
///  segments.
/// </summary>
/// <remarks>
///  <para>
///   Apple III Pascal's disks are in <c>RETROCORE_APPLE3_DISKS</c>; 1.2's are built from 1.1's and the update's, as for
///   <see cref="Apple3PascalTests"/>. Each Compiler, decompiled, compiles with <c>(*$S++*)</c>, its source split in two
///   to fit its volumes. 1.1's and 1.2's call intrinsic units of the system's, in <c>SYSTEM.PASCAL</c>, whose code
///   keeps no interface: the decompiler declares them from their calls, as units compiled first for their interfaces.
///   Each takes a few minutes.
///  </para>
/// </remarks>
[TestClass]
public class Apple3PascalCompilerRoundTripTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Apple III Pascal's Compiler, decompiled, compiled with itself, has the same segments as Apple's.
    /// </summary>
    /// <param name="version">Apple III Pascal's version: 1.0, 1.1 or 1.2.</param>
    [TestMethod]
    [DataRow("1.0")]
    [DataRow("1.1")]
    [DataRow("1.2")]
    public void CompilerRebuildsItself(string version)
    {
        string folder = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        try
        {
            (string system, string tools) = Disks(version, folder);
            byte[] original = SosVolume.Read(DiskImageFile.Sectors(tools), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
            PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
            decompiled.Warnings.Should().BeEmpty();

            // The units the decompiler declared from their calls, compiled for their interfaces.
            Dictionary<string, byte[]> units = new(StringComparer.OrdinalIgnoreCase);
            foreach (PascalDecompiledUnit unit in decompiled.Units)
            {
                unit.Intrinsic.Should().BeTrue();
                (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(unit.Source, system, tools, s_inputs);
                if (code is null) { Assert.Fail($"The Compiler stopped on {unit.Name}:\n{screen}\n{unit.Source}"); }
                units[$"{unit.Name}.CODE"] = code;
            }

            (byte[]? compiled, string compiling) = EmulatedPascalCompiler.Compile($"(*$S++*)\n{decompiled.Source}", system, tools, s_inputs, units);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{compiling}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(compiled)).Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // A version's first and second disks: Apple's for 1.0 and 1.1, built for 1.2 into the folder.
    private static (string System, string Tools) Disks(string version, string folder)
    {
        if (version == "1.2")
        {
            foreach (string disk in (ReadOnlySpan<string>)["Apple3Pascal1.1Disk1.dsk", "Apple3Pascal1.2UpdateDisk1.dsk", "Apple3Pascal1.2UpdateDisk2.dsk"])
            {
                if (!File.Exists(Path.Join(SosVolumeTests.Disks, disk)))
                {
                    Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disk}.");
                }
            }

            (byte[] first, byte[] second) = Apple3PascalTests.Pascal12();
            string built1 = Path.Join(folder, "PASCAL1.dsk");
            string built2 = Path.Join(folder, "PASCAL2.dsk");
            File.WriteAllBytes(built1, first);
            File.WriteAllBytes(built2, second);
            return (built1, built2);
        }

        string system = Path.Join(SosVolumeTests.Disks, version == "1.0" ? "Apple3Pascal1.0Disk1BadFiler.dsk" : $"Apple3Pascal{version}Disk1.dsk");
        string tools = Path.Join(SosVolumeTests.Disks, $"Apple3Pascal{version}Disk2.dsk");
        if (!File.Exists(system) || !File.Exists(tools))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with Apple III Pascal {version}'s disks.");
        }

        return (system, tools);
    }
}
