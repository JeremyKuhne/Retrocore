// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Trs80Model100;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100's BASIC: its tokens, its tokenizer and listings, as the ROM stores typed lines.
/// </summary>
[TestClass]
public sealed class Model100BasicTests
{
    private static BasicDialect Dialect => BasicDialect.Model100;

    // Lines typed into the Model 100's ROM, each quirk its tokenizer has; Model100TokenizesAsTheRom pins what it
    // stored for each.
    private static readonly string[] s_typed =
    [
        "10 CLS",
        "20 PRINT \"HELLO, WORLD!\" : REM greet",
        "30 IF SCORE > 5 THEN 100 ELSE 20",
        "40 FOR I = A TO B STEP 2 : NEXT I",
        "50 A=1 'note: here",
        "60 GO TO 10",
        "70 DATA 1, 2 ,\"A:B\", hello : PRINT",
        "80 ? \"Q\";TAB(5)",
        "90 print a$; left$(b$,2)",
        "100 IF X AND Y OR NOT Z THEN PRINT ELSE PRINT",
        "110 A# = 1D10 : B% = -3 : C! = 2",
        "120  PRINT \"two spaces\"",
        "130 PRINT\"a\";\"b\"",
        "140 ON ERROR GOTO 200 : RESUME NEXT",
        "150 X=PEEK(16396)+INP(1)",
        "160 A=5 MOD 23 XOR 1 EQV 2 IMP 3",
        "170 GOT O 5",
        "180 TOTAL=1",
        "190 SCREEN 0,0:LINE(1,2)-(3,4),1",
        "200 PRINT@40,\"X\"",
        "210 X=1:Y=2:Z$=\"a\":DATA x : y",
        "220 IFA=1GOTO10",
        "230 forI=1to3:next"
    ];

    /// <summary>
    ///  The tokenizer stores each line as the Model 100's ROM stored it when it was typed (read from the ROM's RAM
    ///  after typing it, 2026-11-26).
    /// </summary>
    /// <param name="line">The typed line.</param>
    /// <param name="stored">The bytes the ROM stored after the line number.</param>
    [TestMethod]
    [DataRow("10 CLS", "B0")]
    [DataRow("20 PRINT \"HELLO, WORLD!\" : REM greet", "A3202248454C4C4F2C20574F524C442122203A208E206772656574")]
    [DataRow("30 IF SCORE > 5 THEN 100 ELSE 20", "8A205343D64520DC203520CD20313030203A91203230")]
    [DataRow("40 FOR I = A TO B STEP 2 : NEXT I", "81204920DD204120C1204220CF2032203A20822049")]
    [DataRow("50 A=1 'note: here", "41DD31203A8EFF6E6F74653A2068657265")]
    [DataRow("60 GO TO 10", "88203130")]
    [DataRow("70 DATA 1, 2 ,\"A:B\", hello : PRINT", "8320312C2032202C22413A42222C2068656C6C6F203A20A3")]
    [DataRow("80 ? \"Q\";TAB(5)", "A3202251223BC03529")]
    [DataRow("90 print a$; left$(b$,2)", "A32041243B20FC2842242C3229")]
    [DataRow("100 IF X AND Y OR NOT Z THEN PRINT ELSE PRINT", "8A205820D5205920D620CE205A20CD20A3203A9120A3")]
    [DataRow("110 A# = 1D10 : B% = -3 : C! = 2", "412320DD2031443130203A20422520DD20D133203A20432120DD2032")]
    [DataRow("120  PRINT \"two spaces\"", "20A3202274776F2073706163657322")]
    [DataRow("130 PRINT\"a\";\"b\"", "A32261223B226222")]
    [DataRow("140 ON ERROR GOTO 200 : RESUME NEXT", "972094208820323030203A20952082")]
    [DataRow("150 X=PEEK(16396)+INP(1)", "58DDEE28313633393629D0E3283129")]
    [DataRow("160 A=5 MOD 23 XOR 1 EQV 2 IMP 3", "41DD3520DA20323320D7203120D8203220D92033")]
    [DataRow("170 GOT O 5", "882035")]
    [DataRow("180 TOTAL=1", "C154414CDD31")]
    [DataRow("190 SCREEN 0,0:LINE(1,2)-(3,4),1", "BE20302C303A9228312C3229D128332C34292C31")]
    [DataRow("200 PRINT@40,\"X\"", "A34034302C225822")]
    [DataRow("210 X=1:Y=2:Z$=\"a\":DATA x : y", "58DD313A59DD323A5A24DD2261223A832078203A2059")]
    [DataRow("220 IFA=1GOTO10", "8A41DD31883130")]
    [DataRow("230 forI=1to3:next", "8149DD31C1333A82")]
    public void Model100TokenizesAsTheRom(string line, string stored)
    {
        string text = Dialect.SplitLineNumber(line, out _);
        Convert.ToHexString(Dialect.Tokenize(text)).Should().Be(stored, line);
        Dialect.Tokenize(Dialect.Detokenize(Dialect.Tokenize(text))).Should().Equal(Dialect.Tokenize(text), "{0} lists as it was typed", line);
    }

