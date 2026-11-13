// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Reading Apple Pascal compiler listings: where each line's code is, the names of segments and procedures, and the
///  words of their variables.
/// </summary>
[TestClass]
public class PascalListingTests
{
    // Apple III Pascal 1.1's listing of a program with a segment procedure, and a function with a procedure in it.
    private const string Demo = """
             1   1    1:D     1 PROGRAM DEMO;
             2   1    1:D     3 VAR A, B: INTEGER;
             3   1    1:D     5 S: STRING;
             4   7    1:D     1 SEGMENT PROCEDURE SEGP(X: INTEGER);
             5   7    1:D     2 VAR Y: INTEGER;
             6   7    1:0     0 BEGIN
             7   7    1:1     0 Y := X * 2;
             8   7    1:1     5 WRITELN(Y)
             9   7    1:0    23 END;
            10   1    2:D     3 FUNCTION TWICE(N: INTEGER): INTEGER;
            11   1    3:D     1 PROCEDURE INNER;
            12   1    3:0     0 BEGIN
            13   1    3:1     0 N := N + 1
            14   1    3:0     3 END;
            15   1    2:0     0 BEGIN
            16   1    2:1     0 INNER;
            17   1    2:1     2 TWICE := N * 2
            18   1    2:0     3 END;
            19   1    1:0     0 BEGIN
            20   1    1:1     0 A := 1; B := TWICE(A);
            21   1    1:1    12 S := 'HI';
            22   1    1:1    21 SEGP(B);
            23   1    1:1    25 WRITELN(S, B)
            24   1    1:0    54 END.
        """;

    /// <summary>
    ///  Each line reads as its segment, procedure, depth or declaration, and offset, with its text; a heading or
    ///  stray line is left out.
    /// </summary>
    [TestMethod]
    public void LinesRead()
    {
        PascalListing listing = PascalListing.Parse("Apple /// Pascal Compiler\n" + Demo + "\n\f");
        listing.Lines.Should().HaveCount(24);
        listing.Lines[0].Should().Be(new PascalListingLine(1, 1, 1, Depth: null, 1, "PROGRAM DEMO;"));
        listing.Lines[21].Should().Be(new PascalListingLine(22, 1, 1, 1, 21, "SEGP(B);"));
        listing.Lines[21].IsDeclaration.Should().BeFalse();
    }

    /// <summary>
    ///  Segments and procedures are named by their headings, and match a code file's names by their first eight
    ///  letters.
    /// </summary>
    [TestMethod]
    public void HeadingsNameSegmentsAndProcedures()
    {
        PascalListing listing = PascalListing.Parse(Demo);
        listing.SegmentName(1).Should().Be("DEMO");
        listing.SegmentName(7).Should().Be("SEGP");
        listing.Segments.Should().BeEquivalentTo([1, 7]);
        listing.Compiles(1, "DEMO").Should().BeTrue();
        listing.Compiles(1, "SEGP").Should().BeFalse();
        listing.ProcedureName(1, 2).Should().Be("TWICE");
        listing.ProcedureName(1, 3).Should().Be("INNER");
        listing.ProcedureName(7, 1).Should().Be("SEGP");
        PascalListing.CodeName("PascalSystem").Should().Be("PASCALSY");
    }

    /// <summary>
    ///  A statement line gives its procedure and offset, and a p-code's offset gives the line it is in; a line that
    ///  declares has no code.
    /// </summary>
    [TestMethod]
    public void LinesAndOffsetsMap()
    {
        PascalListing listing = PascalListing.Parse(Demo);
        listing.Statement(22).Should().Match<PascalListingLine>(line => line.Segment == 1 && line.Procedure == 1 && line.Offset == 21);
        listing.Statement(2).Should().BeNull();
        listing.Statement(99).Should().BeNull();

        listing.LineAt(1, 1, 0)?.Line.Should().Be(20, "the statement, not the BEGIN, at the same offset");
        listing.LineAt(1, 1, 13)?.Line.Should().Be(21);
        listing.LineAt(1, 1, 54)?.Line.Should().Be(24);
        listing.LineAt(7, 1, 6)?.Line.Should().Be(8);
        listing.LineAt(1, 3, 2)?.Line.Should().Be(13);
        listing.LineAt(2, 1, 0).Should().BeNull();
    }

