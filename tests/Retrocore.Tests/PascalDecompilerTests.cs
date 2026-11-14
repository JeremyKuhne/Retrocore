// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Decompiling Apple Pascal code files to Pascal that Apple Pascal's Compiler compiles to the same p-code.
/// </summary>
/// <remarks>
///  <para>
///   Two small programs written for these tests, compiled by Apple Pascal 1.1's Compiler, are kept here as code
///   files: P1 has functions, WHILE, FOR, CASE, booleans, reals and I/O; P2 has strings, records, arrays, sets,
///   packed arrays, pointers, a nested procedure and VAR and value parameters. With Apple Pascal's disks
///   (<c>RETROCORE_APPLE2_PASCAL_DISKS</c>), each sample program on APPLE3 is decompiled, compiled again by the
///   Compiler on an emulated Apple II, and compared with the original.
///  </para>
/// </remarks>
[TestClass]
public class PascalDecompilerTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Gets P1's code file, as Apple Pascal 1.1's Compiler wrote it.
    /// </summary>
    internal static byte[] P1Bytes => Convert.FromBase64String(P1Code);

    // P1, compiled by Apple Pascal 1.1:
    //
    //   PROGRAM P1;
    //   VAR I,J: INTEGER; B: BOOLEAN; C: CHAR; R: REAL;
    //   FUNCTION F(X: INTEGER): INTEGER;
    //   BEGIN
    //     F := X + 1
    //   END;
    //   FUNCTION G: BOOLEAN;
    //   BEGIN
    //     G := TRUE
    //   END;
    //   FUNCTION H(A, B: REAL): REAL;
    //   BEGIN
    //     H := A * B
    //   END;
    //   BEGIN
    //     I := F(3);
    //     WHILE I < 10 DO I := I + 2;
    //     FOR J := 10 DOWNTO 1 DO I := I - J;
    //     CASE I OF
    //       1: J := 5;
    //       3, 4: J := 6;
    //       7: BEGIN J := 7; I := 0 END
    //     END;
    //     B := G AND (I > 0) OR NOT (J = 5);
    //     IF B THEN C := 'A' ELSE C := CHR(I);
    //     R := H(1.5, I);
    //     WRITELN(I:4, C, R:6:2, ' ', ORD(C));
    //     READ(C); READLN(I, J);
    //     I := I DIV 3 MOD 2; I := -I; I := ABS(I); I := SQR(I);
    //     R := R / 2; I := TRUNC(R); I := ROUND(R);
    //     IF ODD(I) THEN I := SUCC(I) ELSE I := PRED(I)
    //   END.
    private static readonly string P1Code = string.Concat(
    [
        "AQCGAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAxICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgCoAHwYAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADaAYLMAa0BAAAABgAH",
        "AA4AAgEBzAGtAQAAAAQABwAMAAMBxgHGBbwCxgO8ApC9Aq0CAAAADAAHABYABAG58gMAAM4CqwTrCsmhB+sCgqsEufYKqwMBqwnq",
        "8MShDOvqlasE6gGVqwO59Ou5EgWrA7kiBqsDuR0HqwMAqwS5FawBAAcAuQ4ZAAQAGAAaAAoADAAbAAAAzgPrAMWE6gXDk42rBeyh",
        "BUGrBrkD66sGpQezAsA/AADrigAAzgS9ArYBA+sEzQANngC2AQPtAM0AEZ4AtgEDpQe8AgYCzR8EngC2AQMgAM0AEZ4AtgED7QDN",
        "AA2eALYBA80AFp4AtgECpQbNABCeALYBAqUEzQAMngC2AQKlA80ADJ4AtgECzQAVngDrA4YCjqsE65GrBOuAqwTrmKsEpQelB7wC",
        "AoqHvQKlB7wCnherBKUHvAKeGKsE66EH6wGCqwS5BesBlasEH54WuQUfnhW58MEAACwBCgAXASsBDgAEABkAPAEBAEIBXgFwAQgA",
        "AQQAAAAAAAAAAAAAAAAAAAAAAAARQVBQTEUxOlNZU1RFTS5XUksuVEVYVAAAAAAAAAAAAAAAAAAAAAAAAAATKlNZU1RFTS5XUksu",
        "Q09ERVsqXQAAAAASAAEAFkFQUExFMjpTWVNURU0uU1dBUERJU0sAAAAAAAAAAAAAAA=="
    ]);

    // P2, compiled by Apple Pascal 1.1:
    //
    //   (*$G+*)
    //   PROGRAM P2;
    //   LABEL 1;
    //   TYPE R = RECORD A: INTEGER; B: CHAR; C: REAL END;
    //        PR = ^R;
    //   VAR S, T: STRING; U: STRING[10]; I: INTEGER; C: CHAR;
    //       A: ARRAY[1..5, 0..3] OF INTEGER; X: R; P: PR;
    //       ST: SET OF 0..40; PA: PACKED ARRAY[0..9] OF CHAR;
    //       PB: PACKED ARRAY[1..8] OF 0..3;
    //   PROCEDURE Q(VAR V: INTEGER; W: R; Z: STRING);
    //   VAR K: INTEGER;
    //     PROCEDURE N;
    //     BEGIN
    //       K := V + 1; V := K
    //     END;
    //   BEGIN
    //     N; K := LENGTH(Z); W.A := K
    //   END;
    //   BEGIN
    //     S := 'HELLO'; T := CONCAT(S, ' THERE', U);
    //     I := POS('L', S); INSERT('X', S, 2); DELETE(S, 1, 2);
    //     C := S[1]; S[2] := 'Z';
    //     IF S = T THEN I := 1;
    //     IF S < 'ABC' THEN I := 2;
    //     A[I, 2] := A[3, I] + 1;
    //     WITH X DO BEGIN A := 1; B := 'Q'; C := 2.0 END;
    //     NEW(P); P^.A := X.A; P^ := X;
    //     ST := [1, 3, I..9]; IF I IN ST THEN ST := ST + [5] - [I];
    //     PA[I] := 'K'; C := PA[3]; PB[I] := 2; I := PB[2];
    //     Q(I, X, S);
    //     FILLCHAR(PA, 10, ' '); MOVELEFT(S, T, 5); I := SIZEOF(R);
    //     IF I > 0 THEN GOTO 1;
    //     I := 7;
    //   1: EXIT(P2)
    //   END.
    private static readonly string P2Code = string.Concat(
    [
        "AQCYAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAyICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC2AQP4AYK4ATG2AQO2",
        "ATGarQAAAAAABgAYAAMCxi3ZqATGBNiqUM4DxgQAvswxyjHMLa0AXAAGAAYAHgACAdfXpSzXpgVIRUxMT6pQpQMAq3+lf6UsUM0A",
        "F6V/pgYgVEhFUkXXVs0AF6V/pVVgzQAXpX+qUNemAUylLAAAzQAbq1umAVjXpSxQAs0AGKUsAQLNABqlLAGbvqtcpSwCm1q/pSyl",
        "A68EoQMBq1ulLKYDQUJD17UEoQMCq1ulXalbAQWIAZWkBAIAA4ikAaVdAwEFiAGVpASpWwADiKQB+AGCmgGrcVGrcqVzswIAQAAA",
        "vQKldQSeAal1qXGaqXWlcagEpXapWwmUCgGcoAO9A6lbpXa8AwOLoRKldqV2vAMDIAGcqVuXhaADvQOlealbAAmIS7+leQMACYi+",
        "q1ylfqlbAQiIAZXACAICAAOIu6V+AgEIiAGVwAgCuqtbpVulcaUszgKleQAKIJ4KpSwApQMABZ4CCKtbqVsAxaECuQMHq1sBAZ4E",
        "wQBaAQQABgBOAQEAdgFWAQYAAQMRQVBQTEUxOlNZU1RFTS5XUksuVEVYVAAAAAAAAAAAAAAAAAAAAAAAAAATKlNZU1RFTS5XUksu",
        "Q09ERVsqXQAAAAASAAEAFkFQUExFMjpTWVNURU0uU1dBUERJU0sAAAAAAAAAAAAAAA=="
    ]);

    // P3, compiled by Apple Pascal 1.1: a declared negative constant, and a pointer given an address by a variant
    // record.
    //
    //   PROGRAM P3;
    //   CONST M = -1;
    //   VAR X: INTEGER; F: BOOLEAN;
    //     R: RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (P: ^INTEGER) END;
    //   BEGIN
    //     X := M;
    //     X := -1;
    //     IF ODD(M) THEN X := 2;
    //     R.I := 15616;
    //     R.P^ := X
    //   END.
    private static readonly string P3Code = string.Concat(
    [
        "AQAuAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAzICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADX18cBAJGrAwGRqwPH",
        "AQCRoQMCqwPHAD2rBezqmsEAAAYABAAHACYAAQACAAEBNI5Gjj6O9o4FLkNPREVNLldSSy5DT0RFWypdXUlTSwAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANSNiKnWjRijYqkGo/Wpcg0KAPqNCQByDQoAFo4Y",
        "jhiOAqZiqV6kFo6IqRiOAqZiqbak9Y5yDQQAAAAAAAEAAAAGAAAABkFQUBaOYI4YjgKmYqmgpfcANg0AADYNXo5gjmCOUKliqQKp",
        "9/8AAAAA9o42DXINBAAKAAcA//8CABKXAAAHAAZBUFBMRTFUD1NZU1RFTS5XUksuQ09ERTYNvqoAAAAAeo6IqXyO0vN6/sfz9/sS",
        "jwAAAAD2jjYNAgCSjpKOiKmUjmKYuKAAmPmgAAAAAPaONg0SjyqQLJAskJKguKB/oPsABQAWQVBQTEUyOlNZU1RFTS5TV0FQRElT",
        "SwAAAAAAAAAAAAAAAAAAAAAAAAARQVBQTEUxOlNZU1RFTS5XUksuVEVYVAAAAAAAAAAAAAAAAAAAAAAAAAATKlNZU1RFTS5XUksu",
        "Q09ERVsqXQAAAAASAAEAFkFQUExFMjpTWVNURU0uU1dBUERJU0sAAAAAAAAAAAAAAA=="
    ]);

    /// <summary>
    ///  P1 decompiles to source with its functions, loops, CASE, expressions and I/O, which compiles to the same code.
    /// </summary>
    [TestMethod]
    public void FunctionsLoopsAndIoDecompile()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(Convert.FromBase64String(P1Code)));
        result.Warnings.Should().BeEmpty();
        result.Source.Split('\n').Should().Equal(
        "PROGRAM P1;",
        "VAR",
        "  G3: INTEGER;",
        "  G4: INTEGER;",
        "  G5: BOOLEAN;",
        "  G6: CHAR;",
        "  G7: REAL;",
        "FUNCTION FUNC2(A3: INTEGER): INTEGER;",
        "BEGIN",
        "  FUNC2 := A3 + 1",
        "END;",
        "FUNCTION FUNC3: BOOLEAN;",
        "BEGIN",
        "  FUNC3 := TRUE",
        "END;",
        "FUNCTION FUNC4(A5: REAL; A3: REAL): REAL;",
        "BEGIN",
        "  FUNC4 := A5 * A3",
        "END;",
        "BEGIN",
        "  G4 := FUNC2(3);",
        "  WHILE G4 < 10 DO",
        "    G4 := G4 + 2;",
        "  FOR G3 := 10 DOWNTO 1 DO",
        "    G4 := G4 - G3;",
        "  CASE G4 OF",
        "    1:",
        "      G3 := 5;",
        "    3, 4:",
        "      G3 := 6;",
        "    7:",
        "    BEGIN",
        "      G3 := 7;",
        "      G4 := 0",
        "    END",
        "  END;",
        "  G5 := FUNC3 AND (G4 > 0) OR NOT (G3 = 5);",
        "  IF G5 THEN",
        "    G6 := 'A'",
        "  ELSE",
        "    G6 := CHR(G4);",
        "  G7 := FUNC4(1.5, G4);",
        "  WRITELN(G4:4, G6, G7:6:2, ' ', ORD(G6));",
        "  READLN(G6, G4, G3);",
        "  G4 := G4 DIV 3 MOD 2;",
        "  G4 := -G4;",
        "  G4 := ABS(G4);",
        "  G4 := SQR(G4);",
        "  G7 := G7 / 2;",
        "  G4 := TRUNC(G7);",
        "  G4 := ROUND(G7);",
        "  IF ODD(G4) THEN",
        "    G4 := G4 + 1",
        "  ELSE",
        "    G4 := G4 - 1",
        "END.",
        "");
    }

    /// <summary>
    ///  P2 decompiles with its types laid out as the code uses them: string lengths from CONCAT, a record from the
    ///  value parameter's copy, a set's words, and packed arrays by byte and by bits.
    /// </summary>
    [TestMethod]
    public void StringsRecordsSetsAndPackedArraysDecompile()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(Convert.FromBase64String(P2Code)));
        result.Warnings.Should().BeEmpty();
        string source = result.Source;
        source.Should().Contain("G85: STRING[10];");
        source.Should().Contain("T3 = RECORD F0: INTEGER; F1: INTEGER; F2: REAL END;");
        source.Should().Contain("G117: T4;");
        source.Should().Contain("G3 := CONCAT(G44, ' THERE', G85);");
        source.Should().Contain("T5 = SET OF 0..47;");
        source.Should().Contain("T6 = PACKED ARRAY[0..9] OF CHAR;");
        source.Should().Contain("T7 = PACKED ARRAY[1..8] OF 0..3;");
        source.Should().Contain("PROCEDURE PROC2(VAR A3: INTEGER; A2: T3; A1: STRING);");
        source.Should().Contain("G93[G91, 2] := G93[3, G91] + 1;");
        source.Should().Contain("G118 := [G91..9, 1, 3];");
        source.Should().Contain("G118 := G118 + [5] - [G91];");
    }

    /// <summary>
    ///  P3 decompiles to a CONST for the negative constant the Compiler loaded by LDCI, where <c>-1</c> written in place
    ///  loads by SLDC, and to a variant record for the pointer a number is stored in.
    /// </summary>
    [TestMethod]
    public void DeclaredConstantsAndAddressesDecompile()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(Convert.FromBase64String(P3Code)));
        result.Warnings.Should().BeEmpty();
        string source = result.Source;
        source.Should().Contain("CONST\n  NEG1 = -1;\nTYPE");
        source.Should().Contain("G3 := NEG1;").And.Contain("G3 := -1;").And.Contain("IF ODD(NEG1) THEN");
        source.Should().Contain("T1 = RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (P: ^INTEGER) END;");
        source.Should().Contain("G5.I := 15616;").And.Contain("G5.P^ := G3");
    }

    /// <summary>
    ///  FORMATTER, whose segment the Linker marked M6502 for its assembled procedure, decompiles with that procedure
    ///  declared EXTERNAL, as a function of the parameters its call passes; Apple Pascal 1.1's Compiler compiles the
    ///  source to the same p-code, and only the assembled procedure, which the Linker would add, differs.
    /// </summary>
    [TestMethod]
    public void AssembledProceduresDecompileAsExternal()
    {
        string samples = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_3.dsk");
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string compiler = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(samples) || !File.Exists(boot) || !File.Exists(compiler))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(samples), proDosOrder: false).ReadFile("FORMATTER.CODE");
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        result.Source.Should().Contain("FUNCTION FUNC2(A4: INTEGER; A3: INTEGER): BOOLEAN;\n  EXTERNAL;");
        result.Source.Should().Contain("G3 := FUNC2(G8, G7);");

        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, boot, compiler, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }

        // The assembled procedure's code is last in the segment, so the p-code before it is the same.
        IReadOnlyList<string> differences = PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(code));
        differences.Should().Contain(difference => difference.StartsWith("FORMATTE: the code differs from $055C in FORMATTE.2:", StringComparison.Ordinal));
    }

    /// <summary>
    ///  A unit's interface text gives its procedures in the order calls number them, from 2, and its enumerated types.
    /// </summary>
    [TestMethod]
    public void UnitInterfacesNumberTheirProcedures()
    {
        PascalUnit unit = PascalUnit.Parse("TURTLEGR", 20, """
            TYPE SCREENCOLOR=(none,white,black);
            PROCEDURE INITTURTLE;
            PROCEDURE MOVETO(X,Y: INTEGER);
            (* A comment *) PROCEDURE PENCOLOR(PENMODE: SCREENCOLOR);
            FUNCTION  TURTLEX: INTEGER;
            PROCEDURE DRAWBLOCK(VAR SOURCE; ROWSIZE: INTEGER);
            """);

        unit.UsesName.Should().Be("TURTLEGRAPHICS");
        unit.Enumerations["SCREENCOLOR"].Should().Equal("NONE", "WHITE", "BLACK");
        unit.Procedures.Select(procedure => procedure.Name).Should().Equal("INITTURTLE", "MOVETO", "PENCOLOR", "TURTLEX", "DRAWBLOCK");
        unit.Procedure(2).Should().Be(unit.Procedures[0]);
        unit.Procedures[1].Parameters.Select(parameter => parameter.Name).Should().Equal("X", "Y");
        unit.Procedures[2].Parameters.Single().Type.Should().Be("SCREENCOLOR");
        unit.Procedures[3].Should().Match<PascalUnitProcedure>(procedure => procedure.IsFunction && procedure.Result == "INTEGER");
        unit.Procedures[4].Parameters[0].IsReference.Should().BeTrue();
        unit.Procedures[4].Parameters[0].Type.Should().BeNull("an untyped VAR parameter has no type");
        unit.Procedure(7).Should().BeNull();
    }

    /// <summary>
    ///  Code files compare by their segments: the same code is the same, a different byte is reported with the
    ///  p-code there, and the byte skipped to align an operand is not compared.
    /// </summary>
    [TestMethod]
    public void CodeFilesCompareBySegments()
    {
        byte[] original = Convert.FromBase64String(P1Code);
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(original)).Should().BeEmpty();

        // P1's procedure 2, FUNC2, starts at block 1: SLDL3 SLDC 1 ADI. Changing SLDC 1 to SLDC 2 is a difference.
        byte[] changed = (byte[])original.Clone();
        changed[512 + 1] = 2;
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(changed))
            .Should().Contain(line => line.Contains("differs from $0001 in P1.2", StringComparison.Ordinal));
    }

    /// <summary>
    ///  Text written as a text file reads back the same, its indentation packed.
    /// </summary>
    [TestMethod]
    public void TextFilesWriteAndReadBack()
    {
        string text = "PROGRAM X;\nBEGIN\n    WRITELN('HI')\nEND.\n";
        byte[] file = PascalTextFile.Write(text);
        (file.Length % 1024).Should().Be(0);
        file.AsSpan(1024).IndexOf((byte)0x10).Should().BeGreaterThan(0, "indentation is packed as DLE and a count");
        PascalTextFile.Read(file).Should().Be(text);
    }

    /// <summary>
    ///  A file written onto a Pascal volume takes the first free blocks, and replaces one of the same name.
    /// </summary>
    [TestMethod]
    public void FilesWriteOntoAPascalVolume()
    {
        byte[] image = EmptyVolume("TEST");
        PascalVolume.WriteFile(image, proDosOrder: false, "A.TEXT", PascalFileKind.Text, new byte[1100]);
        PascalVolume.WriteFile(image, proDosOrder: false, "B.CODE", PascalFileKind.Code, [1, 2, 3]);
        PascalVolume.WriteFile(image, proDosOrder: false, "a.text", PascalFileKind.Text, [4]);

        PascalVolume volume = PascalVolume.Read(image, proDosOrder: false);
        volume.Files.Select(file => (file.Name, file.FirstBlock, file.NextBlock)).Should().Equal(
            ("A.TEXT", 6, 7),
            ("B.CODE", 9, 10));

        volume.ReadFile("A.TEXT").Should().Equal(4);
        volume.ReadFile("B.CODE").Should().Equal(1, 2, 3);
    }

    /// <summary>
    ///  A file deleted from a Pascal volume leaves its directory and its blocks free; one that is not there is not
    ///  deleted.
    /// </summary>
    [TestMethod]
    public void FilesDeleteFromAPascalVolume()
    {
        byte[] image = EmptyVolume("TEST");
        PascalVolume.WriteFile(image, proDosOrder: false, "A.TEXT", PascalFileKind.Text, new byte[1100]);
        PascalVolume.WriteFile(image, proDosOrder: false, "B.CODE", PascalFileKind.Code, [1, 2, 3]);

        PascalVolume.DeleteFile(image, proDosOrder: false, "a.text").Should().BeTrue();
        PascalVolume.DeleteFile(image, proDosOrder: false, "C.CODE").Should().BeFalse();
        PascalVolume.Read(image, proDosOrder: false).Files.Select(file => file.Name).Should().Equal("B.CODE");

        PascalVolume.WriteFile(image, proDosOrder: false, "D.TEXT", PascalFileKind.Text, [4]);
        PascalVolume.Read(image, proDosOrder: false).Files.Single(file => file.Name == "D.TEXT").FirstBlock.Should().Be(6);
    }

    /// <summary>
    ///  Each sample program with its source on APPLE3, and the BINDER utility, decompile to source that Apple Pascal
    ///  1.1's Compiler compiles to the same code; only the byte a word-aligned operand skips may differ.
    /// </summary>
    /// <param name="name">The program's code file, without <c>.CODE</c>.</param>
    [TestMethod]
    [DataRow("HILBERT")]
    [DataRow("TREE")]
    [DataRow("BALANCED")]
    [DataRow("CROSSREF")]
    [DataRow("DISKIO")]
    [DataRow("GRAFDEMO")]
    [DataRow("GRAFCHARS")]
    [DataRow("SPIRODEMO")]
    [DataRow("LINEFEED")]
    [DataRow("BINDER")]
    public void SamplesRecompileToTheSameCode(string name)
    {
        string samples = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_3.dsk");
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string compiler = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(samples) || !File.Exists(boot) || !File.Exists(compiler))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(samples), proDosOrder: false).ReadFile(name + ".CODE");
        PascalLibrary library = PascalLibrary.Read(PascalVolume.Read(File.ReadAllBytes(boot), proDosOrder: false).ReadFile("SYSTEM.LIBRARY"));
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original), library);
        result.Warnings.Should().BeEmpty();

        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, boot, compiler, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(code)).Should().BeEmpty(result.Source);
    }

    // A 140K image with an empty Pascal volume: its directory header in block 2, of 280 blocks.
    private static byte[] EmptyVolume(string name)
    {
        byte[] header = new byte[512];
        header[2] = 6;
        header[6] = (byte)name.Length;
        System.Text.Encoding.ASCII.GetBytes(name).CopyTo(header, 7);
        header[14] = 280 & 0xFF;
        header[15] = 280 >> 8;

        // In DOS order, block 2 is track 0's sectors 11 and 10 (ProDOS sectors 4 and 5).
        byte[] image = new byte[143_360];
        header.AsSpan(0, 256).CopyTo(image.AsSpan(11 * 256));
        header.AsSpan(256, 256).CopyTo(image.AsSpan(10 * 256));
        return image;
    }
}