    /// <summary>
    ///  A listing gives each token's word, <c>ELSE</c> and the apostrophe without the colon CRUNCH stored, and the
    ///  pragma's dialect name reads back.
    /// </summary>
    [TestMethod]
    public void ListingsReadAsTyped()
    {
        Dialect.Detokenize(Convert.FromHexString("8A205343D64520DC203520CD20313030203A91203230")).Should().Be("IF SCORE > 5 THEN 100 ELSE 20");
        Dialect.Detokenize(Convert.FromHexString("41DD31203A8EFF6E6F7465")).Should().Be("A=1 'note");
        BasicDialect.FromName("model100").Should().BeSameAs(Dialect);
        BasicProgram program = Model100FilesTests.Parse("10 PRINT \"HI\"\n20 GOTO 10\n");
        program.ToText(pragma: true).Should().StartWith("' retrocore model100\n");
    }

    /// <summary>
    ///  Renumbering changes the lines each jump names, RESTORE's too, which takes a line on the Model 100.
    /// </summary>
    [TestMethod]
    public void RenumberingFollowsTheJumps()
    {
        const string Program = "' retrocore model100\n5 GOSUB 30:ON A GOTO 5,30\n30 IF A THEN 5 ELSE 30\n40 RESTORE 30:RUN 5\n";
        (string? text, _) = BasicRenumber.Renumber(Program, start: 100, step: 100);
        text.Should().Be("' retrocore model100\n100 GOSUB 200:ON A GOTO 100,200\n200 IF A THEN 100 ELSE 200\n300 RESTORE 200:RUN 100\n");
    }

    /// <summary>
    ///  The dialect's keywords are the Model 100's ROM's table at $0080, one token each from $80 to $FF; inconclusive
    ///  without the user's ROM.
    /// </summary>
    /// <param name="rom">The ROM's file.</param>
    [TestMethod]
    [DataRow("m100.bin")]
    [DataRow("t102.bin")]
    public void KeywordsMatchTheRom(string rom)
    {
        byte[] bytes = Trs80Model100RomTests.Rom(rom);
        List<string> table = [];
        int at = 0x80;
        while (bytes[at] != 0x80)
        {
            string word = ((char)(bytes[at++] & 0x7F)).ToString();
            while ((bytes[at] & 0x80) == 0) { word += (char)bytes[at++]; }
            table.Add(word);
        }

        table.Should().Equal(Dialect.Keywords);
    }

    /// <summary>
    ///  The Model 100's ROM stores typed lines as the library tokenizes them, and the library reads the program back
    ///  from its RAM; inconclusive without the user's ROM.
    /// </summary>
    [TestMethod]
    public void TheRomStoresWhatTheLibraryTokenizes()
    {
        Trs80Model100Machine machine = Trs80Model100RomTests.Boot("m100.bin");
        Trs80Model100RomTests.Type(machine, "BASIC\r");
        machine.RunSeconds(1);
        foreach (string line in s_typed)
        {
            Trs80Model100RomTests.Type(machine, line + "\r");
            machine.RunSeconds(0.3);
        }

        machine.RunSeconds(1);
        BasicProgram stored = BasicProgram.Read(Dialect, Model100FilesTests.Memory(machine));
        stored.Lines.Should().HaveCount(s_typed.Length);
        for (int index = 0; index < s_typed.Length; index++)
        {
            string text = Dialect.SplitLineNumber(s_typed[index], out int number);
            stored.Lines[index].Number.Should().Be(number);
            Convert.ToHexString(stored.Lines[index].Tokens.Span).Should().Be(Convert.ToHexString(Dialect.Tokenize(text)), s_typed[index]);
        }
    }

    /// <summary>
    ///  A program written through the library over the one BASIC has open runs, and the files after it move with it;
    ///  inconclusive without the user's ROM.
    /// </summary>
    [TestMethod]
    public void WrittenProgramsRun()
    {
        Trs80Model100Machine machine = Trs80Model100RomTests.Boot("m100.bin");
        Trs80Model100RomTests.Type(machine, "BASIC\r");
        machine.RunSeconds(1);
        Trs80Model100RomTests.Type(machine, "OPEN \"NOTE\" FOR OUTPUT AS 1:PRINT #1,\"KEPT\":CLOSE\r");
        machine.RunSeconds(1);

        IBasicMemory memory = Model100FilesTests.Memory(machine);
        Model100FilesTests.Parse("10 FOR I=1 TO 3:PRINT I*7;:NEXT\n20 PRINT \"DONE\"\n30 OPEN \"NOTE\" FOR INPUT AS 1:INPUT #1,A$:CLOSE:PRINT A$\n").Write(memory);
        Trs80Model100RomTests.Type(machine, "RUN\r");
        machine.RunSeconds(2);

        string screen = string.Join("\n", machine.ScreenText());
        screen.Should().Contain(" 7  14  21").And.Contain("DONE").And.Contain("KEPT");
        BasicProgram.Read(Dialect, memory).Lines.Select(line => line.Number).Should().Equal(10, 20, 30);
    }
}
