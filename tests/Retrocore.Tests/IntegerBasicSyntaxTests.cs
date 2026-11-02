// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Integer BASIC's tokenizer in C#: the ROM's matcher over the ROM's syntax tables, compared with the ROM itself.
/// </summary>
[TestClass]
public class IntegerBasicSyntaxTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // Lines across Integer BASIC's syntax, and lines it refuses.
    private static readonly string[] s_lines =
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
        "140 A$(3,5)=\"XYZ\": B=A$(2)=\"Q\": GOTO 10*B+20",
        "150 PRINT A;B,C;: INPUT X,Y(2): IF X THEN GOSUB 100",
        "160 LIST 10,20: DSP X: NODSP X: TRACE : NOTRACE : POP",
        "170 PR#6: IN#0: HIMEM:32767: LOMEM:2048: CLR",
        "180 A=PDL(0)+SCRN(1,2)-3+ASC(\"A\")",
        "185 A=B-#3",
        "190 COLOR=TOTAL: TOTAL=STEPS: STEPS=1",
        "200 RETURN",
        "210 PRINT 01234,00",
        "220 PRINT (",
        "230 A=40000",
        "240 GOTO",
        "250 PRINT \"UNENDED",
        "PRINT 5",
        "260 X=1:Y=2:",
        "270"
    ];

    /// <summary>
    ///  The tables the tokenizer reads are the SDK build's bytes at $EC00-$EDFF and $F197.
    /// </summary>
    [TestMethod]
    public void TablesAreTheRoms()
    {
        byte[] rom = SdkModules.AssembleIntegerBasic(SdkModules.IntegerBasicPath(s_inputs)).Sections[0].Bytes.ToArray();
        IntegerBasicSyntax.s_table.Should().Equal(rom[0xC00..0xE00]);
        IntegerBasicSyntax.s_index.Should().Equal(rom[0x1197..0x11B7]);
    }

    /// <summary>
    ///  Each line tokenizes to the bytes the ROM stores when it is typed, and a line the ROM refuses is refused.
    /// </summary>
    [TestMethod]
    public void TokenizesAsTheRomDoes()
    {
        Apple2Roms roms = SdkModules.BuildRoms(Apple2Model.II, s_inputs);
        foreach (string line in s_lines)
        {
            IntegerSyntaxResult result = IntegerBasicSyntax.Tokenize(BasicText.Parse(line));
            if (!char.IsAsciiDigit(line[0]))
            {
                // Typed without a number, a line runs at once, which the ROM tokenizer's harness reports as refused.
                result.Error.Should().BeNull(line);
                continue;
            }

            IntegerBasicTokens rom = IntegerBasicTokenizer.Tokenize(roms, [line]);
            if (rom.Errors.Count != 0)
            {
                result.Error.Should().NotBeNull(line);
                continue;
            }

            result.Error.Should().BeNull(line);
            if (rom.Program.Length == 0)
            {
                // Typed without a number it runs at once, and a number alone deletes: nothing is stored either way.
                continue;
            }

            Stored(result).Should().Equal(rom.Program, line);
        }
    }

    /// <summary>
    ///  Every program on the 1980 System Master that is all BASIC lists as text that tokenizes back to the same bytes,
    ///  line for line, but for the constants' markers, which RENUMBER leaves as they were typed.
    /// </summary>
    [TestMethod]
    public void SystemMasterProgramsRoundTrip()
    {
        string path = Path.Join(ExternalTestData.Root, "iie-disks", "DOS 3.3 System Master - 680-0051-01 (1980).dsk");
        if (!File.Exists(path)) { Assert.Inconclusive($"The DOS 3.3 System Master ({path}) is missing."); }

        int lines = 0;
        List<string> untypeable = [];
        foreach (byte[] file in DosFiles.Read(File.ReadAllBytes(path), type: 0x01))
        {
            // An I file is its length, then the program as it lies from PP to HIMEM.
            byte[] image = file[2..(2 + (file[0] | (file[1] << 8)))];
            BasicProgram program;
            try
            {
                program = BasicProgram.FromImage(BasicDialect.Integer, image);
            }
            catch (InvalidDataException)
            {
                // APPLEVISION keeps machine code among its lines, which is no program to list.
                continue;
            }

            program.ToImage().Should().Equal(image);
            int before = untypeable.Count;
            foreach (BasicLine line in program.Lines)
            {
                string text = BasicDialect.Integer.Detokenize(line.Tokens.Span);
                if (text.Contains("{$A2}", StringComparison.Ordinal))
                {
                    // BIORHYTHM's line 610 has quotes inside a string, which no typed line can.
                    untypeable.Add($"{line.Number} {text}");
                    continue;
                }

                byte[] expected = IntegerBasicDialect.WithoutMarkers(line.Tokens.Span);
                IntegerBasicDialect.WithoutMarkers(BasicDialect.Integer.Tokenize(text)).Should().Equal(expected, text);
                lines++;
            }

            if (untypeable.Count != before) { continue; }

            BasicParseResult parsed = BasicProgram.Parse(program.ToText(pragma: true));
            parsed.Diagnostics.Select(diagnostic => $"{diagnostic.Line}: {diagnostic.Message}").Should().BeEmpty();
            parsed.Program.Should().NotBeNull();
            parsed.Program?.Lines.Select(line => Convert.ToHexString(IntegerBasicDialect.WithoutMarkers(line.Tokens.Span)))
                .Should()
                .Equal(program.Lines.Select(line => Convert.ToHexString(IntegerBasicDialect.WithoutMarkers(line.Tokens.Span))));
        }

        lines.Should().BeGreaterThan(300);
        untypeable.Should().ContainSingle().Which.Should().StartWith("610 ");
    }

    /// <summary>
    ///  A program written into memory ends at HIMEM, with PP at its first line and the variables cleared, and reads
    ///  back the same.
    /// </summary>
    [TestMethod]
    public void WritesAndReadsMemory()
    {
        BasicProgram? program = BasicProgram.Parse("REM retrocore integer\n10 PRINT \"HI\"\n20 GOTO 10\n").Program;
        if (program is null)
        {
            Assert.Fail("The program does not parse.");
            return;
        }

        byte[] bytes = new byte[0x10000];
        DelegateBasicMemory memory = DelegateBasicMemory.Of(bytes);
        (bytes[0x4A], bytes[0x4B]) = (0x00, 0x08);
        (bytes[0x4C], bytes[0x4D]) = (0x00, 0x96);
        (bytes[0xCC], bytes[0xCD]) = (0x00, 0x09);
        program.Write(memory);
        int start = bytes[0xCA] | (bytes[0xCB] << 8);
        start.Should().Be(0x9600 - program.ToImage().Length);
        (bytes[0xCC] | (bytes[0xCD] << 8)).Should().Be(0x0800, "the variables are cleared");
        BasicProgram.Read(BasicDialect.Integer, memory).ToText().Should().Be("10 PRINT \"HI\"\n20 GOTO 10\n");
    }

    /// <summary>
    ///  A refused line is an error at the place the tokenizer stopped.
    /// </summary>
    [TestMethod]
    public void ParsingReportsRefusedLines()
    {
        BasicParseResult parsed = BasicProgram.Parse("REM retrocore integer\n10 PRINT 1\n20 PRINT (\n");
        parsed.Program.Should().BeNull();
        BasicDiagnostic error = parsed.Diagnostics.Single();
        error.Line.Should().Be(2);
        error.Message.Should().Contain("SYNTAX");
        error.Start.Should().BeGreaterThan(3);
    }

    /// <summary>
    ///  Letters outside strings and remarks are matched as capitals, as the Apple II's keyboard types them; strings
    ///  keep their case.
    /// </summary>
    [TestMethod]
    public void LowercaseIsTypedAsCapitals()
    {
        IntegerSyntaxResult lower = IntegerBasicSyntax.Tokenize(BasicText.Parse("10 print \"Hi\";a"));
        IntegerSyntaxResult upper = IntegerBasicSyntax.Tokenize(BasicText.Parse("10 PRINT \"Hi\";A"));
        lower.Error.Should().BeNull();
        lower.Tokens.Should().Equal(upper.Tokens);
    }

    /// <summary>
    ///  A refused line says where the tokenizer stopped.
    /// </summary>
    [TestMethod]
    public void ARefusedLineSaysWhere()
    {
        IntegerSyntaxResult result = IntegerBasicSyntax.Tokenize(BasicText.Parse("10 PRINT 1: GOTO"));
        result.Error.Should().Be(IntegerSyntaxError.Syntax);
        result.Column.Should().BeGreaterThan(10);
    }

    // The line as Integer BASIC stores it: its length in place of the number's marker.
    private static byte[] Stored(IntegerSyntaxResult result)
    {
        byte[] line = [.. result.Tokens];
        line[0] = (byte)line.Length;
        return line;
    }
}
