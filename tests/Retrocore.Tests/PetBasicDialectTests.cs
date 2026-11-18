// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Commodore PET's BASIC 1 and 2: each tokenizer's quirks, the text form, the pointers and the variables
///  as the ROMs lay them out. The expected bytes are what the ROMs' <c>CRUNCH</c> stores.
/// </summary>
[TestClass]
public sealed class PetBasicDialectTests
{
    private const int ProgramStart = 0x0401;
    private const int MemoryTop = 0x8000;
    private const int VariablesStart = 0x0410;

    /// <summary>
    ///  Both versions are found by one name, BASIC 2 first, and know their own words: only BASIC 2 has GO.
    /// </summary>
    [TestMethod]
    public void DialectsAreNamed()
    {
        BasicDialect.FromName("PetBasic").Should().BeSameAs(BasicDialect.PetBasic4);
        BasicDialect.PetBasicVersion(1).Should().BeSameAs(BasicDialect.PetBasic1);
        BasicDialect.PetBasicVersion(2).Should().BeSameAs(BasicDialect.PetBasic);
        BasicDialect.PetBasicVersion(4).Should().BeSameAs(BasicDialect.PetBasic4);
        BasicDialect.PetBasic.DisplayName.Should().Be("Commodore BASIC 2 (PET)");
        BasicDialect.PetBasic1.DisplayName.Should().Be("Commodore BASIC 1 (PET)");
        BasicDialect.PetBasic4.DisplayName.Should().Be("Commodore BASIC 4 (PET)");
        BasicDialect.PetBasic1.Name.Should().Be(BasicDialect.PetBasic.Name);
        BasicDialect.PetBasic4.Name.Should().Be(BasicDialect.PetBasic.Name);

        BasicDialect.PetBasic.Keywords.Should().HaveCount(76);
        BasicDialect.PetBasic.Keyword(0xCB).Should().Be("GO");
        BasicDialect.PetBasic.Keyword(0xCC).Should().BeNull();
        BasicDialect.PetBasic1.Keywords.Should().Equal(BasicDialect.PetBasic.Keywords.Take(75));
        BasicDialect.PetBasic1.Keyword(0xCB).Should().BeNull();
        BasicDialect.PetBasic4.Keywords.Take(76).Should().Equal(BasicDialect.PetBasic.Keywords);
        BasicDialect.PetBasic4.Keyword(0xCC).Should().Be("CONCAT");
        BasicDialect.PetBasic4.Keyword(0xDA).Should().Be("DIRECTORY");

        foreach (BasicDialect dialect in (BasicDialect[])[BasicDialect.PetBasic, BasicDialect.PetBasic1, BasicDialect.PetBasic4])
        {
            dialect.Keyword(0x80).Should().Be("END");
            dialect.Keyword(0x99).Should().Be("PRINT");
            dialect.Keyword(0xA2).Should().Be("NEW");
            dialect.Keyword(0xB4).Should().Be("SGN");
            dialect.Keyword(0xCA).Should().Be("MID$");
            dialect.DefaultLoadAddress.Should().Be(ProgramStart);
            dialect.MaximumLineNumber.Should().Be(63999);
        }
    }

