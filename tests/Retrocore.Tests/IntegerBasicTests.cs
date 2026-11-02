// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Integer BASIC: listing its tokens, and tokenizing text through the Apple II's own ROM.
/// </summary>
[TestClass]
public class IntegerBasicTests
{
    // Lines touching most of Integer BASIC's syntax: each tokenizes, lists back the same, and tokenizes again the same.
    private static readonly string[] s_program =
    [
        "10 TEXT : CALL -936",
        "20 DIM A$(20),B(10)",
        "30 INPUT \"NAME\",A$",
        "40 FOR I=1 TO 10 STEP 2",
        "50 B(I)=I*I+ABS (I-5) MOD 3",
        "60 NEXT I",
        "70 IF A$=\"\" THEN 30",
        "80 PRINT \"HELLO, \";A$;LEN(A$)",
        "90 GR : COLOR=12: PLOT 5,6: HLIN 1,10 AT 20: VLIN 2,8 AT 3",
        "100 GOSUB 200: POKE 768, PEEK (769)",
        "110 REM A REMARK, WITH \"QUOTES\"",
        "120 IF NOT B(3)>=2 AND RND (5)<>0 OR SGN (-4) THEN PRINT ASC(A$)",
        "130 VTAB 5: TAB 3: PRINT : END",
        "200 RETURN"
    ];

    private static string IIRoms => Environment.GetEnvironmentVariable("RETROCORE_II_ROMS")
        ?? Path.Join(ExternalTestData.Root, "apple2-roms", "APPLE II");

    /// <summary>
    ///  A program in memory lists as Integer BASIC wrote it: constants from their values, variables, strings and a
    ///  remark from their characters.
    /// </summary>
    [TestMethod]
    public void ListsAProgram()
    {
        byte[] program =
        [
            0x10, 0x0A, 0x00, 0x61, 0x28, 0xC8, 0xC9, 0x29, 0x46, 0xC1, 0xB1, 0x12, 0xB2, 0x17, 0x00, 0x01,
            0x0B, 0x14, 0x00, 0x5D, 0xA0, 0xC8, 0xC5, 0xCC, 0xCC, 0xCF, 0x01
        ];

        IntegerBasic.List(program).Should().Be("10 PRINT \"HI\";A1+23\n20 REM HELLO\n");
        IntegerBasic.LineNumbers(program).Should().Equal(10, 20);
    }

    /// <summary>
    ///  A line whose length runs past the end is not a program.
    /// </summary>
    [TestMethod]
    public void RefusesBytesThatAreNotAProgram()
    {
        Action broken = () => IntegerBasic.List([0x10, 0x0A, 0x00, 0x61]);
        broken.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Text tokenized by Integer BASIC lists back the same, and the listing tokenizes to the same bytes.
    /// </summary>
    [TestMethod]
    public void TokenizesThroughTheRomAndListsBackTheSame()
    {
        Apple2Roms roms = Roms();
        IntegerBasicTokens tokens = IntegerBasicTokenizer.Tokenize(roms, s_program);
        tokens.Errors.Should().BeEmpty();
        IntegerBasic.LineNumbers(tokens.Program).Should().Equal(10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 200);

        string listing = IntegerBasic.List(tokens.Program);
        IntegerBasicTokens again = IntegerBasicTokenizer.Tokenize(roms, listing.Split('\n'));
        again.Program.Should().Equal(tokens.Program, "the listing is text Integer BASIC tokenizes the same");
        Squeeze(listing).Should().Be(Squeeze(string.Join("\n", s_program) + "\n"), "only spacing may differ");
    }

    /// <summary>
    ///  A line Integer BASIC refuses is reported with what it printed, and the rest of the program still goes in.
    /// </summary>
    [TestMethod]
    public void ReportsTheLinesTheRomRefuses()
    {
        IntegerBasicTokens tokens = IntegerBasicTokenizer.Tokenize(Roms(), ["10 PRINT 1", "20 PRINT (", "PRINT 2", "30 END"]);
        tokens.Errors.Select(error => error.Line).Should().Equal(1, 2);
        tokens.Errors[0].Message.Should().Contain("ERR");
        IntegerBasic.LineNumbers(tokens.Program).Should().Equal(10, 30);
    }

    private static Apple2Roms Roms()
    {
        if (!File.Exists(Path.Join(IIRoms, "APPLE II - 341-0001 - INTEGER BASIC E000 - 2716.bin")))
        {
            Assert.Inconclusive("Set RETROCORE_II_ROMS to the II's chip dumps.");
        }

        return Apple2Roms.LoadFromDirectory(Apple2Model.II, IIRoms);
    }

    private static string Squeeze(string text) => text.Replace(" ", "", StringComparison.Ordinal);
}
