// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Decompiling what Apple III Pascal's Compiler writes that Apple Pascal's does not: files of its own size, and calls
///  of intrinsic units no library at hand declares.
/// </summary>
/// <remarks>
///  <para>
///   Each probe is compiled by Apple III Pascal 1.1's Compiler on an emulated Apple III, decompiled, compiled again,
///   and compared with the first compile. They need Apple III Pascal's disks (<c>RETROCORE_APPLE3_DISKS</c>).
///  </para>
/// </remarks>
[TestClass]
public class Apple3PascalDecompilerTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // An untyped file and then a text file: Apple III Pascal's untyped file has all its 550 words, and its window's
    // address, past them, is the text file's.
    private const string FilesSource = """
        PROGRAM FS;
        VAR A: FILE; L: TEXT; N: INTEGER;
        BEGIN
          REWRITE(L, 'X.TEXT'); WRITELN(L, 'A');
          RESET(A, 'Y'); N := BLOCKREAD(A, L, 1, 0)
        END.
        """;

    /// <summary>
    ///  Files are as long as their FINIT shows, Apple III Pascal's longer than Apple Pascal's, and an untyped file whose
    ///  window is the next file's address leaves that file one.
    /// </summary>
    [TestMethod]
    public void FilesTakeTheirWordsFromTheirWindows()
    {
        string source = RoundTrip(FilesSource);
        source.Should().Contain("G3: FILE;").And.Contain("G553: TEXT;");
    }

    // A CASE with OTHERWISE, whose statement follows the jump table.
    private const string OtherwiseSource = """
        PROGRAM OW;
        VAR I, J: INTEGER;
        BEGIN
          CASE I OF
            1, 2: J := I + 20;
            3: J := 24;
            OTHERWISE J := I + 28
          END;
          IF J = 0 THEN I := 5
        END.
        """;

    /// <summary>
    ///  A CASE whose XJP goes for other values to the statement after its table, which its arms jump past, has
    ///  Apple III Pascal's OTHERWISE.
    /// </summary>
    [TestMethod]
    public void CasesWithOtherwiseDecompile()
    {
        string source = RoundTrip(OtherwiseSource);
        source.Should().Contain("    OTHERWISE\n      G3 := G4 + 28\n  END;");
    }

    // Compiles a probe, decompiles it, and checks the decompiled source compiles to the same segments.
    private static string RoundTrip(string probe)
    {
        (string system, string tools) = Disks();
        (byte[]? original, string compiled) = EmulatedPascalCompiler.Compile(probe, system, tools, s_inputs);
        if (original is null) { Assert.Fail($"The Compiler stopped:\n{compiled}"); }

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        result.Warnings.Should().BeEmpty(result.Source);

        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, system, tools, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(code)).Should().BeEmpty(result.Source);
        return result.Source;
    }

    private static (string System, string Tools) Disks()
    {
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        string tools = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk2.dsk");
        if (!File.Exists(system) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE3_DISKS to a folder with Apple III Pascal 1.1's disks.");
        }

        return (system, tools);
    }
}
