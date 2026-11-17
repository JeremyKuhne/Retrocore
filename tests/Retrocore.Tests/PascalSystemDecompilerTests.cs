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
    // procedures NS numbers from 7, as Apple's Compilers' are.
    private const string SystemSource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF; SR = RECORD A, B: INTEGER END;
        VAR SYSCOM: ^SR; IN1, OUT1, TERM1, SWAP: INTEGER; G6, G7: INTEGER;
            CODEF, SYMF: FP; ERRNUM, ERRBLK, ERRSYM: INTEGER; SLOW, STUPID: BOOLEAN; ALT: CHAR;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR B: PACKED ARRAY[0..511] OF CHAR; N: INTEGER;
        PROCEDURE ERROR(E: INTEGER); FORWARD;
        (*$NS 7*)
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

    // A program compiled as part of the system that calls a system procedure past the standard ones, sets a string's
    // length, and passes strings of two lengths to a VAR string that only its own statements show is one.
    private static readonly string s_systemCallSource = $"""
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF; SR = RECORD A, B: INTEGER END; SP = ^STRING;
        VAR SYSCOM: ^SR; IN1, OUT1, TERM1, SWAP: INTEGER; G6, G7: INTEGER;
            CODEF, SYMF: FP; ERRNUM, ERRBLK, ERRSYM: INTEGER; SLOW, STUPID: BOOLEAN; ALT: CHAR;
        {string.Join("\n", Enumerable.Range(2, 41).Select(number => $"PROCEDURE P{number}; FORWARD;"))}
        PROCEDURE FIXNAME(VAR S: STRING; A, B: INTEGER); FORWARD;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR L: STRING[40]; P: SP; N: INTEGER;
        PROCEDURE GET(VAR S: STRING; K: INTEGER); BEGIN IF S = 'XY' THEN N := K END;
        BEGIN
          GET(L, 40); FIXNAME(L, 1, 40); L[0] := CHR(N);
          NEW(P); GET(P^, 80)
        END;
        BEGIN END.
        """;

    /// <summary>
    ///  A program compiled as part of the system calls a system procedure no standard procedure names by a heading in
    ///  the system's block, FORWARD, numbered with those before it; a string's length is set as its byte 0; and strings
    ///  of two lengths passed to one VAR string keep their own.
    /// </summary>
    [TestMethod]
    public void SystemProgramsCallTheSystemsOtherProcedures()
    {
        string source = RoundTrip(s_systemCallSource);
        source.Should().Contain("PROCEDURE SYSTEM42; FORWARD;\nPROCEDURE SYSTEM43(VAR A1: ");
        source.Should().Contain("SYSTEM43(").And.Contain("[0] := CHR(");
    }

    /// <summary>
    ///  Hints name the system's procedures and their parameters, by number (SYSTEM.43, SYSTEM.43@1): the headings and
    ///  the calls take the names, and the source still compiles to the same code.
    /// </summary>
    [TestMethod]
    public void HintsNameTheSystemsProcedures()
    {
        PascalDecompilerOptions options = new()
        {
            Names = new Dictionary<string, string>
            {
                ["SYSTEM.2"] = "EXECERROR",
                ["SYSTEM.43"] = "FIXNAME",
                ["SYSTEM.43@1"] = "TITLE",
                ["SYSTEM.42"] = "EXECERRORS"
            }
        };

        string source = RoundTrip(s_systemCallSource, options, out IReadOnlyList<string> warnings);
        source.Should().Contain("PROCEDURE EXECERROR; FORWARD;\n").And.Contain("PROCEDURE FIXNAME(VAR TITLE: ");
        source.Should().Contain("FIXNAME(").And.NotContain("SYSTEM43");
        warnings.Should().Contain(warning => warning.Contains("EXECERRORS for SYSTEM.42 would clash", StringComparison.Ordinal));
    }

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

    // NEW of a record's variants, each as long as its variant, as the Compiler allocates its identifiers.
    private const string NewVariantSource = """
        PROGRAM NV;
        TYPE K = (A, B, C);
          P = ^R;
          R = RECORD S: INTEGER; L: P;
            CASE F: K OF
              A: (X: INTEGER);
              B: (Y, Z, W: INTEGER);
              C: ()
          END;
        VAR Q: P;
        BEGIN NEW(Q, A); Q^.X := 1; NEW(Q, C); Q^.S := 2; NEW(Q, B); Q^.W := 3; NEW(Q); Q^.L := Q END.
        """;

    /// <summary>
    ///  NEW of fewer words than its record has takes a variant of the record as long as the words, labelled with 100
    ///  more than them.
    /// </summary>
    [TestMethod]
    public void NewTakesVariantsAsLongAsItAllocates()
    {
        string source = RoundTrip(NewVariantSource);
        source.Should().Contain("; 103: (X3N: ARRAY[1..3] OF INTEGER); 104: (X4N: ARRAY[1..4] OF INTEGER) END;");
        source.Should().Contain("NEW(G3, 104);").And.Contain("NEW(G3, 103);");
    }

    /// <summary>
    ///  With <see cref="PascalDecompilerOptions.PcodeComments"/>, each statement is written below its p-code in a
    ///  brace comment, a loop's test above it and its jump back below its body, a WITH's statements each below their
    ///  own, and the source compiles the same.
    /// </summary>
    [TestMethod]
    public void StatementsAreWrittenBelowTheirPcode()
    {
        const string Probe = """
            PROGRAM PC;
            TYPE R = RECORD A, B: INTEGER END;
            VAR I, J: INTEGER; X: ARRAY[1..3] OF R;
            BEGIN
              FOR I := 1 TO 3 DO
                WITH X[I] DO
                  BEGIN
                    A := I;
                    B := J
                  END;
              I := 1;
              J := 0;
              WHILE I < 10 DO
                BEGIN
                  J := J + I;
                  I := I + 1
                END;
              REPEAT
                I := I - 1
              UNTIL I = 0;
              WRITELN('A, B', J)
            END.
            """;

        string source = RoundTrip(Probe, new PascalDecompilerOptions { PcodeComments = true }, out _);
        string[] lines = [.. source.Split('\n').Select(line => line.Trim())];
        int loop = Array.FindIndex(lines, line => line.StartsWith("WHILE ", StringComparison.Ordinal));
        loop.Should().BePositive(source);
        lines[loop - 1].Should().MatchRegex(@"^\{.*LESI; FJP \$[0-9A-F]{4}\}$", source);
        lines.Should().Contain(line => line.StartsWith("{UJP $", StringComparison.Ordinal), source);

        // A WITH's statements are each below their own p-code, not all of it above the FOR.
        int with = Array.FindIndex(lines, line => line.StartsWith("WITH ", StringComparison.Ordinal));
        lines[with - 1].Should().MatchRegex(@"^\{.*IXA.*\}$", source);
        lines[with - 2].Should().StartWith("FOR ", source);
        lines[with + 1].Should().Be("BEGIN", source);
        lines[with + 2].Should().StartWith("{", source);
        lines[with + 3].Should().Contain(":=", source);
        lines[with + 4].Should().StartWith("{", source);
        int until = Array.FindIndex(lines, line => line.StartsWith("UNTIL ", StringComparison.Ordinal));
        lines[until - 1].Should().MatchRegex(@"^\{.*EQUI; FJP \$[0-9A-F]{4}\}$", source);
        source.Should().Contain("LSA 'A, B'", source);
        lines[^3].Should().EndWith("RBP 0}", source);
    }

    /// <summary>
    ///  Hints name a record's variants' labels (T2:104), declared as constants, which NEW of the variant takes too,
    ///  and their padding (T2.X4N), and the source still compiles to the same code.
    /// </summary>
    [TestMethod]
    public void HintsNameVariantsAndTheirPadding()
    {
        PascalDecompilerOptions options = new()
        {
            Names = new Dictionary<string, string>
            {
                ["T2:104"] = "ASIZE",
                ["T2:103"] = "CSIZE",
                ["T2:0"] = "WHOLE",
                ["T2.X4N"] = "AWORDS"
            }
        };

        string source = RoundTrip(NewVariantSource, options, out _);
        source.Should().Contain("CONST\n  (* T2's variants *)\n  WHOLE = 0;\n  CSIZE = 103;\n  ASIZE = 104;\nTYPE");
        source.Should().Contain("WHOLE: (F0: INTEGER;").And.Contain("ASIZE: (AWORDS: ARRAY[1..4] OF INTEGER)\n");
        source.Should().Contain("NEW(G3, ASIZE);").And.Contain("NEW(G3, CSIZE);");
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
        source.Should().Contain("SEGMENT PROCEDURE COMPILER(G2: INTEGER; G1: INTEGER);\n");
        source.Should().Contain("  (*$NS 7*)  (* The next segment is numbered 7. *)\n  SEGMENT PROCEDURE INIT;");
        source.Should().EndWith("END;\nBEGIN\nEND.\n");
    }

    // The record HintsNameTheSystemsGlobalsTypesAndFields names, a field to a line with its comment.
    private const string HintedRecord = """
          (* The system's record:
             its two words *)
          SysRec = RECORD
              Second: INTEGER;
              First: INTEGER  (* Its A *)
            END;
          T1 = ^SysRec;

        """;

    /// <summary>
    ///  Hints name the system's globals, by their words, and types and their fields, by the decompiler's names for
    ///  them, and comment them; a record with a field named is written a field to a line, each with its comment. A
    ///  name another in the source has is refused, with a warning, and the source still compiles to the same code.
    /// </summary>
    [TestMethod]
    public void HintsNameTheSystemsGlobalsTypesAndFields()
    {
        PascalDecompilerOptions options = new()
        {
            Names = new Dictionary<string, string>
            {
                ["SYSTEM@1"] = "SysCom",
                ["SYSTEM@8"] = "SymFile",
                ["SYSTEM@9"] = "Buffer",
                ["COMPILER.1@3"] = "Buffer",
                ["T2"] = "SysRec",
                ["T2.F1"] = "First",
                ["T2.F0"] = "Second",
                ["T1"] = "SysCom",
                ["T5"] = "AFile"
            },
            Comments = new Dictionary<string, string>
            {
                ["SYSTEM@8"] = "The source",
                ["COMPILER.1@3"] = "A block",
                ["T2"] = "The system's record:\nits two words",
                ["T2.F1"] = "Its A"
            }
        };

        string source = RoundTrip(SystemSource, options, out IReadOnlyList<string> warnings);
        source.Should().Contain(HintedRecord);
        source.Should().Contain("  SysCom: T1;\n").And.Contain("  SymFile: T4;  (* The source *)\n");
        source.Should().Contain("    Buffer: T6;  (* A block *)\n");
        source.Should().Contain("IF BLOCKREAD(SymFile^, Buffer, 1, 0) <> 1 THEN").And.Contain("IF SysCom^.First = 0 THEN");
        source.Should().Contain("  AFile = FILE;");
        warnings.Should().Contain(warning => warning.Contains("Buffer for SYSTEM@9 would clash with Buffer", StringComparison.Ordinal));
        warnings.Should().Contain(warning => warning.Contains("SysCom for T1 would clash with another name the source has", StringComparison.Ordinal));
    }

    // A program compiled as part of the system that indexes the system's files from its first word, as Apple Pascal
    // 1.0's Compiler reads its source.
    private const string SystemFilesSource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF;
        VAR GFILES: ARRAY[0..8] OF FP; ERRNUM: INTEGER;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR B: PACKED ARRAY[0..511] OF CHAR;
        BEGIN
          IF BLOCKREAD(GFILES[Q]^, B, 1, 0) <> 1 THEN ERRNUM := 3
        END;
        BEGIN END.
        """;

    /// <summary>
    ///  A system global indexed for a file to pass is an array of pointers to files.
    /// </summary>
    [TestMethod]
    public void SystemFilesIndexedAreArraysOfPointersToFiles()
    {
        string source = RoundTrip(SystemFilesSource);
        source.Should().Contain("  T2 = ^T3;\n  T1 = ARRAY[0..8] OF T2;\n").And.Contain("BLOCKREAD(SYS1[G2]^, ");
    }

    // A program compiled as part of the system by Apple Pascal 1.0's Compiler, which has no NS: segment procedures
    // declared FORWARD and never given a body take segments 2 and 3, so that its segment procedure is 4.
    private const string SkippedSegmentsSource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        VAR SYSCOM: INTEGER;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR N: INTEGER;
        SEGMENT PROCEDURE SEG2; FORWARD;
        SEGMENT PROCEDURE SEG3; FORWARD;
        SEGMENT PROCEDURE INIT;
        BEGIN N := 1 END;
        BEGIN INIT END;
        BEGIN END.
        """;

    /// <summary>
    ///  Apple Pascal 1.0's Compiler, which has no NS option, numbers a segment past those before it by segment
    ///  procedures declared FORWARD, whose slots stay empty.
    /// </summary>
    [TestMethod]
    public void SegmentsSkippedWithoutNsAreForwardSegments()
    {
        string source = RoundTrip(SkippedSegmentsSource, version: "1.0");
        source.Should().Contain("  SEGMENT PROCEDURE SEG2; FORWARD;").And.Contain("  SEGMENT PROCEDURE SEG3; FORWARD;").And.NotContain("$NS");
    }

    // A word read as a boolean in one variant and compared as an integer, by EQUI, in another.
    private const string BooleanWordSource = """
        PROGRAM BW;
        TYPE R = RECORD A: INTEGER; CASE INTEGER OF 0: (B: BOOLEAN); 1: (K: INTEGER) END;
        VAR X: ^R; F: BOOLEAN;
        BEGIN
          NEW(X); X^.A := 0; X^.K := 1; F := X^.B AND F;
          IF X^.B THEN X^.A := 2;
          IF X^.K = 1 THEN F := FALSE;
          IF X^.K <> 21 THEN F := TRUE
        END.
        """;

    /// <summary>
    ///  A boolean compared as a word, by EQUI or NEQI, is compared as an integer, ORD of it, not as a boolean, which
    ///  EQUBOOL compares.
    /// </summary>
    [TestMethod]
    public void BooleansComparedAsWordsAreOrd()
    {
        string source = RoundTrip(BooleanWordSource, version: "1.0");
        source.Should().Contain("IF ORD(G3^.F1) = 1 THEN").And.Contain("IF ORD(G3^.F1) <> 21 THEN");
    }

    // A word used both ways that points to bytes in one place and to bits in another, as 1.3's Compiler reads the
    // system's version and its options.
    private const string ViewsSource = """
        PROGRAM PB;
        TYPE BA = PACKED ARRAY[0..15] OF CHAR; BB = PACKED ARRAY[0..127] OF BOOLEAN;
          W = RECORD CASE INTEGER OF 0: (I: INTEGER); 1: (P: ^BA); 2: (Q: ^BB) END;
        VAR H: BOOLEAN; W1: W;
        BEGIN W1.I := -16607; IF W1.P^[0] <> CHR(4) THEN H := FALSE; W1.I := -16606; H := W1.Q^[6] END.
        """;

    /// <summary>
    ///  What a word used both ways points to, read as bytes in one place and bits in another, is two variants'
    ///  pointers, as the two cannot be one array.
    /// </summary>
    [TestMethod]
    public void WordsPointingToBytesAndBitsHaveAVariantForEach()
    {
        string source = RoundTrip(ViewsSource);
        source.Should().Contain("1: (P: ^T2); 2: (P2: ^T3) END;").And.Contain(".P2^[6]");
    }

    // Bytes written with a width of their own, a constant and a variable.
    private const string WidthSource = """
        PROGRAM WB;
        VAR A: PACKED ARRAY[0..9] OF CHAR; W: INTEGER;
        BEGIN W := 3; WRITE(A:5); WRITE(A:W) END.
        """;

    /// <summary>
    ///  WRITE of bytes passes their field's width, then their count (FWRITEBYTES), so the width is the one before.
    /// </summary>
    [TestMethod]
    public void WrittenBytesKeepTheirWidths()
    {
        string source = RoundTrip(WidthSource);
        source.Should().Contain("WRITE(G3:5, G3:G8)");
    }

    // A record's name that the code only writes, with words after it that the code never names.
    private const string WrittenNameSource = """
        PROGRAM WN;
        TYPE R = RECORD N: PACKED ARRAY[0..7] OF CHAR; X, Y: INTEGER; K: INTEGER END;
        VAR P: ^R;
        BEGIN NEW(P); P^.K := 1; WRITELN(P^.N, P^.K) END.
        """;

    /// <summary>
    ///  Bytes that WRITE writes, with no bounds the code shows, are as many as it writes, not as many as the words up to
    ///  the next field hold.
    /// </summary>
    [TestMethod]
    public void WrittenBytesAreAsLongAsWriteWrites()
    {
        string source = RoundTrip(WrittenNameSource);
        source.Should().Contain("PACKED ARRAY[0..7] OF CHAR");
    }

    // An IF whose THEN is only a GOTO into the next IF's THEN.
    private const string GotoIntoSource = """
        (*$G+*)
        PROGRAM GI;
        LABEL 1;
        VAR I, J: INTEGER;
        BEGIN
          I := 0; J := 0;
          IF I = 0 THEN GOTO 1;
          IF I > 3 THEN BEGIN J := 2; 1: J := J + 1 END ELSE J := 5
        END.
        """;

    /// <summary>
    ///  An IF whose THEN is a GOTO forward has no ELSE where the code after it has an FJP that leaves it, as the
    ///  Compiler's FJPs stay in their statements.
    /// </summary>
    [TestMethod]
    public void GotosForwardAreNotElsesWhereAnFjpLeaves()
    {
        string source = RoundTrip(GotoIntoSource);
        source.Should().Contain("GOTO 1");
    }

    // An IF inside an IF, whose THEN is a GOTO: the UJP before the outer IF's end is the inner one's.
    private const string InnerGotoSource = """
        (*$G+*)
        PROGRAM IG;
        LABEL 1;
        VAR I: INTEGER; B: BOOLEAN;
        BEGIN
          I := 0; B := TRUE;
          WHILE I < 10 DO
          BEGIN
            I := I + 1;
            IF B THEN IF I IN [2, 4] THEN GOTO 1;
            B := I < 7;
            1:
          END
        END.
        """;

    /// <summary>
    ///  A UJP that ends an IF's THEN is not the jump over an ELSE where an IF inside jumps to the same place, as a
    ///  GOTO in the inner IF's THEN.
    /// </summary>
    [TestMethod]
    public void GotosEndingAnInnerIfAreNotElses()
    {
        string source = RoundTrip(InnerGotoSource);
        source.Should().Contain("GOTO 1");
    }

    // A value parameter copied in, in a procedure with two WITH statements that keep their records' addresses in one
    // word, which is decoded again for them.
    private const string CopiedWithSource = """
        PROGRAM CW;
        TYPE ALFA = PACKED ARRAY[1..8] OF CHAR; R = RECORD A, B: INTEGER END;
        VAR P, Q: ^R; N: ALFA;
        PROCEDURE SHOW(S: ALFA);
        BEGIN
          WITH P^ DO A := ORD(S[1]);
          WITH Q^ DO B := ORD(S[2])
        END;
        BEGIN NEW(P); NEW(Q); N := 'ABCDEFGH'; SHOW(N) END.
        """;

    /// <summary>
    ///  A value parameter's copy is still its copy in a procedure decoded again for its WITH statements, not an
    ///  assignment at the start of its body.
    /// </summary>
    [TestMethod]
    public void ValueParametersStayCopiedWhereWithsShareAWord()
    {
        string source = RoundTrip(CopiedWithSource);
        source.Should().Contain("PROCEDURE PROC2(A1: T5);\nBEGIN\n  WITH");
    }

    // Characters stored at an index from a WITH's record, which are its first field's, a packed array's.
    private const string FirstIndexedSource = """
        PROGRAM FI;
        TYPE N = RECORD S: PACKED ARRAY[0..23] OF CHAR; L: ^N END;
        VAR P: ^N; T: PACKED ARRAY[0..9] OF CHAR; I: INTEGER;
        BEGIN
          T := 'ABCDEFGHIJ'; NEW(P);
          WITH P^ DO
          BEGIN
            MOVELEFT(T[1], S, 3);
            I := 3;
            IF I < 24 THEN S[I] := ' ';
            L := NIL
          END
        END.
        """;

    /// <summary>
    ///  A byte stored at an index from a record's address is its first field's element, a packed array's, not the
    ///  record's.
    /// </summary>
    [TestMethod]
    public void RecordsIndexedByBytesIndexTheirFirstFields()
    {
        string source = RoundTrip(FirstIndexedSource);
        source.Should().Contain("F0[G9] := ' '");
    }

    // SCAN of a WITH's record, from its address: its first field, which the WITH's temporary reaches.
    private const string ScannedWithSource = """
        PROGRAM SW;
        TYPE N = RECORD S: PACKED ARRAY[0..23] OF CHAR; L: ^N END;
        VAR P: ^N; I: INTEGER;
        BEGIN
          NEW(P);
          WITH P^ DO
          BEGIN
            I := SCAN(24, = ' ', S);
            L := NIL
          END
        END.
        """;

    /// <summary>
    ///  The array SCAN scans, inside a WITH on its record, is the record's first field, which the WITH reaches,
    ///  rather than the record through its pointer again.
    /// </summary>
    [TestMethod]
    public void ScansInsideWithsScanTheFirstField()
    {
        string source = RoundTrip(ScannedWithSource);
        source.Should().Contain("SCAN(24, = ' ', F0)");
    }

    // A GOTO out of a WHILE to the end of the THEN around it.
    private const string ThenEndSource = """
        (*$G+*)
        PROGRAM TE;
        LABEL 1;
        VAR I, J: INTEGER;
        BEGIN
          I := 0; J := 0;
          IF I = 0 THEN
          BEGIN
            WHILE J < 3 DO BEGIN IF J = 2 THEN GOTO 1; J := J + 1 END;
            I := 5;
            1:
          END
          ELSE I := 7
        END.
        """;

    /// <summary>
    ///  A GOTO to an IF's jump over its ELSE goes to a label at the end of its THEN.
    /// </summary>
    [TestMethod]
    public void GotosToTheEndOfAThenHaveALabelThere()
    {
        string source = RoundTrip(ThenEndSource);
        source.Should().Contain("GOTO 1");
    }

    // An IF with an empty ELSE, which jumps to where the ELSE starts.
    private const string EmptyElseSource = """
        PROGRAM EE;
        VAR I, J: INTEGER;
        BEGIN I := 3; IF I = 3 THEN J := 1 ELSE ; I := J END.
        """;

    /// <summary>
    ///  An IF's jump over an ELSE with nothing in it is the ELSE's, not a GOTO.
    /// </summary>
    [TestMethod]
    public void EmptyElsesDecompile()
    {
        string source = RoundTrip(EmptyElseSource);
        source.Should().Contain("ELSE").And.NotContain("GOTO");
    }

    // A GOTO out of an inner WHILE to the end of the outer one's body.
    private const string LoopEndSource = """
        (*$G+*)
        PROGRAM LE;
        LABEL 1;
        VAR I, J: INTEGER;
        BEGIN
          I := 0;
          WHILE I < 5 DO
          BEGIN
            I := I + 1; J := 0;
            WHILE J < 3 DO BEGIN IF J = I THEN GOTO 1; J := J + 1 END;
            1:
          END
        END.
        """;

    /// <summary>
    ///  A GOTO to the jump back of a WHILE goes to a label at the end of its body.
    /// </summary>
    [TestMethod]
    public void GotosToTheEndOfALoopsBodyHaveALabelThere()
    {
        string source = RoundTrip(LoopEndSource);
        source.Should().Contain("GOTO 1");
    }

    // A procedure that keeps segments in memory while it runs, one by its number, with an EXIT out of it.
    private const string ResidentSource = """
        PROGRAM RS;
        VAR G: INTEGER;
        SEGMENT PROCEDURE SEGA;
        BEGIN G := 1 END;
        SEGMENT PROCEDURE SEGB;
          SEGMENT PROCEDURE SEGC;
          BEGIN G := 4 END;
        BEGIN G := 2; SEGC END;
        PROCEDURE P;
        BEGIN (*$R SEGA,SEGB,9*)
          IF G = 3 THEN EXIT(P);
          SEGA; SEGB
        END;
        BEGIN P END.
        """;

    /// <summary>
    ///  A procedure that loads segments as it starts and releases them as it ends has the R option, naming those it
    ///  sees and numbering the others, as a segment procedure nested in another: each in an option of its own, as
    ///  Apple III Pascal 1.0's Compiler takes only the first segment of a list.
    /// </summary>
    [TestMethod]
    public void ResidentSegmentsDecompileToTheROption()
    {
        string source = RoundTrip(ResidentSource);
        source.Should().Contain("BEGIN (*$R SEGA*)(*$R SEGB*)(*$R 9*)");
    }

    // MOVELEFT from a WITH's record's first field, at the record's address.
    private const string WithMoveSource = """
        PROGRAM WM;
        TYPE R = RECORD N: PACKED ARRAY[0..7] OF CHAR; K: INTEGER END;
        VAR P: ^R; B: PACKED ARRAY[0..15] OF CHAR;
        BEGIN NEW(P); WITH P^ DO BEGIN K := 1; MOVELEFT(N, B, 8); K := K + 1 END END.
        """;

    /// <summary>
    ///  An untyped argument at a WITH's record's address is its first field, which the WITH reaches.
    /// </summary>
    [TestMethod]
    public void UntypedArgumentsInsideAWithAreItsRecordsFirstField()
    {
        string source = RoundTrip(WithMoveSource);
        source.Should().Contain("MOVELEFT(F0, ");
    }

    // A WITH inside another, on a record of another type, whose fields the outer's are at the offsets of.
    private const string NestedWithSource = """
        PROGRAM NW;
        TYPE A = RECORD X, Y, Z: INTEGER END;
          B = RECORD U: CHAR; V: BOOLEAN END;
        VAR P: ^A; Q: ^B;
        BEGIN
          NEW(P); NEW(Q); Q^.U := 'A'; Q^.V := TRUE;
          WITH P^ DO BEGIN WITH Q^ DO BEGIN X := ORD(U); Y := ORD(V) END; Z := X + 1 END
        END.
        """;

    /// <summary>
    ///  The fields of an outer WITH's record are named with its type's name, so that an inner WITH's record of
    ///  another type does not hide them and they are reached through the outer WITH.
    /// </summary>
    [TestMethod]
    public void OuterWithRecordsNameTheirFieldsWithTheirTypes()
    {
        string source = RoundTrip(NestedWithSource);
        source.Should().Contain("WITH ").And.Contain("F2 := ");
    }

    // A word used both ways assigned whole, which the Compiler moves as the one-word record it is.
    private const string WholeWordSource = """
        PROGRAM WW;
        TYPE P = ^R;
          R = RECORD N: INTEGER END;
          W = RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (Q: P) END;
        VAR A, B: W;
        BEGIN NEW(A.Q); A.Q^.N := 1; B := A; B.I := B.I + 1 END.
        """;

    /// <summary>
    ///  A word used both ways that is moved whole is assigned whole, so that it is moved again.
    /// </summary>
    [TestMethod]
    public void WordsUsedBothWaysMovedWholeAreAssignedWhole()
    {
        string source = RoundTrip(WholeWordSource);
        source.Should().Contain("G3 := G4;");
    }

    // A local record moved whole from a global, whose first field, a pointer, is otherwise used alone.
    private const string WholeLocalSource = """
        PROGRAM WL;
        TYPE P = ^R;
          R = RECORD A: P; B, C: INTEGER END;
        VAR G: R; H: INTEGER;
        PROCEDURE X;
          VAR L: R; K: INTEGER;
          PROCEDURE Y(VAR Q: P); BEGIN H := Q^.C END;
        BEGIN L := G; K := 1; Y(L.A); IF L.A <> NIL THEN K := L.A^.B; H := H + K END;
        BEGIN NEW(G.A); G.B := 4; G.C := 5; X END.
        """;

    /// <summary>
    ///  A local a record moves to whole is that record, though the code otherwise uses only its first word, so the
    ///  locals after it keep their offsets.
    /// </summary>
    [TestMethod]
    public void LocalsMovedToWholeAreTheRecord()
    {
        string source = RoundTrip(WholeLocalSource);
        source.Should().Contain("A1: T");
    }

    // A pointer used both ways passed by value, and on by reference to a procedure that only reads it.
    private const string PlainReferenceSource = """
        PROGRAM PR;
        TYPE P = ^R;
          R = RECORD N: INTEGER; L: P END;
          W = RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (Q: P) END;
        VAR G: W; H: INTEGER;
        PROCEDURE MARK(VAR V: P); BEGIN V^.N := 5 END;
        PROCEDURE SHOW(V: P); VAR K: INTEGER; BEGIN MARK(V); K := 3; H := V^.N + ORD(V) + K END;
        BEGIN NEW(G.Q); SHOW(G.Q); G.I := G.I + 2; SHOW(G.Q) END.
        """;

    /// <summary>
    ///  A value parameter used both ways that is passed on to a VAR parameter is its pointer, as is the VAR one, so
    ///  that neither is a record to copy.
    /// </summary>
    [TestMethod]
    public void WordsUsedBothWaysPassByReferenceAsTheirPointers()
    {
        string source = RoundTrip(PlainReferenceSource);
        source.Should().Contain("(VAR A1: T");
    }

    // A procedure declared FORWARD before the body of another, in which one is nested: it is numbered first.
    private const string NumberingSource = """
        PROGRAM NU;
        VAR G: INTEGER;
        PROCEDURE A; FORWARD;
        PROCEDURE C; FORWARD;
        PROCEDURE A;
          PROCEDURE B; BEGIN G := G + 1 END;
        BEGIN B; C END;
        PROCEDURE C; BEGIN G := 2 END;
        BEGIN A END.
        """;

    /// <summary>
    ///  A procedure numbered before one nested in an earlier body has its heading before that body, as the Compiler
    ///  numbers a procedure at its first heading.
    /// </summary>
    [TestMethod]
    public void ProceduresNumberedBeforeNestedOnesAreDeclaredFirst()
    {
        string source = RoundTrip(NumberingSource);
        source.Should().Contain("PROCEDURE PROC2; FORWARD;\nPROCEDURE PROC3; FORWARD;\n");
    }

    // A move of a record's first words, which no field of the decompiled record is as long as.
    private const string MoveSource = """
        PROGRAM MV;
        TYPE R = RECORD
            CASE BOOLEAN OF
              TRUE: (H: ARRAY[1..3] OF INTEGER; K: INTEGER);
              FALSE: (A, B, C, D, E: INTEGER)
          END;
        VAR P, Q: ^R;
        BEGIN NEW(P); NEW(Q); P^.H := Q^.H; P^.E := 1; P^.A := 2 END.
        """;

    /// <summary>
    ///  A move of a record's first words, where no field is as long, moves a variant that views them as one array.
    /// </summary>
    [TestMethod]
    public void MovesOfARecordsFirstWordsViewThemAsAnArray()
    {
        string source = RoundTrip(MoveSource);
        source.Should().Contain("203: (B3N: ARRAY[1..3] OF INTEGER)").And.Contain(".B3N := ");
    }

    // A record whose variant has a field inside the words of another variant's real.
    private const string OverlapSource = """
        PROGRAM OV;
        TYPE R = RECORD N: INTEGER;
            CASE BOOLEAN OF
              TRUE: (X: REAL);
              FALSE: (L: INTEGER; S: PACKED ARRAY[0..3] OF CHAR)
          END;
        VAR P: ^R; C: CHAR;
        BEGIN NEW(P); P^.X := 1.5; C := P^.S[1]; P^.L := 2 END.
        """;

    /// <summary>
    ///  A field that starts inside a real before it is a variant's, so that it keeps its word.
    /// </summary>
    [TestMethod]
    public void FieldsInsideARealAreAnotherVariants()
    {
        string source = RoundTrip(OverlapSource);
        source.Should().Contain("0: (F1: REAL; F3: INTEGER); 1: (F1V1: INTEGER; F2: T3) END;");
    }

    // A word used both ways passed by value: the Compiler passes a pointer's word, where it would copy a record's.
    private const string PlainSource = """
        PROGRAM PL;
        TYPE P = ^R;
          R = RECORD N: INTEGER; L: P END;
          W = RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (Q: P) END;
        VAR G: W; H: INTEGER;
        PROCEDURE SHOW(V: P); BEGIN H := V^.N + ORD(V) END;
        BEGIN NEW(G.Q); G.Q^.N := 3; SHOW(G.Q); G.I := G.I + 2; SHOW(G.Q) END.
        """;

    /// <summary>
    ///  A value parameter whose word is used both ways is declared as its pointer, so that it is passed as the word
    ///  it is rather than as a record to copy, and its uses as an integer read it with ORD.
    /// </summary>
    [TestMethod]
    public void WordsUsedBothWaysPassByValueAsTheirPointers()
    {
        string source = RoundTrip(PlainSource);
        source.Should().Contain("ORD(A1)");
    }

    // A WITH of a field of the record of the WITH it is in, as the last statement that names the outer one's record.
    private const string FieldWithSource = """
        PROGRAM NW;
        TYPE P = ^R; R = RECORD N: PACKED ARRAY[1..8] OF CHAR; L: P; K: INTEGER END;
        VAR G: P;
        BEGIN
          NEW(G);
          WITH G^ DO
          BEGIN
            N := 'APPLE   '; NEW(L);
            WITH L^ DO
            BEGIN
              N := 'FALSE   '; NEW(L);
              WITH L^ DO BEGIN N := 'TRUE    '; K := 1; L := NIL END
            END
          END
        END.
        """;

    /// <summary>
    ///  A WITH whose record is a field of the record of the WITH it is in keeps its statements in its body, though they
    ///  come after the outer WITH's last use of its own temporary.
    /// </summary>
    [TestMethod]
    public void WithsOfFieldsNestInTheirRecordsWith()
    {
        string source = RoundTrip(FieldWithSource);
        source.Should().Contain(":= 'TRUE    ';");
    }

    // A record's first field, an array of bytes, indexed at the record's own address.
    private const string FirstArraySource = """
        PROGRAM FA;
        TYPE P = ^R; R = RECORD N: PACKED ARRAY[1..8] OF CHAR; L: P; K: INTEGER END;
        VAR G: P; I, S: INTEGER; C: PACKED ARRAY[1..8] OF CHAR;
        BEGIN
          NEW(G);
          WITH G^ DO BEGIN N := C; K := 2; FOR I := 1 TO 8 DO S := S + ORD(N[I]) END
        END.
        """;

    /// <summary>
    ///  An index of a record's address, where its first field is an array, indexes that field.
    /// </summary>
    [TestMethod]
    public void IndexesOfARecordIndexItsFirstField()
    {
        string source = RoundTrip(FirstArraySource);
        source.Should().Contain("ORD(F0[G5])");
    }

    // A function's result kept in a variable and passed by value, which never reaches a record.
    private const string KeptResultSource = """
        PROGRAM WF;
        VAR G: INTEGER;
        FUNCTION F: INTEGER; BEGIN F := G END;
        PROCEDURE Q(A, B: INTEGER; C: BOOLEAN); BEGIN IF C THEN G := A + B END;
        PROCEDURE R;
        VAR X: INTEGER;
        BEGIN X := F; Q(G, X, TRUE) END;
        BEGIN R END.
        """;

    /// <summary>
    ///  A word assigned a word and passed on, but never used to reach a record, is a variable, not a WITH's temporary.
    /// </summary>
    [TestMethod]
    public void WordsThatReachNoRecordAreNotWithTemporaries()
    {
        string source = RoundTrip(KeptResultSource);
        source.Should().NotContain("WITH");
    }

    // A program compiled as part of the system that keeps a copy of a system global's file pointer, and reads its file.
    private const string FileCopySource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF;
        VAR SYSCOM: INTEGER; IN1, OUT1, TERM1, SWAP: INTEGER; G6, G7: INTEGER; CODEF: FP;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR B: PACKED ARRAY[0..511] OF CHAR; N: INTEGER; W: FP;
        BEGIN
          MOVELEFT(CODEF, W, 2);
          N := BLOCKREAD(W^, B, 1, 0)
        END;
        BEGIN END.
        """;

    /// <summary>
    ///  A word of the program's own that it passes as a file is a pointer to a file, as the system's globals are.
    /// </summary>
    [TestMethod]
    public void WordsPassedAsFilesPointToFiles()
    {
        string source = RoundTrip(FileCopySource);
        source.Should().Contain("BLOCKREAD(G260^, ");
    }

    // Sets built of members the Compiler pushes one by one, constants among them that it did not fold.
    private const string SetMembersSource = """
        PROGRAM SG;
        VAR S: SET OF CHAR; C: CHAR; T: SET OF 0..255; I: INTEGER;
        BEGIN
          S := [CHR(13), C, ' '];
          T := [13, I, 32];
          T := [ORD(13), I, 32];
          S := [C, CHR(13)]
        END.
        """;

    /// <summary>
    ///  A constant the code pushes as a set's member, as for CHR(13), is written so that the Compiler does not fold it
    ///  into the set's constant.
    /// </summary>
    [TestMethod]
    public void PushedConstantMembersStayOutOfTheConstant()
    {
        string source = RoundTrip(SetMembersSource);
        source.Should().Contain("[ORD(13), ");
    }

    // A program compiled as part of the system that calls FOPEN, the system's procedure 5, itself, with NIL for its
    // last argument, where RESET and REWRITE pass 0, as Apple III Pascal 1.2's Compiler does.
    private const string OpenSource = """
        (*$U-*)
        PROGRAM PASCALSYSTEM;
        TYPE UF = FILE; FP = ^UF;
        VAR SYSCOM: INTEGER; IN1, OUT1, TERM1, SWAP: INTEGER; G6, G7: INTEGER; CODEF: FP;
        PROCEDURE P2; FORWARD;
        PROCEDURE P3; FORWARD;
        PROCEDURE P4; FORWARD;
        PROCEDURE OPEN(VAR F: UF; VAR S: STRING; OLD: INTEGER; J: FP); FORWARD;
        SEGMENT PROCEDURE COMPILER(Q, R: INTEGER);
        VAR S: STRING;
        BEGIN S := 'X'; OPEN(CODEF^, S, 1, NIL) END;
        BEGIN END.
        """;

    /// <summary>
    ///  FOPEN with other than 0 for its last argument is called as the system's procedure 5, its file by the system
    ///  global that points to it, and NIL as that pointer's type.
    /// </summary>
    [TestMethod]
    public void OpensWithNilCallTheSystemsProcedure()
    {
        string source = RoundTrip(OpenSource);
        source.Should().Contain("SYSTEM5(SYS8^, G3, 1, NIL)");
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

    /// <summary>
    ///  Compiles a probe with Apple Pascal 1.1's Compiler, or 1.0's, decompiles it, and checks the decompiled source
    ///  compiles to the same segments.
    /// </summary>
    /// <param name="probe">The probe's source.</param>
    /// <param name="version">The Compiler's version, 1.1 or 1.0, whose disks are named in capitals.</param>
    /// <returns>The decompiled source.</returns>
    internal static string RoundTrip(string probe, string version = "1.1") =>
        RoundTrip(probe, new PascalDecompilerOptions(), out _, version);

    /// <summary>
    ///  Compiles a probe with Apple Pascal 1.1's Compiler, or 1.0's, decompiles it with options, and checks the
    ///  decompiled source compiles to the same segments.
    /// </summary>
    /// <param name="probe">The probe's source.</param>
    /// <param name="options">The decompiler's options, such as hints.</param>
    /// <param name="warnings">The decompiler's warnings.</param>
    /// <param name="version">The Compiler's version, 1.1 or 1.0, whose disks are named in capitals.</param>
    /// <returns>The decompiled source.</returns>
    internal static string RoundTrip(string probe, PascalDecompilerOptions options, out IReadOnlyList<string> warnings, string version = "1.1")
    {
        string extension = version == "1.0" ? "DSK" : "dsk";
        string boot = Path.Join(PascalMediaTests.Apple2Disks, $"UCSD Pascal {version}_1.{extension}");
        string compiler = Path.Join(PascalMediaTests.Apple2Disks, $"UCSD Pascal {version}_2.{extension}");
        if (!File.Exists(boot) || !File.Exists(compiler))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal {version}'s disks.");
        }

        (byte[]? original, string compiled) = EmulatedPascalCompiler.Compile(probe, boot, compiler, s_inputs);
        if (original is null) { Assert.Fail($"The Compiler stopped:\n{compiled}"); }

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original), options);
        warnings = result.Warnings;
        if (options.Names.Count == 0) { result.Warnings.Should().BeEmpty(result.Source); }

        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, boot, compiler, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(code)).Should().BeEmpty(result.Source);
        return result.Source;
    }
}