    /// <summary>
    ///  BASIC 2 keeps spaces, finds words anywhere, has GO as a word of its own, and does not skip spaces inside
    ///  words.
    /// </summary>
    /// <param name="text">The statements typed after a line number.</param>
    /// <param name="expected">The bytes stored, in hex.</param>
    [TestMethod]
    [DataRow("PRINT \"HI\"", "992022484922")]
    [DataRow("?A", "9941")]
    [DataRow("IF SCORE > 5 THEN 100", "8B205343B04520B1203520A720313030")]
    [DataRow("FOR I=S TO P", "812049B25320A42050")]
    [DataRow("GO TO 10", "CB20A4203130")]
    [DataRow("GO  TO 10", "CB2020A4203130")]
    [DataRow("GO SUB 10", "CB20535542203130")]
    [DataRow("G O T O 10", "47204F2054204F203130")]
    [DataRow("GOTO10", "893130")]
    [DataRow("PRINT #1,A", "992023312C41")]
    [DataRow("PRINT# 1,A", "9820312C41")]
    [DataRow("DATA 1, 2 ,\"A:B\", HELLO : PRINT", "8320312C2032202C22413A42222C2048454C4C4F203A2099")]
    [DataRow("REM  HI:THERE \"X", "8F202048493A5448455245202258")]
    [DataRow("A=1:B=2: C = A AND B OR NOT C", "41B2313A42B2323A204320B2204120AF204220B020A82043")]
    [DataRow("PRINT \"UNCLOSED", "992022554E434C4F534544")]
    [DataRow("F OR I=1TO10STEP2:NEXT", "4620B02049B231A43130A9323A82")]
    [DataRow("S T O P", "532054204F2050")]
    [DataRow("  PRINT  ", "2020992020")]
    [DataRow("A$=LEFT$(B$,2)+MID$(C$,1,1)+RIGHT$(D$,1)+CHR$(147)+STR$(1)", "4124B2C82842242C3229AACA2843242C312C3129AAC92844242C3129AAC72831343729AAC4283129")]
    [DataRow("OPEN 1,4:CMD 1:CLOSE 1:SYS 64824:CLR:GET A$", "9F20312C343A9D20313AA020313A9E2036343832343A9C3AA1204124")]
    [DataRow("LIST 63999", "9B203633393939")]
    [DataRow("PRINT \"{$93}{CTRL-S}{$11}{$12}HI{$92}{$A0}\"", "99202293131112484992A022")]
    [DataRow("A={$FF}*2", "41B2FFAC32")]
    public void Basic2Tokenizes(string text, string expected) =>
        Convert.ToHexString(BasicDialect.PetBasic.Tokenize(text)).Should().Be(expected);

    /// <summary>
    ///  BASIC 1 skips spaces inside reserved words, so GO TO is GOTO and S TO P is STOP, and has no GO.
    /// </summary>
    /// <param name="text">The statements typed after a line number.</param>
    /// <param name="expected">The bytes stored, in hex.</param>
    [TestMethod]
    [DataRow("PRINT \"HI\"", "992022484922")]
    [DataRow("IF SCORE > 5 THEN 100", "8B205343B04520B1203520A720313030")]
    [DataRow("FOR I=S TO P", "812049B290")]
    [DataRow("GO TO 10", "89203130")]
    [DataRow("G O T O 10", "89203130")]
    [DataRow("GO  TO 10", "89203130")]
    [DataRow("GO SUB 10", "8D203130")]
    [DataRow("PRINT #1,A", "98312C41")]
    [DataRow("F OR I=1TO10STEP2:NEXT", "812049B231A43130A9323A82")]
    [DataRow("S T O P", "90")]
    [DataRow("  PRINT  ", "2020992020")]
    [DataRow("DATA  A B C ,\"X\" : PRINT", "8320204120422043202C225822203A2099")]
    [DataRow("REM  HI:THERE \"X", "8F202048493A5448455245202258")]
    [DataRow("A=1:B=2: C = A AND B OR NOT C", "41B2313A42B2323A204320B2204120AF204220B020A82043")]
    public void Basic1Tokenizes(string text, string expected) =>
        Convert.ToHexString(BasicDialect.PetBasic1.Tokenize(text)).Should().Be(expected);

    /// <summary>
    ///  Lowercase letters outside strings, DATA and REM are the uppercase the keyboard types; inside them they stay
    ///  as written.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    /// <param name="text">The statements.</param>
    /// <param name="expected">The bytes stored, in hex.</param>
    [TestMethod]
    [DataRow(2, "print a$", "99204124")]
    [DataRow(2, "PRINT \"hi\"", "992022686922")]
    [DataRow(2, "DATA ab:print", "832061623A99")]
    [DataRow(2, "rem Lower", "8F204C6F776572")]
    [DataRow(2, "x{{y", "587B59")]
    [DataRow(1, "go to 10", "89203130")]
    public void LowercaseIsFoldedOutsideLiterals(int version, string text, string expected) =>
        Convert.ToHexString(BasicDialect.PetBasicVersion(version).Tokenize(text)).Should().Be(expected);

