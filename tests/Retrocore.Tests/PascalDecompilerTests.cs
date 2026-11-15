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

    // P4, compiled by Apple III Pascal 1.1: UNITSTATUS, its CSP 12, and SCAN, into a word array and a packed one.
    //
    //   PROGRAM T;
    //   VAR B: ARRAY[0..19] OF INTEGER; N, I: INTEGER; C: CHAR;
    //     S: PACKED ARRAY[0..40] OF CHAR;
    //   BEGIN
    //     UNITSTATUS(0, B, 0);
    //     UNITSTATUS(N, B[3], 5);
    //     I := SCAN(41, = CHR(N), B);
    //     I := SCAN(-10, <> C, S[2]);
    //     I := SCAN(N, = 'A', S)
    //   END.
    private static readonly string P4Code = string.Concat(
    [
        "AQBQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFQgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGCAIIAggCCAIIAggCCAIIAggCCAIIAggCCAIIAggCCAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADX1wClAwAAngypGKUD",
        "AwATiKQBAAWeDCkAqRilAwAAngurFwqRAakZpRoCACiIAJ4LqxepGABBpRoAAJ4LqxfBAABYAAQABwBIAAEAAgABAXBpbGluZy4u",
        "LiBa9Vr1qPWo9ZJL3Et/S/mDBwAOV09SSzpIT1NULkNPREVERVsqXXSAD1zzgwAAoPlKAR0ASgG+90r1el50gG9e9YNFAET5SgFq",
        "9CdDb3B5cmlnaHQgQXBwbGUgQ29tcHV0ZXIgBFdPUks6SE9TVC5DT0RFWFT0E0N1cnJlbnQgIGRhdGUgIGlzICBjVrT0LHxfX19f",
        "X19fX19fX19fX19fX19fX19fX19fX19fX19fX19fX19fXxBXT1JLOlNPVVJDRS5URVhUICAgIEFwcGxlICAvLy8gIFBhc2NhbCAg",
        "IDEuMSAgICAgICAgIHwBtVUAACsgX19fX19fX19fX19fX19fX19fX18EAAAAAgABAABXT1JL9RJ5dIDrePODAAEBAC71SgFKAQAA",
        "NvW+9zr1cl10gEoBSgEAAEb1vvdK9axddICWXfWDHQADACD+WvVa9b73qPWSS9xLjEn3gyD+Xv41SQAARUNvbW1hbmQ6IEUoZGl0",
        "LCBSKHVuLCBGKGlsZSwgQyhvbXAsIEwoaW5rLCBYKGVjdXRlLCBBAACm9cT1qvUaCg=="
    ]);

    // P5, built by Apple III Pascal 1.1's Compiler, Assembler and Linker: a program, USER, that uses two units of its own,
    // ALPHA (AlphaSource) and BETA (BetaSource), BETA's ADD1 assembled (Add1Source).
    private static readonly string P5Code = string.Concat(
    [
        "AwBGAAEAPAACAFwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFVTRVIgICAgQUxQ",
        "SEEgICBCRVRBICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg",
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGCB4IIhwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAzAMDzATa28ihENna",
        "AAOIpAHYmtoBgswDufatAAAYAAQABAAJACYAAgGtAAAAAAAGAAgAAQEOAAQABwI6IEJVRjsgTjogSU5URUdFUik7DUlNUExFTUVO",
        "VEFUSU9OICAgICAgICBFIE9SSzpIT1NULkNPREVERVsqXXSAD1zzgwAAoPlKAR0ASgG+9z71el50gG9e9YNFAET5SgF0gG9e9YNF",
        "AET5SgFq9CdDb3B5cmlnaHQgQXBwBFdPUks6SE9TVC5DT0RFWFQxOTgxLTE5ODMJV4L0E0N1cnJlbnQgIGRhdGUgIGlzICBjVrT0",
        "LHxfX19fX19fX19fX19fX19fX19fX19fX19fXxBXT1JLOlNPVVJDRS5URVhUAAAAAAADACAgICAgICAgIEFwcGxlICAvLy8gIFBh",
        "c2NhbCAgIDEuMSAgICAgICAgIHwBtVUAACsgX19fX19fX18EAAAAAgABAABXT1JL9RJ5dIDrePODAAEBACL1SgFKAQAAKvW+9y71",
        "cl10gEoBSgEAADr1vvc+9axddICWXfWDHQADACD+TvVO9b73nPWSS9xLjEn3gyD+Xv41SQAARUNvbW1hbmQ6IEUoZGl0LCBSKHVu",
        "LCBGKGlsZSwgQyhvbXAsIEwoaW5rLCBYKGVjdXRlLCBBKHNzZW0sAACg9cT1pPUaCtoCj8wBrQEAAAAGAAcADgADAa0AAAAAAAYA",
        "CAABAWiNIABojSEAaGhoaGgYaQGqaGkASIpIrSEASK0gAEhgAAAAACIAIAAQAA4ABAAAAAAAMgAAAEQABAA8AAgDICAgICAgICBF",
        "IA5XT1JLOkhPU1QuQ09ERURFWypddIAPXPODAACg+UoBHQBKAb73PvV6XnSAb171g0UARPlKAXSAb171g0UARPlKAWr0J0NvcHly",
        "aWdodCBBcHAEV09SSzpIT1NULkNPREVYVDE5ODEtMTk4MwlXgvQTQ3VycmVudCAgZGF0ZSAgaXMgIGNWtPQsfF9fX19fX19fX19f",
        "X19fX19fX19fX19fX19fEFdPUks6U09VUkNFLlRFWFQAAAAAAAMAICAgICAgICAgQXBwbGUgIC8vLyAgUGFzY2FsICAgMS4xICAg",
        "ICAgICAgfAG1VQAAKyBfX19fX19fXwQAAAACAAEAAFdPUkv1Enl0gOt484MAAQEAIvVKAUoBAAAq9b73LvVyXXSASgFKAQAAOvW+",
        "9z71rF10gJZd9YMdAAMAIP5O9U71vvec9ZJL3EuMSfeDIP5e/jVJAABFQ29tbWFuZDogRShkaXQsIFIodW4sIEYoaWxlLCBDKG9t",
        "cCwgTChpbmssIFgoZWN1dGUsIEEoc3NlbSwAAKD1xPWk9RoKuSnNBwHNCAGlAwXNBwKlAwIAA4ikAfgAAM0IAgAAzQgDqwcInhYH",
        "nha5CAeeFQieFbn2wQAANAAKAAQAGQA+AAEAAgABAQ1Db21waWxpbmcuLi4gTvVO9Zz1nPWSS9xLf0v5gwcADldPUks6SE9TVC5D",
        "T0RFREVbKl10gA9c84MAAKD5SgEdAEoBvvc+9XpedIBvXvWDRQBE+UoBdIBvXvWDRQBE+UoBavQnQ29weXJpZ2h0IEFwcARXT1JL",
        "OkhPU1QuQ09ERVhUMTk4MS0xOTgzCVeC9BNDdXJyZW50ICBkYXRlICBpcyAgY1a09Cx8X19fX19fX19fX19fX19fX19fX19fX19f",
        "X18QV09SSzpTT1VSQ0UuVEVYVAAAAAAAAwAgICAgICAgICBBcHBsZSAgLy8vICBQYXNjYWwgICAxLjEgICAgICAgICB8AbVVAAAr",
        "IF9fX19fX19fBAAAAAIAAQAAV09SS/USeXSA63jzgwABAQAi9UoBSgEAACr1vvcu9XJddIBKAUoBAAA69b73PvWsXXSAll31gx0A",
        "AwAg/k71TvW+95z1kkvcS4xJ94Mg/l7+NUkAAEVDb21tYW5kOiBFKGRpdCwgUih1biwgRihpbGUsIEMob21wLCBMKGluaywgWChl",
        "Y3V0ZSwgQShzc2VtLAAAoPXE9aT1Ggo="
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
    ///  FORMATTER, whose segment the Linker marked M6502 for its assembled procedure, decompiles to Pascal, with that
    ///  procedure declared EXTERNAL as a function of the parameters its call passes, and to source for the Assembler
    ///  for the procedure; compiled, assembled and linked with Apple Pascal 1.1's own tools, they make the same code
    ///  file, byte for byte.
    /// </summary>
    [TestMethod]
    public void FormatterRebuildsByteForByte()
    {
        string samples = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_3.dsk");
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(samples) || !File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(samples), proDosOrder: false).ReadFile("FORMATTER.CODE");
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        result.Source.Should().Contain("FUNCTION FUNC2(A4: INTEGER; A3: INTEGER): BOOLEAN;\n  EXTERNAL;");
        result.Source.Should().Contain("G3 := FUNC2(G8, G7);");
        result.Source.Should().EndWith("END.\n(* Alignment bytes FORMATTE $009F=$54 $00C9=$02 $03E1=$10 $046F=$30 *)\n");
        result.Assembly.Should().StartWith("         .FUNC   FUNC2,2\n         PLA\n         STA     L003E\n");
        result.Assembly.Should().Contain("         JSR     3D00\n").And.Contain("L003C    .WORD   L0040\n").And.EndWith("         .END\n");

        (byte[]? host, string compiled) = EmulatedPascalCompiler.Compile(result.Source, boot, tools, s_inputs);
        if (host is null) { Assert.Fail($"The Compiler stopped:\n{compiled}\n{result.Source}"); }

        (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(result.Assembly ?? "", boot, tools, s_inputs);
        if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}\n{result.Assembly}"); }

        (byte[]? linked, string linking) = EmulatedPascalTools.Link(host, [assembled], boot, tools, s_inputs);
        if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }
        linked.Should().Equal(original);
    }

    /// <summary>
    ///  Hints name procedures, parameters and variables, and comment procedures; a name that would change what the
    ///  source compiles to is left as the decompiler names it, with a warning: a predeclared name the code calls, one
    ///  the same as another in its first eight letters, the Compiler's, and a program's that is not its segment's.
    /// </summary>
    [TestMethod]
    public void HintsNameAndCommentTheSource()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(P1Bytes), new PascalDecompilerOptions
        {
            Names = new Dictionary<string, string>
            {
                ["P1.1"] = "Other",
                ["P1.2"] = "Next",
                ["P1.2@3"] = "X",
                ["P1.4@5"] = "A",
                ["P1.4@$3"] = "B",
                ["P1.1@3"] = "Counter1A",
                ["P1.1@4"] = "IoResult",
                ["P1.1@5"] = "Counter1B",
                ["P1.1@6"] = "Begin"
            },
            Comments = new Dictionary<string, string> { ["P1.4"] = "Multiplies (*reals*)." }
        });

        string source = result.Source;
        source.Should().StartWith("PROGRAM P1;");
        source.Should().Contain("FUNCTION Next(X: INTEGER): INTEGER;\nBEGIN\n  Next := X + 1\nEND;");
        source.Should().Contain("(* Multiplies (*reals* ). *)\nFUNCTION FUNC4(A: REAL; B: REAL): REAL;");
        source.Should().Contain("  Counter1A: INTEGER;\n  G4: INTEGER;\n  G5: BOOLEAN;\n  G6: CHAR;");
        source.Should().Contain("G4 := Next(3);");
        result.Warnings.Should().Contain(warning => warning.Contains("Other for P1.1 is not its segment's name", StringComparison.Ordinal));
        result.Warnings.Should().Contain(warning => warning.Contains("IoResult for P1.1@4 would clash with IORESULT", StringComparison.Ordinal));
        result.Warnings.Should().Contain(warning => warning.Contains("Counter1B for P1.1@5 would clash with Counter1A", StringComparison.Ordinal));
        result.Warnings.Should().Contain(warning => warning.Contains("Begin for P1.1@6 would clash with BEGIN", StringComparison.Ordinal));
    }

    /// <summary>
    ///  With the listing the Compiler wrote of HILBERT's own source, its decompilation names its procedures and
    ///  variables as the source did, nested procedures' too, and still compiles to the same code.
    /// </summary>
    [TestMethod]
    public void AListingNamesTheSource()
    {
        string samples = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_3.dsk");
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string compiler = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(samples) || !File.Exists(boot) || !File.Exists(compiler))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        PascalVolume volume = PascalVolume.Read(File.ReadAllBytes(samples), proDosOrder: false);
        string original = PascalTextFile.Read(volume.ReadFile("HILBERT.TEXT"));
        (_, string screen, string? text) = EmulatedPascalCompiler.CompileWithListing(
            $"(*$L APPLE1:HIL.LST.TEXT*)\n{original}",
            boot,
            compiler,
            "HIL.LST.TEXT",
            s_inputs);

        if (text is null) { Assert.Fail($"The Compiler wrote no listing:\n{screen}"); }

        byte[] code = volume.ReadFile("HILBERT.CODE");
        PascalLibrary library = PascalLibrary.Read(PascalVolume.Read(File.ReadAllBytes(boot), proDosOrder: false).ReadFile("SYSTEM.LIBRARY"));
        PascalDecompilation result = PascalDecompiler.Decompile(
            PascalCodeFile.Read(code),
            new PascalDecompilerOptions { Library = library, Listing = PascalListing.Parse(text) });

        result.Warnings.Should().BeEmpty();
        result.Source.Should().Contain("PROCEDURE HIL(I: INTEGER);\n  VAR\n    B: INTEGER;\n    A: INTEGER;\n  PROCEDURE HIL1;");
        result.Source.Should().Contain("FOR N := 2 TO ORDER DO");

        (byte[]? recompiled, string stopped) = EmulatedPascalCompiler.Compile(result.Source, boot, compiler, s_inputs);
        if (recompiled is null) { Assert.Fail($"The Compiler stopped:\n{stopped}\n{result.Source}"); }
        PascalCodeComparison.Compare(PascalCodeFile.Read(code), PascalCodeFile.Read(recompiled)).Should().BeEmpty(result.Source);
    }

    /// <summary>
    ///  A program that calls a 6502 function, compiled, assembled and linked with Apple's own Compiler, Assembler and
    ///  Linker, decompiles to Pascal and to source for the Assembler that compile, assemble and link back to the same
    ///  bytes, file and all.
    /// </summary>
    [TestMethod]
    public void LinkedProgramsRebuildByteForByte()
    {
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        (byte[]? function, string assembled) = EmulatedPascalTools.Assemble(Add1Source, boot, tools, s_inputs);
        if (function is null) { Assert.Fail($"The Assembler stopped:\n{assembled}"); }

        byte[] linked = Build(LinkedSource);
        PascalCodeFile file = PascalCodeFile.Read(linked);
        file.Segments.Single(segment => segment.Code.Length > 0).Procedure(2).Should().Match<PascalProcedure>(procedure => procedure.IsNative);

        // The linked file keeps no name for the function, so the source and the Assembler's both call it FUNC2.
        PascalDecompilation result = PascalDecompiler.Decompile(file);
        result.Source.Should().Contain("FUNCTION FUNC2(A3: INTEGER): INTEGER;\n  EXTERNAL;").And.Contain("G3 := FUNC2(41)");
        result.Assembly.Should().StartWith("         .FUNC   FUNC2,1\n");

        (byte[]? generated, string regenerated) = EmulatedPascalTools.Assemble(result.Assembly ?? "", boot, tools, s_inputs);
        if (generated is null) { Assert.Fail($"The Assembler stopped:\n{regenerated}\n{result.Assembly}"); }
        Build(result.Source, generated).Should().Equal(linked);

        byte[] Build(string source, byte[]? assembled = null)
        {
            (byte[]? host, string screen) = EmulatedPascalCompiler.Compile(source, boot, tools, s_inputs);
            if (host is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{source}"); }

            (byte[]? code, string linking) = EmulatedPascalTools.Link(host, [assembled ?? function], boot, tools, s_inputs);
            if (code is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }
            return code;
        }
    }

    /// <summary>
    ///  Two 6502 procedures that share a label and call each other through the segment, one of which reaches the host's
    ///  global, built with Apple Pascal 1.1's tools, decompile to Pascal and Assembler source with <c>.DEF</c>,
    ///  <c>.REF</c> and <c>.PUBLIC</c> that build back to the same bytes.
    /// </summary>
    [TestMethod]
    public void SharedNamesRebuildByteForByte()
    {
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_2.dsk");
        if (!File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] linked = Build(SharedPascal, SharedAssembly, boot, tools);
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(linked));
        result.Assembly.Should().Contain("         .REF    D").And.Contain(",PROC3\n").And.Contain("         .PUBLIC G3\n");
        result.Assembly.Should().Contain("         .DEF    D").And.Contain("         JSR     PROC3\n");
        Build(result.Source, result.Assembly ?? "", boot, tools).Should().Equal(linked);
    }

    /// <summary>
    ///  A 6502 procedure that reaches the interpreter, built with Apple Pascal 1.2's tools, whose interpreter moves,
    ///  decompiles to Assembler source with <c>.INTERP</c> that builds back to the same bytes.
    /// </summary>
    [TestMethod]
    public void InterpreterWordsRebuildByteForByte()
    {
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.2_1.DSK");
        string tools = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.2_2.DSK");
        if (!File.Exists(boot) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.2's disks.");
        }

        byte[] linked = Build(InterpreterPascal, InterpreterAssembly, boot, tools);
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(linked));
        result.Assembly.Should().Contain("         LDA     .INTERP+2\n").And.Contain("         JMP     @.INTERP\n");
        Build(result.Source, result.Assembly ?? "", boot, tools).Should().Equal(linked);
    }

    // A program compiled, its assembled procedures assembled, and the two linked, with the tools on the disks.
    private static byte[] Build(string pascal, string assembly, string boot, string tools)
    {
        (byte[]? host, string compiled) = EmulatedPascalCompiler.Compile(pascal, boot, tools, s_inputs);
        if (host is null) { Assert.Fail($"The Compiler stopped:\n{compiled}\n{pascal}"); }

        (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, boot, tools, s_inputs);
        if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}\n{assembly}"); }

        (byte[]? linked, string linking) = EmulatedPascalTools.Link(host, [assembled], boot, tools, s_inputs);
        if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }
        return linked;
    }

    private const string SharedPascal = """
        PROGRAM SHARED;
        VAR COUNT: INTEGER;
        PROCEDURE LEFT; EXTERNAL;
        PROCEDURE RIGHT; EXTERNAL;
        BEGIN
          COUNT := 7;
          LEFT;
          RIGHT
        END.
        """;

    private const string SharedAssembly = """
                .PROC   LEFT
                .REF    FLAG,RIGHT
                .PUBLIC COUNT
                LDA     COUNT
                STA     FLAG
                JSR     RIGHT
                RTS
                .PROC   RIGHT
                .DEF    FLAG
                RTS
        FLAG    .BYTE   0
                .END
        """;

    private const string InterpreterPascal = """
        PROGRAM INTERP;
        PROCEDURE PEEK; EXTERNAL;
        BEGIN
          PEEK
        END.
        """;

    private const string InterpreterAssembly = """
                .PROC   PEEK
                LDA     .INTERP+2
                JMP     @.INTERP
                .END
        """;

    /// <summary>
    ///  The same program and 6502 function, built with Apple III Pascal 1.1's own Compiler, Assembler and Linker on an
    ///  emulated Apple III, decompile to Pascal and Assembler source that build back to the same bytes there.
    /// </summary>
    [TestMethod]
    public void Apple3LinkedProgramsRebuildByteForByte()
    {
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        string tools = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk2.dsk");
        if (!File.Exists(system) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE3_DISKS to a folder with Apple III Pascal 1.1's disks.");
        }

        byte[] linked = Build(LinkedSource, Add1Source, system, tools);
        PascalCodeFile file = PascalCodeFile.Read(linked);
        PascalSegment segment = file.Segments.Single(own => own.Code.Length > 0);
        segment.Version.Should().Be(4, "Apple III Pascal 1.1's");
        segment.Procedure(2).Should().Match<PascalProcedure>(procedure => procedure.IsNative);

        PascalDecompilation result = PascalDecompiler.Decompile(file);
        result.Assembly.Should().StartWith("         .FUNC   FUNC2,1\n");
        Build(result.Source, result.Assembly ?? "", system, tools).Should().Equal(linked);
    }

    /// <summary>
    ///  The alignment bytes a decompiled source records after its <c>END.</c> are put back in the segment it names,
    ///  where the Compiler left 0.
    /// </summary>
    [TestMethod]
    public void AlignmentBytesArePutBack()
    {
        byte[] code = new byte[1024];
        code[0] = 1;
        code[2] = 0x10;
        "TEST    "u8.CopyTo(code.AsSpan(0x40));
        code[512 + 0x0B] = 0x77;

        EmulatedPascalCompiler.RestoreAlignment(code, "END.\n(* Alignment bytes TEST $0009=$54 $000B=$02 *)\n").Should().Be(1);
        code[512 + 0x09].Should().Be(0x54);
        code[512 + 0x0B].Should().Be(0x77, "a byte the Compiler wrote is its own");
    }

    /// <summary>
    ///  A source too long for two volumes' halves is cut before outer procedures into pieces: the main file on SOURCE:
    ///  includes the others where they were, each on SOURCE: while it fits, then on CODE:, and together they are the
    ///  source again.
    /// </summary>
    [TestMethod]
    public void ALongSourceIsIncludedInPieces()
    {
        string body = string.Concat(Enumerable.Repeat("    X := X + 1; (* a comment that makes the procedure long enough *)\n", 50));
        string source = "PROGRAM LONG;\nSEGMENT PROCEDURE S;\n  VAR X: INTEGER;\n"
            + string.Concat(Enumerable.Range(1, 45).Select(number => $"  PROCEDURE P{number};\n  BEGIN\n{body}  END;\n"))
            + "BEGIN\nEND;\nBEGIN\nEND.\n";

        (byte[] sources, byte[] codes) = EmulatedPascalCompiler.Volumes(source);
        PascalVolume first = PascalVolume.Read(sources, proDosOrder: false);
        PascalVolume second = PascalVolume.Read(codes, proDosOrder: false);
        string main = PascalTextFile.Read(first.ReadFile("PROGRAM.TEXT"));
        List<string> included = [.. main.Split('\n').Where(line => line.StartsWith("(*$I ", StringComparison.Ordinal)).Select(line => $"{line}\n")];

        included.Should().HaveCountGreaterThan(1).And.Contain(directive => directive.Contains("CODE:", StringComparison.Ordinal));
        string whole = main;
        foreach (string directive in included)
        {
            string name = directive[(directive.IndexOf(':', StringComparison.Ordinal) + 1)..directive.IndexOf(".TEXT", StringComparison.Ordinal)] + ".TEXT";
            PascalVolume volume = directive.Contains("SOURCE:", StringComparison.Ordinal) ? first : second;
            whole = whole.Replace(directive, PascalTextFile.Read(volume.ReadFile(name)), StringComparison.Ordinal);
        }

        whole.TrimEnd().Should().Be(source.TrimEnd());
    }

    // A function, of a word, that adds 1 to its parameter, for the Assembler.
    private const string Add1Source = """
                .FUNC   ADD1,1
                PLA
                STA     RETURN
                PLA
                STA     RETURN+1
                PLA
                PLA
                PLA
                PLA
                PLA
                CLC
                ADC     #1
                TAX
                PLA
                ADC     #0
                PHA
                TXA
                PHA
                LDA     RETURN+1
                PHA
                LDA     RETURN
                PHA
                RTS
        RETURN  .WORD   0
                .END
        """;

    // A program that calls it.
    private const string LinkedSource = """
        PROGRAM LINKED;
        VAR I: INTEGER;
        FUNCTION ADD1(N: INTEGER): INTEGER; EXTERNAL;
        BEGIN
          I := ADD1(41)
        END.
        """;

    /// <summary>
    ///  Apple III Pascal's UNITSTATUS (CSP 12) and SCAN decompile: SCAN's test as <c>=</c> or <c>&lt;&gt;</c> and its
    ///  character, and a packed array's bounds from the range check of the element it starts at.
    /// </summary>
    [TestMethod]
    public void UnitStatusAndScanDecompile()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(Convert.FromBase64String(P4Code)));
        result.Warnings.Should().BeEmpty();
        string source = result.Source;
        source.Should().Contain("T2 = PACKED ARRAY[0..40] OF CHAR;").And.Contain("G24: INTEGER;").And.Contain("G25: CHAR;");
        source.Should().Contain("UNITSTATUS(0, G3, 0);").And.Contain("UNITSTATUS(G24, G3[3], 5);");
        source.Should().Contain("G23 := SCAN(41, = CHR(G24), G3);").And.Contain("G23 := SCAN(-10, <> G25, G26[2]);");
        source.Should().Contain("G23 := SCAN(G24, = 'A', G26)");
    }

    /// <summary>
    ///  P4's source compiles with Apple III Pascal 1.1's Compiler, on an emulated Apple III, to the same code.
    /// </summary>
    [TestMethod]
    public void UnitStatusAndScanRecompileOnTheApple3()
    {
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        string tools = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk2.dsk");
        if (!File.Exists(system) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE3_DISKS to a folder with Apple III Pascal 1.1's disks.");
        }

        PascalCodeFile original = PascalCodeFile.Read(Convert.FromBase64String(P4Code));
        PascalDecompilation result = PascalDecompiler.Decompile(original);
        (byte[]? code, string screen) = EmulatedPascalCompiler.Compile(result.Source, system, tools, s_inputs);
        if (code is null) { Assert.Fail($"The Compiler stopped:\n{screen}\n{result.Source}"); }
        PascalCodeComparison.Compare(original, PascalCodeFile.Read(code)).Should().BeEmpty(result.Source);
    }

    /// <summary>
    ///  A program's own units, which the Linker linked in, decompile to UNIT sources of their own: the procedures the
    ///  program calls in the interface, with the types it declares them with, and their bodies, an assembled one
    ///  EXTERNAL, in the implementation; the program USES them by their code files, and takes their types from them.
    /// </summary>
    [TestMethod]
    public void UnitsDecompileToUnitSources()
    {
        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(Convert.FromBase64String(P5Code)));
        result.Units.Select(unit => (unit.Name, unit.Segment)).Should().Equal(("ALPHA", 7), ("BETA", 8));
        result.Source.Should().Be("""
            PROGRAM USER;
            (* Each unit's interface is read from the code file its $U option names. *)
            USES (*$U ALPHA.CODE*) ALPHA, (*$U BETA.CODE*) BETA;
            VAR
              G3: T1;
              G7: INTEGER;
            BEGIN
              S7P2(G3, 5);
              G7 := S8F3(S8F2(G3[2]))
            END.

            """);

        result.Units[0].Source.Should().Be("""
            UNIT ALPHA;
            INTERFACE
              TYPE
                T1 = ARRAY[0..3] OF INTEGER;
              PROCEDURE S7P2(VAR A7X2: T1; A7X1: INTEGER);
            IMPLEMENTATION
              PROCEDURE S7P2;
                VAR
                  A7X3: INTEGER;
              BEGIN
                FOR A7X3 := 0 TO 3 DO
                  A7X2[A7X3] := A7X1
              END;
            END.

            """);

        result.Units[1].Source.Should().Contain("""
              FUNCTION S8F2(A8X3: INTEGER): INTEGER;
              FUNCTION S8F3(A8X3: INTEGER): INTEGER;
            IMPLEMENTATION
              FUNCTION S8F2;
                EXTERNAL;
              FUNCTION S8F3;
            """);

        result.Assembly.Should().StartWith("         .FUNC   S8F2,1\n");
    }

    /// <summary>
    ///  P5, built from its sources with Apple III Pascal 1.1's tools on an emulated Apple III, decompiles to a program,
    ///  its units and its assembled function that build back to the same segments: each unit compiled on its own, the
    ///  program against their code files, and all linked.
    /// </summary>
    [TestMethod]
    public void UnitsRebuildOnTheApple3()
    {
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        string tools = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk2.dsk");
        if (!File.Exists(system) || !File.Exists(tools))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE3_DISKS to a folder with Apple III Pascal 1.1's disks.");
        }

        byte[] original = BuildWithUnits(UserSource, [("ALPHA", AlphaSource), ("BETA", BetaSource)], Add1Source, system, tools);
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(Convert.FromBase64String(P5Code))).Should().BeEmpty();

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        byte[] rebuilt = BuildWithUnits(
            result.Source,
            [.. result.Units.Select(unit => (unit.Name, unit.Source))],
            result.Assembly ?? "",
            system,
            tools);

        // The blocks' unused ends hold what the Compiler's buffer had, the units' interface text among it, whose names
        // the code does not keep; the segments are the same.
        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(rebuilt)).Should().BeEmpty(result.Source);
    }

    // A program built with units of its own: each unit compiled to NAME.CODE, the program against them, its assembled
    // procedures assembled, and all linked.
    private static byte[] BuildWithUnits(string program, IReadOnlyList<(string Name, string Source)> units, string assembly, string boot, string tools)
    {
        Dictionary<string, byte[]> compiled = new(StringComparer.OrdinalIgnoreCase);
        foreach ((string name, string source) in units)
        {
            (byte[]? unit, string screen) = EmulatedPascalCompiler.Compile(source, boot, tools, s_inputs);
            if (unit is null) { Assert.Fail($"The Compiler stopped on {name}:\n{screen}\n{source}"); }
            compiled[$"{name}.CODE"] = unit;
        }

        (byte[]? host, string hosted) = EmulatedPascalCompiler.Compile(program, boot, tools, s_inputs, compiled);
        if (host is null) { Assert.Fail($"The Compiler stopped:\n{hosted}\n{program}"); }

        (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, boot, tools, s_inputs);
        if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}\n{assembly}"); }

        (byte[]? linked, string linking) = EmulatedPascalTools.Link(host, [.. units.Select(unit => compiled[$"{unit.Name}.CODE"]), assembled], boot, tools, s_inputs);
        if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }
        return linked;
    }

    private const string AlphaSource = """
        UNIT ALPHA;
        INTERFACE
          TYPE BUF = ARRAY[0..3] OF INTEGER;
          PROCEDURE FILL(VAR B: BUF; N: INTEGER);
        IMPLEMENTATION
          PROCEDURE FILL;
            VAR I: INTEGER;
          BEGIN
            FOR I := 0 TO 3 DO B[I] := N
          END;
        END.
        """;

    private const string BetaSource = """
        UNIT BETA;
        INTERFACE
          FUNCTION ADD1(N: INTEGER): INTEGER;
          FUNCTION TWICE(N: INTEGER): INTEGER;
        IMPLEMENTATION
          FUNCTION ADD1; EXTERNAL;
          FUNCTION TWICE;
          BEGIN
            TWICE := N * 2
          END;
        END.
        """;

    private const string UserSource = """
        PROGRAM USER;
        USES (*$U ALPHA.CODE*) ALPHA, (*$U BETA.CODE*) BETA;
        VAR G: BUF; X: INTEGER;
        BEGIN
          FILL(G, 5);
          X := TWICE(ADD1(G[2]))
        END.
        """;

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

        // The byte after a procedure's last p-code that puts its attributes on a word is not compared either.
        PascalSegment segment = PascalCodeFile.Read(original).Segments.Single(own => own.Code.Length > 0);
        List<int> ends = [];
        foreach (PascalProcedure procedure in segment.Procedures)
        {
            int end = PcodeDisassembler.Disassemble(segment, procedure).Max(instruction => instruction.Next);
            if ((end & 1) != 0) { ends.Add(end); }
        }

        ends.Should().NotBeEmpty();
        byte[] padded = (byte[])original.Clone();
        foreach (int end in ends)
        {
            padded[(segment.Block * 512) + end] ^= 0x5A;
        }

        PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(padded)).Should().BeEmpty();
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

    // A 140K image with an empty Pascal volume.
    private static byte[] EmptyVolume(string name) => PascalVolume.Format(name, proDosOrder: false);
}
