// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Decompiling the encodings Apple's system programs, such as its Compilers, use: segment procedures that call the
///  program's procedures, programs compiled as part of the system, <c>(*$U-*)</c>, and IDSEARCH and TREESEARCH.
/// </summary>
/// <remarks>
///  <para>
///   Each probe is compiled by Apple Pascal 1.1's Compiler on an emulated Apple II, decompiled, compiled again, and
///   compared with the first compile. They need Apple Pascal's disks (<c>RETROCORE_APPLE2_PASCAL_DISKS</c>).
///  </para>
/// </remarks>
[TestClass]
public class PascalSystemDecompilerTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // A segment procedure calls the program's procedure through CXP 1, 2; the procedure, whose body comes after the
    // segment procedure's, is declared FORWARD before it.
    private const string SegmentCallSource = """
        PROGRAM SEGP;
        VAR G: INTEGER;
        PROCEDURE A(X: INTEGER); FORWARD;
        SEGMENT PROCEDURE INIT;
        BEGIN A(3) END;
        PROCEDURE A;
        BEGIN G := X END;
        BEGIN INIT END.
        """;

    // A program compiled as part of the system: the system's outer block declares its globals, a pointer to its
    // SYSCOM record and pointers to files among them, and the program is its segment procedure 1, whose own segment
    // procedures follow the system's, 2 to 6, as Apple's Compilers' do.
    private const string SystemSource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF; SR = RECORD A, B: INTEGER END;
        VAR SYSCOM: ^SR; IN1, OUT1, TERM1, SWAP: INTEGER; G6, G7: INTEGER;
            CODEF, SYMF: FP; ERRNUM, ERRBLK, ERRSYM: INTEGER; SLOW, STUPID: BOOLEAN; ALT: CHAR;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER); FORWARD;
        SEGMENT PROCEDURE D2; FORWARD;
        SEGMENT PROCEDURE D3; FORWARD;
        SEGMENT PROCEDURE D4; FORWARD;
        SEGMENT PROCEDURE D5; FORWARD;
        SEGMENT PROCEDURE D6; FORWARD;
        SEGMENT PROCEDURE COMPILER;
        VAR B: PACKED ARRAY[0..511] OF CHAR; N: INTEGER;
        PROCEDURE ERROR(E: INTEGER); FORWARD;
        SEGMENT PROCEDURE INIT;
        BEGIN
          IF BLOCKREAD(SYMF^, B, 1, 0) <> 1 THEN ERROR(3);
          IF STUPID AND (ALT = 'E') THEN N := BLOCKWRITE(CODEF^, B, 1, ERRSYM);
          WRITELN(OUTPUT, 'X')
        END;
        PROCEDURE ERROR;
        BEGIN ERRNUM := E; IF SYSCOM^.A = 0 THEN ERRBLK := N END;
        BEGIN INIT END;
        BEGIN END.
        """;

    // The Compiler's own IDSEARCH and TREESEARCH, CSP IDS and CSP TRS.
    private const string SearchSource = """
        PROGRAM SEARCH;
        TYPE ALPHA = PACKED ARRAY[1..8] OF CHAR;
          CTP = ^NODE; NODE = RECORD NAME: ALPHA; L, R: CTP END;
          BUF = PACKED ARRAY[0..1023] OF CHAR;
        VAR CUR: INTEGER; BP: ^BUF; ROOT, FOUND: CTP; ID: ALPHA; I: INTEGER;
        BEGIN
          IDSEARCH(CUR, BP^);
          I := TREESEARCH(ROOT, FOUND, ID)
        END.
        """;

    // A pointer used as an integer: ORD of it compiles to nothing.
    private const string OrdinalSource = """
        PROGRAM O;
        TYPE R = RECORD A, B: INTEGER END;
        VAR P: ^R; I: INTEGER;
        BEGIN NEW(P); P^.A := 1; I := ORD(P); I := ORD(P) + 4; IF ORD(P) = I THEN I := 0 END.
        """;

    // A record with a variant part, like the Compiler's identifiers: VALUE, an integer, and TYP, a pointer, share a
    // word, reached through different procedures' parameters.
    private const string VariantSource = """
        PROGRAM V;
        TYPE K = (KONST, VARS, PROC);
          P = ^N;
          N = RECORD NAME: INTEGER; LINK: P;
            CASE KLASS: K OF
              KONST: (VALUE: INTEGER; NEXT: P);
              VARS: (TYP: P; ADDR: INTEGER);
              PROC: (LEV: INTEGER)
          END;
        VAR A: P; I: INTEGER;
        PROCEDURE USE(Q: P);
        BEGIN I := Q^.VALUE * 3 END;
        PROCEDURE USE2(Q: P);
        BEGIN I := Q^.TYP^.NAME; Q^.TYP^.LINK := Q; Q^.ADDR := Q^.NEXT^.NAME END;
        BEGIN NEW(A); USE(A); USE2(A); A := A^.LINK END.
        """;

    // A word that is an integer or a pointer, like the Compiler's VALU, set through a VAR parameter and read into a
    // plain integer and a plain pointer.
    private const string ValueSource = """
        PROGRAM W;
        TYPE CP = ^C; C = RECORD N: INTEGER; X: CP END;
          VALU = RECORD CASE BOOLEAN OF TRUE: (IVAL: INTEGER); FALSE: (VALP: CP) END;
        VAR V: VALU; I: INTEGER; P: CP;
        PROCEDURE K(VAR F: VALU);
        BEGIN IF I > 0 THEN F.IVAL := I * 2 ELSE BEGIN NEW(F.VALP); F.VALP^.N := 1 END END;
        BEGIN K(V); I := V.IVAL + 1; P := V.VALP; P^.X := P END.
        """;

    // Segment procedures inside a segment procedure and inside an ordinary procedure, as the Compiler's are, which
    // reach their parents' variables.
    private const string NestedSource = """
        PROGRAM N;
        VAR G: INTEGER;
        SEGMENT PROCEDURE OUTER;
        VAR L: INTEGER;
          PROCEDURE HELP; FORWARD;
          SEGMENT PROCEDURE INNER;
          VAR M: INTEGER;
          BEGIN M := G; L := M + 1; HELP END;
          PROCEDURE DEEP;
          VAR K: INTEGER;
            SEGMENT PROCEDURE INNEST;
            BEGIN K := L * 2 END;
          BEGIN K := 0; INNEST; G := K END;
          PROCEDURE HELP; BEGIN G := L END;
        BEGIN INNER; DEEP END;
        BEGIN OUTER END.
        """;

    /// <summary>
    ///  A segment procedure below level 1 is declared in the procedure its callers are in at the level above, a
    ///  segment procedure or an ordinary one, so the words it reaches there are that procedure's.
    /// </summary>
    [TestMethod]
    public void SegmentProceduresNestWhereTheirCallersAre()
    {
        string source = RoundTrip(NestedSource);
        source.Should().Contain("  SEGMENT PROCEDURE INNER;\n").And.Contain("    A7X1 := B8X1 + 1;");
        source.Should().Contain("    SEGMENT PROCEDURE INNEST;\n    BEGIN\n      B7X1 := A7X1 * 2\n    END;");
    }

    // A packed record, whose fields share words, in an array.
    private const string PackedSource = """
        PROGRAM PK;
        TYPE R = PACKED RECORD A: 0..7; B: BOOLEAN; C: 0..255; D: INTEGER; E: 0..15 END;
        VAR X: ARRAY[0..9] OF R; I: INTEGER;
        BEGIN
          X[I].A := 5; X[I].C := I; IF X[2].B THEN I := X[3].E; X[1].D := 7
        END.
        """;

    /// <summary>
    ///  A record whose fields the code reaches by word and bit is a packed record with each field at its word and bit,
    ///  with fillers before and between them and to each word's end.
    /// </summary>
    [TestMethod]
    public void PackedRecordsKeepTheirFieldsBits()
    {
        string source = RoundTrip(PackedSource);
        source.Should().Contain("PACKED RECORD F0B0: 0..7; F0B3: BOOLEAN; X0B4: 0..15; F0B8: 0..255; F1: INTEGER; F2B0: 0..15; X2B4: 0..4095 END;");
    }

    /// <summary>
    ///  Records whose words are integers in one place and pointers in another decompile with a variant part, each
    ///  use naming its variant's field.
    /// </summary>
    [TestMethod]
    public void RecordsWithVariantsDecompileWithAVariantPart()
    {
        string source = RoundTrip(VariantSource);
        source.Should().Contain("CASE INTEGER OF 0: (F3: INTEGER; F4: T3); 1: (F3V1: T4) END;");
        source.Should().Contain(" := A1^.F3 * 3").And.Contain(" := A1^.F3V1^.F0;");
    }

    /// <summary>
    ///  A word used both ways keeps its views through a VAR parameter and NEW, and the integer and the pointer read
    ///  from it keep their own types.
    /// </summary>
    [TestMethod]
    public void WordsUsedBothWaysKeepTheirViews()
    {
        string source = RoundTrip(ValueSource);
        source.Should().Contain("A1.I := G4 * 2").And.Contain("NEW(A1.P);").And.Contain("A1.P^.F0 := 1");
        source.Should().Contain("  G4: INTEGER;\n  G5: T3;\n").And.Contain("G5 := G3.P;");
    }

    /// <summary>
    ///  A pointer used as an integer decompiles to ORD of it, the pointer keeping its own type, rather than to a word
    ///  used both ways.
    /// </summary>
    [TestMethod]
    public void PointersUsedAsIntegersAreOrd()
    {
        string source = RoundTrip(OrdinalSource);
        source.Should().Contain("G4 := ORD(G3);").And.Contain("G4 := ORD(G3) + 4;").And.NotContain("CASE BOOLEAN");
    }

    /// <summary>
    ///  A segment procedure's call of the program's procedure, CXP 1, n, decompiles to a call of it, declared FORWARD
    ///  before the segment procedure, which takes its segment's name.
    /// </summary>
    [TestMethod]
    public void SegmentProceduresCallTheProgramsProcedures()
    {
        string source = RoundTrip(SegmentCallSource);
        source.Should().Contain("PROCEDURE PROC2(A1: INTEGER); FORWARD;\nSEGMENT PROCEDURE INIT;\nBEGIN\n  PROC2(3)\nEND;");
    }

    /// <summary>
    ///  A program compiled as part of the system decompiles to the system's outer block, which declares the globals
    ///  the program reaches, with a pointer for each it passes as a file, around the program as its segment procedure.
    /// </summary>
    [TestMethod]
    public void SystemProgramsDeclareTheSystemsGlobals()
    {
        string source = RoundTrip(SystemSource);
        source.Should().StartWith("(*$U-*)  (* Compiled as part of the system: its globals are the system's, I/O and range checks off. *)\nPROGRAM PASCALSY;\n");
        source.Should().Contain("  SYS8: T4;\n  SYS9: T4;\n").And.Contain("IF BLOCKREAD(SYS8^, G3, 1, 0) <> 1 THEN");
        source.Should().Contain("SEGMENT PROCEDURE COMPILER(G2: INTEGER; G1: INTEGER); FORWARD;\nSEGMENT PROCEDURE SYSSEG2; FORWARD;");
        source.Should().Contain("SEGMENT PROCEDURE SYSSEG6; FORWARD;\nSEGMENT PROCEDURE COMPILER;\n");
        source.Should().EndWith("END;\nBEGIN\nEND.\n");
    }

    /// <summary>
    ///  CSP IDS and CSP TRS decompile to IDSEARCH and TREESEARCH.
    /// </summary>
    [TestMethod]
    public void IdSearchAndTreeSearchDecompile()
    {
        string source = RoundTrip(SearchSource);
        source.Should().Contain("IDSEARCH(G3, G4^);").And.Contain(" := TREESEARCH(G6, G5, G7)");
    }

    // Compiles a probe, decompiles it, and checks the decompiled source compiles to the same segments.
    private static string RoundTrip(string probe)
    {
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string compiler = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(boot) || !File.Exists(compiler))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        (byte[]? original, string compiled) = EmulatedPascalCompiler.Compile(probe, boot, compiler, s_inputs);
        if (original is null) { Assert.Fail($"The Compiler stopped:\n{compiled}"); }

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        result.Warnings.Should().BeEmpty(result.Source);

        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, boot, compiler, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(code)).Should().BeEmpty(result.Source);
        return result.Source;
    }
}
