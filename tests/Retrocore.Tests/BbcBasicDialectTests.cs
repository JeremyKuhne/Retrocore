// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Acorn;

namespace Retrocore.Tests;

/// <summary>
///  Verifies BBC BASIC II's dialect against the ROM: its keyword table, its tokeniser on lines typed into a Model B,
///  and its programs in memory.
/// </summary>
/// <remarks>
///  <para>
///   The machine runs on the ROMs built from the SDK's sources, so no dumps are needed.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcBasicDialectTests
{
    private static readonly string s_sources = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn");
    private static readonly Lazy<BbcRoms> s_roms = new(() => BbcSdkModules.Build(s_sources, filingSystem: false));

    // Lines that take each path through the tokeniser.
    private static readonly string[] s_lines =
    [
        "10 PRINT \"HELLO\";A%:GOTO 10",
        "20IF X>3 THEN 100 ELSE PRINT TIME",
        "30 TIME=0:P.PAGE:PR.\"A\"",
        "40 REM hello PRINT GOTO 10",
        "50 DATA 1,2,PRINT",
        "60 DEF PROCfoo(A$):LOCAL I%",
        "70 PROCPRINT:X=FNTIMER",
        "80 COUNTER=1:TIMER=2:ENDING=3",
        "90 ON X GOTO 10,20,30 ELSE 40",
        "100 *CAT",
        "110 A=&FFAB:B=1.5E3:C=.5",
        "120 printx=3:ENDPROC",
        "130 RESTORE 50:GOSUB 40000",
        "140 X=Y DIV 2 MOD 3 EOR 1 AND NOT 2",
        "150 PRINT ~X;TAB(3);LEFT$(A$,2)",
        "160 HIMEM=LOMEM+PAGE:PTR#C=TIME",
        "170 IF A THEN GOTO 10",
        "180 X=TRUE:Y=FALSE:Z=PI"
    ];

    /// <summary>
    ///  The dialect's keyword table is the ROM's: the same words, tokens and flags, in the order the ROM searches it.
    /// </summary>
    [TestMethod]
    public void KeywordTableMatchesTheRom()
    {
        AssemblyResult basic = BbcSdkModules.AssembleBasic(s_sources);
        ReadOnlySpan<byte> rom = basic.Sections[0].Bytes.Span;
        int at = (int)basic.Symbols["KEYWORD_TABLE"] - BbcSdkModules.PagedOrigin;
        List<(string, byte, int)> table = [];
        while (table.Count < BbcBasicDialect.Table.Count)
        {
            int start = at;
            while (rom[at] < 0x80) { at++; }
            table.Add((System.Text.Encoding.ASCII.GetString(rom[start..at]), rom[at], rom[at + 1]));
            at += 2;
        }

        table.Should().Equal(BbcBasicDialect.Table);
    }

    /// <summary>
    ///  Line numbers pack into three bytes as the ROM's comment gives line 10, and back.
    /// </summary>
    [TestMethod]
    public void LineNumbersPack()
    {
        BbcBasicDialect.PackLineNumber(10).Should().Be((0x54, 0x4A, 0x40));
        for (int number = 0; number <= 32767; number += 7)
        {
            (byte first, byte second, byte third) = BbcBasicDialect.PackLineNumber(number);
            BbcBasicDialect.UnpackLineNumber(first, second, third).Should().Be(number);
            ((int)first).Should().BeInRange(0x40, 0x7F);
        }
    }

    /// <summary>
    ///  Each line tokenises to the bytes BASIC stores when it is typed, and lists back as typed.
    /// </summary>
    [TestMethod]
    public void TypedLinesTokeniseAsTheRomDoes()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, string.Join("\r", s_lines) + "\r");
        BasicProgram stored = BasicProgram.Read(BasicDialect.BbcBasic, Memory(machine));
        stored.Lines.Should().HaveCount(s_lines.Length);
        for (int index = 0; index < s_lines.Length; index++)
        {
            string text = BasicDialect.BbcBasic.SplitLineNumber(s_lines[index], out int number);
            BasicLine line = stored.Lines[index];
            line.Number.Should().Be(number);
            Convert.ToHexString(BasicDialect.BbcBasic.Tokenize(text)).Should().Be(
                Convert.ToHexString(line.Tokens.Span),
                $"line {number} should tokenise as the ROM stored it");

            // Abbreviations list in full, as BASIC's LIST gives them.
            string listed = s_lines[index].Replace("P.PAGE", "PRINTPAGE", StringComparison.Ordinal)
                .Replace("PR.\"", "PRINT\"", StringComparison.Ordinal);

            BasicDialect.BbcBasic.FormatLine(line).Should().Be(listed);
        }
    }

    /// <summary>
    ///  A program written into memory runs, and BASIC's own LIST shows it as the dialect gives it.
    /// </summary>
    [TestMethod]
    public void WrittenProgramRuns()
    {
        BbcMachine machine = Boot();
        BasicProgram program = BasicProgram.Parse(
            "10 FOR I%=1 TO 3:PRINT I%*7;:NEXT\n20 PRINT '\"DONE\"\n",
            BasicDialect.BbcBasic).Program ?? throw new AssertFailedException("The program did not parse.");

        program.Write(Memory(machine));
        BbcMachineTests.Type(machine, "LIST\rRUN\r");
        string screen = string.Join("\n", machine.ReadTextScreen().Select(line => line.TrimEnd()));
        screen.Should().Contain("   10 FOR I%=1 TO 3:PRINT I%*7;:NEXT");
        screen.Should().Contain("   20 PRINT '\"DONE\"");
        screen.Should().Contain("         7        14        21");
        screen.Should().Contain("DONE");
    }

    /// <summary>
    ///  A SAVEd program's bytes, from PAGE to TOP, read as the program, and the program writes them back.
    /// </summary>
    [TestMethod]
    public void ImageRoundTrips()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, string.Join("\r", s_lines) + "\r");
        int page = machine.Bus.Peek(0x18) << 8;
        int top = machine.Bus.Peek(0x12) | (machine.Bus.Peek(0x13) << 8);
        byte[] image = machine.Bus.Ram[page..top].ToArray();
        BasicProgram program = BasicProgram.FromImage(BasicDialect.BbcBasic, image);
        program.ToImage().Should().Equal(image);
        (BasicProgram.Parse(program.ToText(), BasicDialect.BbcBasic).Program?.ToImage()).Should().Equal(image);
    }

    // A Model B on the SDK's MOS and BASIC, at BASIC's prompt.
    private static BbcMachine Boot()
    {
        BbcMachine machine = new(s_roms.Value, BbcModel.ModelB, diskInterface: false);
        BbcMachineTests.RunToPrompt(machine);
        return machine;
    }

    private static DelegateBasicMemory Memory(BbcMachine machine) =>
        new(address => machine.Bus.Peek((ushort)address), (address, value) => machine.Bus.Write((ushort)address, value));
}
