// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Wizardry (Proving Grounds of the Mad Overlord, v2.1, Sir-Tech), written in Apple Pascal 1.1, decompiled and built
///  again with Apple Pascal 1.1's own Compiler, Assembler and Linker to the same segments; and probes, built by the 1.1
///  Compiler, of what its code showed the decompiler.
/// </summary>
/// <remarks>
///  <para>
///   Wizardry's boot disk is a WOZ image in <c>RETROCORE_WIZARDRY_DISKS</c> (<c>Wizardry1 v2.1 - boot.woz</c>), with
///   two code files: SYSTEM.STARTUP, which uses CHAINSTUFF from the disk's SYSTEM.LIBRARY, and WIZARDRY.CODE. Each has
///   assembled procedures, which are assembled from their decompiled source and linked in. WIZARDRY.CODE's source
///   has more declarations than the 1.1 Compiler holds in 64K, so the 1.1 Compiler, its segments marked version 5,
///   compiles it under Apple Pascal 1.2's 128K system on a 128K IIe (1.2's disks, in
///   <c>RETROCORE_APPLE2_PASCAL_DISKS</c>, with 1.2_3's <c>128K.APPLE</c> and <c>128K.PASCAL</c> as 1.2_1's system),
///   its source split with an include file across two volumes. It takes about seven minutes.
///  </para>
/// </remarks>
[TestClass]
public class PascalWizardryTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Gets the folder of Wizardry's disk images.
    /// </summary>
    internal static string Disks => Environment.GetEnvironmentVariable("RETROCORE_WIZARDRY_DISKS")
        ?? Path.Join(ExternalTestData.Root, "wizardry-disks");

    /// <summary>
    ///  SYSTEM.STARTUP, decompiled with the disk's library, compiled with Apple Pascal 1.1's Compiler on an Apple II,
    ///  its assembled procedures assembled and linked with 1.1's Assembler and Linker, has the same segments.
    /// </summary>
    [TestMethod]
    public void StartupRebuildsToTheSameSegments()
    {
        (PascalVolume volume, string boot, string tools) = Volumes();
        byte[] original = volume.ReadFile("SYSTEM.STARTUP");
        PascalLibrary library = PascalLibrary.Read(volume.ReadFile("SYSTEM.LIBRARY"));
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original), library);
        decompiled.Warnings.Where(warning => !warning.Contains("assembled code", StringComparison.Ordinal) && !warning.Contains("never called", StringComparison.Ordinal))
            .Should().BeEmpty();

        // 64K holds its declarations with the Compiler's segments swapped.
        (byte[]? compiled, string screen) = EmulatedPascalCompiler.Compile($"(*$S+*)\n{decompiled.Source}", boot, tools, s_inputs);
        if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

        LinkAndCompare(original, compiled, decompiled, boot, tools);
    }

    /// <summary>
    ///  WIZARDRY.CODE, decompiled, compiled with Apple Pascal 1.1's Compiler under Apple Pascal 1.2's 128K system, its
    ///  assembled procedures assembled and linked with 1.1's Assembler and Linker, has the same segments.
    /// </summary>
    [TestMethod]
    public void WizardryRebuildsToTheSameSegments()
    {
        (PascalVolume volume, string boot, string tools) = Volumes();
        string[] apple12 = [.. Enumerable.Range(1, 3).Select(disk => Path.Join(PascalMediaTests.Apple2Disks, $"UCSD Pascal 1.2_{disk}.DSK"))];
        if (apple12.Any(disk => !File.Exists(disk)))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.2's disks too.");
        }

        byte[] original = volume.ReadFile("WIZARDRY.CODE");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        decompiled.Warnings.Where(warning => !warning.Contains("assembled code", StringComparison.Ordinal)).Should().BeEmpty();

        string name = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}");
        string boot128 = $"{name}-APPLE1-128K.dsk";
        string compiler11 = $"{name}-APPLE2-1.1.dsk";
        try
        {
            File.WriteAllBytes(boot128, Boot128K(apple12[0], apple12[2]));
            File.WriteAllBytes(compiler11, Compiler11(apple12[1], tools));
            string source = $"(*$S++*)\n{decompiled.Source}";
            (byte[]? compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, boot128, compiler11, listing: null, s_inputs, files: null, Apple2Model.IIeEnhanced);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            LinkAndCompare(original, compiled, decompiled, boot, tools);
        }
        finally
        {
            File.Delete(boot128);
            File.Delete(compiler11);
        }
    }

    // The probes, each compiled by the 1.1 Compiler, decompiled and compiled again.

    // A directory's entries, a packed record with a string after its bits.
    private const string DirectorySource = """
        PROGRAM P;
        TYPE E = PACKED RECORD A, B: INTEGER; K: 0..15; X: 0..4095; S: STRING[15]; L: INTEGER END;
        VAR D: ARRAY[0..3] OF E; I: INTEGER;
        FUNCTION F(U: INTEGER; N: STRING): INTEGER;
        BEGIN F := 0; IF (D[I].K >= 1) AND (D[I].K <= 7) THEN IF D[I].S = N THEN F := D[I].A END;
        BEGIN I := F(4, 'AB') END.
        """;

    /// <summary>
    ///  A packed record's field of more than a word, a string, is declared whole.
    /// </summary>
    [TestMethod]
    public void PackedRecordsHoldStrings()
    {
        PascalSystemDecompilerTests.RoundTrip(DirectorySource).Should().Contain("X2B4: 0..4095; F3: STRING[16] END;");
    }

    /// <summary>
    ///  A hint names a packed record's string where it is declared, as where the code uses it.
    /// </summary>
    [TestMethod]
    public void HintsNamePackedRecordsStrings()
    {
        PascalDecompilerOptions options = new()
        {
            Names = new Dictionary<string, string> { ["T2"] = "ENTRY", ["T2.F3"] = "TITLE", ["T2.F2B0"] = "KIND" }
        };

        string source = PascalSystemDecompilerTests.RoundTrip(DirectorySource, options, out IReadOnlyList<string> warnings);
        warnings.Should().BeEmpty(source);
        source.Should().Contain("ENTRY = PACKED RECORD F0: INTEGER; F1: INTEGER; KIND: 0..15; X2B4: 0..4095; TITLE: STRING[16] END;");
        source.Should().Contain("IF G3[G51].TITLE = A3 THEN");
    }

    // A level's squares' kinds, an array of packed arrays of bits.
    private const string SquaresSource = """
        PROGRAM P;
        TYPE K = PACKED ARRAY[0..15] OF 0..15;
        VAR M: ARRAY[0..1] OF K; I: INTEGER;
        BEGIN
          CASE M[1, I] OF 1: I := 2; 5: I := 3 END;
          IF M[0, I] = 5 THEN M[1, I] := 1
        END.
        """;

    /// <summary>
    ///  Hints name the values of an array's elements, by the array's key, an array of arrays' too; the elements'
    ///  bounds, which only one name is given for, stay numbers.
    /// </summary>
    [TestMethod]
    public void HintsNameArraysElementsValues()
    {
        PascalDecompilerOptions options = new()
        {
            Constants = new Dictionary<string, IReadOnlyList<string>>
            {
                ["SQUARE"] = ["NORMAL", "STAIRS", "", "", "", "DARK"]
            },
            Values = new Dictionary<string, string> { ["T1"] = "SQUARE" }
        };

        string source = PascalSystemDecompilerTests.RoundTrip(SquaresSource, options, out IReadOnlyList<string> warnings);
        warnings.Should().BeEmpty(source);
        source.Should().Contain("  NORMAL = 0; STAIRS = 1; DARK = 5;\n").And.Contain("T2 = PACKED ARRAY[0..15] OF 0..15;");
        source.Should().Contain("    STAIRS:\n").And.Contain("    DARK:\n").And.Contain("IF G3[0, G11] = DARK THEN\n    G3[1, G11] := STAIRS");
    }

    // A word of a record read only to compare as equal or not, before words the code never names.
    private const string ComparedSource = """
        (*$V-*)
        PROGRAM P;
        VAR B: PACKED ARRAY[0..1023] OF CHAR; I: INTEGER;
        PROCEDURE R(VAR S: STRING; K: INTEGER);
        BEGIN MOVELEFT(B[K], S, 208) END;
        PROCEDURE T;
        VAR N: STRING[40]; C: RECORD NAME: STRING[15]; PW: STRING[22]; ST: INTEGER; REST: ARRAY[1..83] OF INTEGER END;
        BEGIN
          READLN(N);
          R(C.NAME, I);
          IF (C.NAME = N) AND (C.ST <> 7) THEN I := 0
        END;
        BEGIN T END.
        """;

    /// <summary>
    ///  A word only compared as equal or not is a word, with the words after it padding.
    /// </summary>
    [TestMethod]
    public void WordsComparedAreWords()
    {
        PascalSystemDecompilerTests.RoundTrip(ComparedSource).Should().Contain("    A42: INTEGER;\n");
    }

    // A string written, and otherwise only moved into.
    private const string WrittenSource = """
        PROGRAM P;
        VAR C: CHAR; S: STRING[6]; X: PACKED ARRAY[0..9] OF CHAR;
        PROCEDURE A;
        BEGIN WRITELN('A', S) END;
        BEGIN MOVELEFT(X, S, 7); A END.
        """;

    /// <summary>
    ///  What WRITE writes as a string is one.
    /// </summary>
    [TestMethod]
    public void WrittenStringsAreStrings()
    {
        PascalSystemDecompilerTests.RoundTrip(WrittenSource).Should().Contain("G4: STRING[6];");
    }

    // An array of records in a record, reached by a variable index and at constant ones.
    private const string ElementsSource = """
        (*$R-*)
        PROGRAM P;
        TYPE IT = RECORD EQ, CU: BOOLEAN; IX: INTEGER END;
          CH = RECORD NAME: INTEGER; N: INTEGER; POSS: ARRAY[1..8] OF IT; AGE: INTEGER END;
        VAR C: ARRAY[0..5] OF CH; I, J: INTEGER;
        BEGIN
          IF C[I].POSS[J].CU THEN I := 0;
          C[I].POSS[1].IX := 3;
          C[I].POSS[2].EQ := TRUE;
          C[I].AGE := C[I].N
        END.
        """;

    /// <summary>
    ///  An array of records is one array with the scalars the code reaches at its elements' addresses, their first
    ///  fields.
    /// </summary>
    [TestMethod]
    public void ArraysOfRecordsAreOneArray()
    {
        PascalSystemDecompilerTests.RoundTrip(ElementsSource).Should().Contain("T2 = RECORD F0: INTEGER; F1: INTEGER; F2: T3; F26: INTEGER END;");
    }

    // An array whose bounds the code shows only the low one of, before a word the code never uses.
    private const string FittedSource = """
        (*$R-*)
        PROGRAM P;
        VAR B: ARRAY[32..95] OF ARRAY[1..4] OF INTEGER; X, Y, I: INTEGER;
        BEGIN UNITREAD(4, B, 512, 2, 0); I := B[I, 2]; Y := 1 END.
        """;

    /// <summary>
    ///  An array fitted to the words up to the next variable has whole elements, and the words past them are padding.
    /// </summary>
    [TestMethod]
    public void FittedArraysHaveWholeElements()
    {
        PascalSystemDecompilerTests.RoundTrip(FittedSource).Should().Contain("G259: INTEGER;");
    }

    // A CONCAT passed to a value string, and characters passed to value strings.
    private const string ConcatSource = """
        PROGRAM P;
        PROCEDURE W(S: STRING);
        BEGIN WRITELN(S) END;
        PROCEDURE O;
          PROCEDURE A(X, Y: STRING);
          BEGIN W(CONCAT('** ', X, Y, ' **')); EXIT(O) END;
        BEGIN A('A', 'B') END;
        BEGIN O END.
        """;

    /// <summary>
    ///  A CONCAT passes to a procedure's value string, and a character passes to one as itself.
    /// </summary>
    [TestMethod]
    public void StringsPassToValueStrings()
    {
        string source = PascalSystemDecompilerTests.RoundTrip(ConcatSource);
        source.Should().Contain("PROC2(CONCAT('** ', B2, B1, ' **'));").And.Contain("PROC4('A', 'B')");
    }

    // A record variable whose fields are set one by one, passed whole to a VAR record.
    private const string ContainedSource = """
        PROGRAM P;
        TYPE WL = RECORD LOW, MID, HIGH: INTEGER END;
        VAR G: WL; I: INTEGER;
        PROCEDURE ADD(VAR A, B: WL);
        BEGIN
          A.LOW := A.LOW + B.LOW;
          A.MID := A.MID + B.MID;
          A.HIGH := A.HIGH + B.HIGH
        END;
        PROCEDURE S;
        VAR T: WL; K: INTEGER;
        BEGIN
          T.HIGH := 0; T.LOW := 0; T.MID := 25; K := 1;
          ADD(G, T)
        END;
        BEGIN S END.
        """;

    /// <summary>
    ///  A variable whose address a call passes for a VAR record is that record, and the variables in its words its
    ///  fields.
    /// </summary>
    [TestMethod]
    public void VariablesPassedAsRecordsAreRecords()
    {
        PascalSystemDecompilerTests.RoundTrip(ContainedSource).Should().Contain("    A1: T2;\n    A4: INTEGER;\n");
    }

    /// <summary>
    ///  A 6502 function called inside an expression, below whose room for its result the expression has a word, is
    ///  signed by the words its code takes off the stack; and with a procedure whose code is before its, though its
    ///  number is after, they are written in the order of their code, and rebuild to the same segments.
    /// </summary>
    [TestMethod]
    public void AssembledFunctionsInExpressionsAreSignedByTheirCode()
    {
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        (byte[]? function, string assembled) = EmulatedPascalTools.Assemble(RandomSource, boot, tools, s_inputs);
        if (function is null) { Assert.Fail($"The Assembler stopped:\n{assembled}"); }

        (byte[]? host, string screen) = EmulatedPascalCompiler.Compile(RandomCaller, boot, tools, s_inputs);
        if (host is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

        (byte[]? linked, string linking) = EmulatedPascalTools.Link(host, [function], boot, tools, s_inputs);
        if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(linked));
        result.Source.Should().Contain("FUNCTION FUNC2: INTEGER;\n  EXTERNAL;").And.Contain("5 + FUNC2 MOD 7");
        result.Assembly.Should().StartWith("         .PROC   PROC3\n");
        LinkAndCompare(linked, Compiled(result.Source, boot, tools), result, boot, tools);
    }

    // A procedure of no parameters, and a function of none that takes its room for its result and leaves 9, for the
    // Assembler.
    private const string RandomSource = """
                .PROC   CLEAR,0
                RTS
                .FUNC   RANDOM,0
                PLA
                STA     RETURN
                PLA
                STA     RETURN+1
                PLA
                PLA
                PLA
                PLA
                LDA     #0
                PHA
                LDA     #9
                PHA
                LDA     RETURN+1
                PHA
                LDA     RETURN
                PHA
                RTS
        RETURN  .WORD   0
                .END
        """;

    // A program that calls the function inside an expression, with a word below it.
    private const string RandomCaller = """
        PROGRAM R;
        VAR I: INTEGER;
        FUNCTION RANDOM: INTEGER; EXTERNAL;
        PROCEDURE CLEAR; EXTERNAL;
        BEGIN
          CLEAR;
          I := 5 + RANDOM MOD 7
        END.
        """;

    private static byte[] Compiled(string source, string boot, string tools)
    {
        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(source, boot, tools, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{source}"); }
        return code;
    }

    // Assembles the decompiled assembled procedures, links them into the compiled code, and compares the segments.
    private static void LinkAndCompare(byte[] original, byte[] compiled, PascalDecompilation decompiled, string boot, string tools)
    {
        string assembly = decompiled.Assembly ?? throw new AssertFailedException("The program has assembled procedures.");
        (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, boot, tools, s_inputs);
        if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}"); }

        (byte[]? linked, string linking) = EmulatedPascalTools.Link(compiled, [assembled], boot, tools, s_inputs);
        if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }

        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(linked)).Should().BeEmpty();
    }

    // Wizardry's boot volume, and Apple Pascal 1.1's APPLE1 and APPLE2.
    private static (PascalVolume Volume, string Boot, string Tools) Volumes()
    {
        string wizardry = Path.Join(Disks, "Wizardry1 v2.1 - boot.woz");
        if (!File.Exists(wizardry))
        {
            Assert.Inconclusive("Set RETROCORE_WIZARDRY_DISKS to a folder with Wizardry's v2.1 boot disk, Wizardry1 v2.1 - boot.woz.");
        }

        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] sectors = SectorDiskReader.Read(WozDisk.Load(File.ReadAllBytes(wizardry)), proDosOrder: false);
        return (PascalVolume.Read(sectors, proDosOrder: false), boot, tools);
    }

    // Apple Pascal 1.2's APPLE1 with APPLE3's 128K system as its own, and without the Editor, which a compile does not
    // need.
    private static byte[] Boot128K(string apple1, string apple3)
    {
        byte[] boot = File.ReadAllBytes(apple1);
        PascalVolume extras = PascalVolume.Read(File.ReadAllBytes(apple3), proDosOrder: false);
        foreach ((string from, string to, PascalFileKind kind) in (ReadOnlySpan<(string, string, PascalFileKind)>)
            [("128K.APPLE", "SYSTEM.APPLE", PascalFileKind.Data), ("128K.PASCAL", "SYSTEM.PASCAL", PascalFileKind.Code)])
        {
            PascalVolume.DeleteFile(boot, proDosOrder: false, to);
            PascalVolume.WriteFile(boot, proDosOrder: false, to, kind, extras.ReadFile(from));
        }

        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR");
        return boot;
    }

    // Apple Pascal 1.2's APPLE2 with 1.1's Compiler in place of its own, its segments marked version 5, which the 1.2
    // system runs.
    private static byte[] Compiler11(string apple2, string apple2Of11)
    {
        byte[] compiler = PascalVolume.Read(File.ReadAllBytes(apple2Of11), proDosOrder: false).ReadFile("SYSTEM.COMPILER");

        // Each segment's information word has its version in its top three bits.
        const int SegmentInformation = 0x100;
        const int Segments = 16;
        const int Version = 5;
        for (int segment = 0; segment < Segments; segment++)
        {
            int high = SegmentInformation + (segment * 2) + 1;
            if (compiler[high] != 0) { compiler[high] = (byte)((compiler[high] & 0x1F) | (Version << 5)); }
        }

        byte[] tools = File.ReadAllBytes(apple2);
        PascalVolume.DeleteFile(tools, proDosOrder: false, "SYSTEM.COMPILER");
        PascalVolume.WriteFile(tools, proDosOrder: false, "SYSTEM.COMPILER", PascalFileKind.Code, compiler);
        return tools;
    }
}