    /// <summary>
    ///  Declarations give their variables' words: globals after the program's files, a list from its last name,
    ///  parameters, a function's result, locals after parameters, and a string's 41 words.
    /// </summary>
    [TestMethod]
    public void DeclarationsGiveVariables()
    {
        PascalListing listing = PascalListing.Parse(Demo);
        // The Compiler allocates a list from its last name: VAR A, B puts B at word 3 and A at 4.
        listing.Variables(1, 1).Should().Equal(
            new PascalVariable("A", 4, 1, "INTEGER"),
            new PascalVariable("B", 3, 1, "INTEGER"),
            new PascalVariable("S", 5, 41, "STRING"));

        listing.Variables(1, 2).Should().Equal(
            new PascalVariable("TWICE", 1, 2, "INTEGER"),
            new PascalVariable("N", 3, 1, "INTEGER"));

        listing.Variables(7, 1).Should().Equal(
            new PascalVariable("X", 1, 1, "INTEGER"),
            new PascalVariable("Y", 2, 1, "INTEGER"));

        listing.Variables(1, 3).Should().BeEmpty();
    }

    /// <summary>
    ///  A name whose type's size is not known keeps its word, and the names after it on the line are left out;
    ///  types and constants declare no variables.
    /// </summary>
    [TestMethod]
    public void UnknownSizesStopALine()
    {
        PascalListing listing = PascalListing.Parse("""
                1   1    1:D     1 PROGRAM T;
                2   1    1:D     3 TYPE R = RECORD X: INTEGER END;
                3   1    1:D     3 VAR P: R; Q: INTEGER;
                4   1    1:D     9 C: CHAR; S: STRING[20];
                5   1    1:0     0 BEGIN
            """);

        listing.Variables(1, 1).Should().Equal(
            new PascalVariable("P", 3, 0, "R"),
            new PascalVariable("C", 9, 1, "CHAR"),
            new PascalVariable("S", 10, 11, "STRING[20]"));
    }

    /// <summary>
    ///  Headings name in any case; a VAR parameter's word holds its variable's address; and an array with a range in
    ///  its type is no integer, so the names after it on its line, whose words are unknown, are left out.
    /// </summary>
    [TestMethod]
    public void CaseReferencesAndArraysRead()
    {
        PascalListing listing = PascalListing.Parse("""
                1   1    1:D     1 program Shapes;
                2   1    1:D     3 var A: array[1..3] of integer; B: integer;
                3   1    2:D     3 function Area(var Side: integer; N: integer): integer;
                4   1    2:0     0 begin
            """);

        listing.SegmentName(1).Should().Be("Shapes");
        listing.Compiles(1, "SHAPES").Should().BeTrue();
        listing.ProcedureName(1, 2).Should().Be("Area");
        listing.Variables(1, 1).Should().Equal(new PascalVariable("A", 3, 0, "array[1..3] of integer"));
        // Parameters are pushed in order, so the last has the lowest word.
        listing.Variables(1, 2).Should().Equal(
            new PascalVariable("Area", 1, 2, "integer"),
            new PascalVariable("Side", 4, 1, "integer", Reference: true),
            new PascalVariable("N", 3, 1, "integer"));

        PascalListing.IsOrdinal("Integer").Should().BeTrue();
        PascalListing.IsOrdinal("1..10").Should().BeTrue();
        PascalListing.IsOrdinal("-5..'Z'").Should().BeTrue();
        PascalListing.IsOrdinal("ARRAY[1..3] OF INTEGER").Should().BeFalse();
        PascalListing.WordsOf("STRING[20]").Should().Be(11);
        PascalListing.WordsOf("ARRAY[1..3] OF INTEGER").Should().Be(0);
    }
}