    /// <summary>
    ///  A listing reads as BASIC would show it and tokenizes back to the same bytes.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    /// <param name="text">The typed statements.</param>
    /// <param name="listing">The listing of what was stored.</param>
    [TestMethod]
    [DataRow(2, "IF SCORE > 5 THEN 100", "IF SCORE > 5 THEN 100")]
    [DataRow(2, "GO TO 10", "GO TO 10")]
    [DataRow(2, "print a$;\"hi\"", "PRINT A$;\"hi\"")]
    [DataRow(2, "PRINT \"{$93}{$11}HI{$12}\"", "PRINT \"{$93}{CTRL-Q}HI{CTRL-R}\"")]
    [DataRow(2, "A={$FF}*2", "A={$FF}*2")]
    [DataRow(2, "DATA  1, 2", "DATA  1, 2")]
    [DataRow(2, "PRINT \"{{\"", "PRINT \"{{\"")]
    [DataRow(1, "G O T O 10", "GOTO 10")]
    [DataRow(1, "FOR I=S TO P", "FOR I=STOP")]
    [DataRow(1, "PRINT #1,A", "PRINT#1,A")]
    public void ListingsRoundTrip(int version, string text, string listing)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        byte[] tokens = dialect.Tokenize(text);
        string listed = dialect.Detokenize(tokens);
        listed.Should().Be(listing);
        dialect.Tokenize(listed).Should().Equal(tokens);
    }

    /// <summary>
    ///  Bytes typing could not store still list as text that tokenizes back to them.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    /// <param name="hex">The stored bytes.</param>
    [TestMethod]
    [DataRow(2, "3F20")]
    [DataRow(2, "61")]
    [DataRow(2, "FF")]
    [DataRow(2, "C1")]
    [DataRow(2, "474F544F")]
    [DataRow(1, "CB")]
    [DataRow(1, "4720544F")]
    [DataRow(1, "992023")]
    public void OddBytesRoundTrip(int version, string hex)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        byte[] bytes = Convert.FromHexString(hex);
        dialect.Tokenize(dialect.Detokenize(bytes)).Should().Equal(bytes);
    }

    /// <summary>
    ///  A text program takes the PET's BASIC from a pragma, keeps BASIC 1 when that is the dialect given, and stops at
    ///  line 63999.
    /// </summary>
    [TestMethod]
    public void TextProgramsParse()
    {
        BasicParseResult parsed = BasicProgram.Parse("REM retrocore petbasic\n10 PRINT \"HI\"\n63999 END\n");
        parsed.Success.Should().BeTrue();
        parsed.Dialect.Should().BeSameAs(BasicDialect.PetBasic4, "petbasic names BASIC 4, which has every word");
        parsed.Program?.ToText().Should().Be("10 PRINT \"HI\"\n63999 END\n");

        BasicProgram.Parse("REM retrocore petbasic\n10 GO TO 10\n", BasicDialect.PetBasic1).Dialect.Should().BeSameAs(BasicDialect.PetBasic1);
        BasicProgram.Parse("10 END", path: "game.petbasic.bas").Dialect.Should().BeSameAs(BasicDialect.PetBasic4);
        BasicProgram.Parse("64000 END", BasicDialect.PetBasic).Success.Should().BeFalse("64000 is past the last line");

        // CHRGET skips the spaces after the line number.
        BasicDialect.PetBasic.SplitLineNumber("10   PRINT", out int number).Should().Be("PRINT");
        number.Should().Be(10);
    }

    /// <summary>
    ///  Tokenized images link their lines from $0401, and writing one into memory sets each version's pointers.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    /// <param name="programStart">TXTTAB.</param>
    /// <param name="variables">VARTAB.</param>
    /// <param name="currentLine">CURLIN.</param>
    [TestMethod]
    [DataRow(1, 0x7A, 0x7C, 0x88)]
    [DataRow(2, 0x28, 0x2A, 0x36)]
    [DataRow(4, 0x28, 0x2A, 0x36)]
    public void ProgramsWriteToMemory(int version, int programStart, int variables, int currentLine)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        BasicPointers pointers = dialect.Pointers;
        pointers.ProgramStart.Should().Be(programStart);
        pointers.Variables.Should().Be(variables);
        pointers.CurrentLine.Should().Be(currentLine);
        (pointers.Arrays, pointers.FreeStart, pointers.StringBottom, pointers.MemoryTop).Should()
            .Be((variables + 2, variables + 4, variables + 6, variables + 10));

        (pointers.ContinueText, pointers.DataPointer).Should().Be((currentLine + 4, currentLine + 8));
        pointers.ProgramEnd.Should().BeNull();
        pointers.StackTop.Should().BeNull();

        BasicProgram program = BasicProgram.Parse("10 END\n20 PRINT \"HI\"\n", dialect).Program ?? throw new AssertFailedException("parse");
        Convert.ToHexString(program.ToImage()).Should().Be("07040A00800012041400992022484922000000");

        byte[] ram = new byte[0x10000];
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        Word(ram, pointers.ProgramStart, ProgramStart);
        Word(ram, pointers.MemoryTop, MemoryTop);
        program.Write(memory);
        int end = ProgramStart + program.ToImage(ProgramStart).Length;
        foreach (int pointer in (int[])[pointers.Variables, pointers.Arrays, pointers.FreeStart])
        {
            Read(ram, pointer).Should().Be(end);
        }

        Read(ram, pointers.StringBottom).Should().Be(MemoryTop);
        Read(ram, pointers.DataPointer).Should().Be(ProgramStart - 1);
        BasicProgram.Read(dialect, memory).ToText().Should().Be(program.ToText());

        // Direct mode is $FF in CURLIN's high byte alone.
        ram[pointers.CurrentLine] = 0;
        ram[pointers.CurrentLine + 1] = 0xFF;
        dialect.InDirectMode(memory).Should().BeTrue();
        ram[pointers.CurrentLine + 1] = 0;
        dialect.InDirectMode(memory).Should().BeFalse();
    }

    /// <summary>
    ///  The variables, an array and a string as BASIC lays them out read back, a new variable moves the arrays up,
    ///  and the evaluator takes true as -1 and AND, OR and NOT bit by bit.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    public void VariablesReadAsTheRomKeepsThem(int version)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        BasicPointers pointers = dialect.Pointers;
        byte[] ram = new byte[0x10000];
        DelegateBasicMemory memory = DelegateBasicMemory.Of(ram);
        byte[] simple =
        [
            0x41, 0x00, 0x81, 0x40, 0x00, 0x00, 0x00,   // A = 1.5
            0xC2, 0x80, 0xFF, 0xFD, 0x00, 0x00, 0x00,   // B% = -3, high byte first
            0x43, 0x80, 0x02, 0xFE, 0x7F, 0x00, 0x00    // C$ = "HI" at $7FFE
        ];

        byte[] array =
        [
            0x45, 0x00, 0x16, 0x00, 0x01, 0x00, 0x03,   // E(2): its size, one subscript of three elements
            0x00, 0x00, 0x00, 0x00, 0x00,
            0x83, 0x60, 0x00, 0x00, 0x00,               // E(1) = 7
            0x00, 0x00, 0x00, 0x00, 0x00
        ];

        simple.CopyTo(ram, VariablesStart);
        int arrays = VariablesStart + simple.Length;
        array.CopyTo(ram, arrays);
        "HI"u8.CopyTo(ram.AsSpan(MemoryTop - 2));
        Word(ram, pointers.ProgramStart, ProgramStart);
        Word(ram, pointers.Variables, VariablesStart);
        Word(ram, pointers.Arrays, arrays);
        Word(ram, pointers.FreeStart, arrays + array.Length);
        Word(ram, pointers.StringBottom, MemoryTop - 2);
        Word(ram, pointers.MemoryTop, MemoryTop);

        BasicVariables variables = new(dialect, memory);
        variables.Simple().Select(variable => variable.Name).Should().Equal("A", "B%", "C$");
        Value(variables, "A").Should().Be(1.5);
        Value(variables, "B%").Should().Be(-3);
        Encoding.ASCII.GetString(variables.Read(BasicVariableKind.String, variables.Find("C$")?.ValueAddress ?? 0).Text ?? []).Should().Be("HI");
        BasicArray e = variables.FindArray("E") ?? throw new AssertFailedException("E");
        e.Dimensions.Should().Equal(3);
        variables.Read(e.Kind, e.ElementAddress([1])).Number.Should().Be(7);

        BasicEvaluator evaluator = new(dialect, memory);
        evaluator.Format(evaluator.Evaluate("A*2+B%")).Should().Be("0");
        evaluator.Format(evaluator.Evaluate("C$+\"!\"")).Should().Be("\"HI!\"");
        evaluator.Format(evaluator.Evaluate("1=1")).Should().Be("-1");
        evaluator.Format(evaluator.Evaluate("2 AND 1")).Should().Be("0");
        evaluator.Format(evaluator.Evaluate("NOT 0")).Should().Be("-1");

        // A new variable goes at the end of the simple ones, as seven bytes, and moves the arrays up.
        BasicVariable d = variables.Create("D%");
        d.Address.Should().Be(arrays);
        ram.AsSpan(arrays, 2).ToArray().Should().Equal(0xC4, 0x80);
        Read(ram, pointers.Arrays).Should().Be(arrays + 7);
        variables.Write(BasicVariableKind.Integer, d.ValueAddress, new(258));
        ram.AsSpan(d.ValueAddress, 2).ToArray().Should().Equal(0x01, 0x02);
        variables.Read(e.Kind, (variables.FindArray("E") ?? e).ElementAddress([1])).Number.Should().Be(7);
    }

    /// <summary>
    ///  AND, OR and NOT take their operands down to the integer below, as AYINT and QINT do, so a fraction under
    ///  32768 is in range and a negative one goes down.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <param name="result">What BASIC prints for it.</param>
    [TestMethod]
    [DataRow("NOT -0.5", "0")]
    [DataRow("NOT 0.5", "-1")]
    [DataRow("32767.5 AND 1", "1")]
    [DataRow("-0.5 OR 0", "-1")]
    [DataRow("-32768 AND -1", "-32768")]
    public void LogicTakesTheFloor(string expression, string result)
    {
        BasicEvaluator evaluator = new(BasicDialect.PetBasic, DelegateBasicMemory.Of(new byte[0x10000]));
        evaluator.Format(evaluator.Evaluate(expression)).Should().Be(result);
        Action tooBig = () => evaluator.Evaluate("32768 AND 1");
        tooBig.Should().Throw<FormatException>();
    }

    /// <summary>
    ///  BASIC 1 skips spaces inside reserved words, so R E M and D A T A hide what follows from label checks.
    /// </summary>
    [TestMethod]
    public void SpacedRemarksAndDataHideLabels()
    {
        BasicProgram.Parse("10 R E M GOTO nowhere\n", BasicDialect.PetBasic1).Success.Should().BeTrue();
        BasicProgram.Parse("10 D A T A GOTO nowhere\n", BasicDialect.PetBasic1).Success.Should().BeTrue();
        BasicProgram.Parse("10 D A T A 1:GOTO nowhere\n", BasicDialect.PetBasic1).Success.Should().BeFalse("DATA ends at the colon");
    }

    /// <summary>
    ///  Writing a program clears BASIC 4's disk status, as CLEARC does, since its string was in the space freed.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    /// <param name="cleared">Whether the disk status descriptor is cleared.</param>
    [TestMethod]
    [DataRow(4, true)]
    [DataRow(2, false)]
    public void WritingAProgramForgetsTheDiskStatus(int version, bool cleared)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        byte[] ram = new byte[0x10000];
        Word(ram, dialect.Pointers.ProgramStart, ProgramStart);
        Word(ram, dialect.Pointers.MemoryTop, MemoryTop);
        ram[PetBasicDialect.DiskStatusDescriptor] = 40;
        BasicProgram program = BasicProgram.Parse("10 END\n", dialect).Program ?? throw new AssertFailedException("parse");
        program.Write(DelegateBasicMemory.Of(ram));
        ram[PetBasicDialect.DiskStatusDescriptor].Should().Be(cleared ? (byte)0 : (byte)40);
    }

    /// <summary>
    ///  Every reserved word of both versions has help.
    /// </summary>
    /// <param name="version">The BASIC version.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    public void EveryKeywordHasHelp(int version)
    {
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        dialect.Keywords.Where(keyword => BasicKeywordHelp.Describe(dialect, keyword) is null).Should().BeEmpty();
        BasicKeywordHelp.Markdown(dialect, "PRINT").Should().Contain("10-column");
        BasicKeywordHelp.Describe(dialect, "CLR")?.Syntax.Should().Be("CLR");
    }

    private static double Value(BasicVariables variables, string name)
    {
        BasicVariable variable = variables.Find(name) ?? throw new AssertFailedException(name);
        return variables.Read(variable.Kind, variable.ValueAddress).Number;
    }

    private static int Read(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void Word(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
