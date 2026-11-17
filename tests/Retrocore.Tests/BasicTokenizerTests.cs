// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the BASIC library: each ROM's reserved words, its tokenizer's quirks, the text form and the program
///  formats.
/// </summary>
[TestClass]
public sealed class BasicTokenizerTests
{
    // A CSAVE tape's leader, sync byte, three header bytes and name.
    private const int BasicTapeHeader = 255 + 1 + 3 + 1;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The reserved word lists are the ROMs' own, in token order.
    /// </summary>
    [TestMethod]
    public void KeywordsMatchTheRoms()
    {
        AssemblyResult appleSoft = SdkModules.AssembleAppleSoft(Path.Join(s_inputs, "AppleSoft", "applesoft.mac"), Apple2Model.IIeEnhanced);
        RomWords(appleSoft.Sections[0].Bytes.Span[(int)appleSoft.Symbols["RESLST"]..], lastLetterMarked: true)
            .Should().Equal(BasicDialect.AppleSoft.Keywords);

        AssemblyResult level2 = Trs80SdkModules.AssembleLevel2(Path.Join(s_inputs, "Trs80", "Level2.asm"), revision: 12);
        RomWords(level2.Sections[0].Bytes.Span[(int)level2.Symbols["KEYWORDS"]..], lastLetterMarked: false)
            .Should().Equal(BasicDialect.Level2.Keywords);
    }

    /// <summary>
    ///  The ROM sources name the statement dispatch and command loop the debugger uses to bring BASIC back to its
    ///  prompt after a save, on every model and revision.
    /// </summary>
    [TestMethod]
    public void BasicRomsNameTheirPromptAndStatements()
    {
        foreach (Apple2Model model in (Apple2Model[])[Apple2Model.IIe, Apple2Model.IIeEnhanced])
        {
            AssemblyResult appleSoft = SdkModules.AssembleAppleSoft(Path.Join(s_inputs, "AppleSoft", "applesoft.mac"), model);
            appleSoft.Symbols.Should().ContainKeys("NEWSTT", "MAIN");
        }

        foreach (int revision in (int[])[12, 13])
        {
            Trs80SdkModules.AssembleLevel2(Path.Join(s_inputs, "Trs80", "Level2.asm"), revision).Symbols
                .Should().ContainKeys("NEWSTT", "READY");
        }
    }

    /// <summary>
    ///  AppleSoft drops spaces, finds reserved words anywhere, and has its AT, ? and DATA rules.
    /// </summary>
    /// <param name="text">The statements typed after a line number.</param>
    /// <param name="expected">The bytes stored, in hex.</param>
    [TestMethod]
    [DataRow("PRINT \"HI\"", "BA22484922")]
    [DataRow("?A", "BA41")]
    [DataRow("IF SCORE > 5 THEN 100", "AD5343CE45CF35C4313030")]
    [DataRow("FOR I = A TO B", "8149D041C142")]
    [DataRow("X = ATN(1)", "58D0E1283129")]
    [DataRow("DRAW 1 AT 5,6", "9431C5352C36")]
    [DataRow("DATA 1, 2 ,\"A:B\": PRINT", "8320312C2032202C22413A42223ABA")]
    [DataRow("REM  Hi:there", "B2202048693A7468657265")]
    [DataRow("print a$", "BA4124")]
    [DataRow("G O T O 10", "AB3130")]
    [DataRow("HGR 2", "90")]
    [DataRow("PRINT \"{CTRL-D}CATALOG\"", "BA2204434154414C4F4722")]
    public void AppleSoftTokenizes(string text, string expected) =>
        Convert.ToHexString(BasicDialect.AppleSoft.Tokenize(text)).Should().Be(expected);

    /// <summary>
    ///  The original IIe's AppleSoft leaves lowercase alone, so lowercase is not a reserved word.
    /// </summary>
    [TestMethod]
    public void OriginalAppleSoftKeepsLowercase() =>
        Convert.ToHexString(BasicDialect.AppleSoftOriginal.Tokenize("print a$")).Should().Be("7072696E746124");

    /// <summary>
    ///  Level II keeps spaces, stores ELSE with a colon and an apostrophe as :REM', and lets only GOTO have spaces.
    /// </summary>
    /// <param name="text">The statements typed after a line number.</param>
    /// <param name="expected">The bytes stored, in hex.</param>
    [TestMethod]
    [DataRow("PRINT \"HI\"", "B22022484922")]
    [DataRow("IF A THEN 10 ELSE 20", "8F204120CA203130203A95203230")]
    [DataRow("A=1 'note", "41D531203A93FB6E6F7465")]
    [DataRow("GO TO 10", "8D203130")]
    [DataRow("for i=1 to 3", "812049D53120BD2033")]
    [DataRow("SCORE=1", "5343D345D531")]
    [DataRow("DATA a, \"x:y\":PRINT", "8820612C2022783A79223AB2")]
    [DataRow("PRINT\"a\"", "B2226122")]
    public void Level2Tokenizes(string text, string expected) =>
        Convert.ToHexString(BasicDialect.Level2.Tokenize(text)).Should().Be(expected);

    /// <summary>
    ///  A listing reads as BASIC would show it and tokenizes back to the same bytes.
    /// </summary>
    /// <param name="dialect">The dialect's name.</param>
    /// <param name="text">The typed statements.</param>
    /// <param name="listing">The listing of what was stored.</param>
    [TestMethod]
    [DataRow("applesoft", "IF SCORE > 5 THEN 100", "IF SC OR E>5 THEN 100")]
    [DataRow("applesoft", "for i=1to10:print i;:next", "FOR I=1 TO 10: PRINT I;: NEXT")]
    [DataRow("applesoft", "DRAW 1 AT 5,6", "DRAW 1 AT 5,6")]
    [DataRow("applesoft", "DATA  1, 2", "DATA  1, 2")]
    [DataRow("applesoft", "PRINT \"{CTRL-D}CATALOG\"", "PRINT \"{CTRL-D}CATALOG\"")]
    [DataRow("applesoft", "PRINT \"{{\"", "PRINT \"{{\"")]
    [DataRow("level2", "IF A THEN 10 ELSE 20", "IF A THEN 10 ELSE 20")]
    [DataRow("level2", "A=1 'note", "A=1 'note")]
    [DataRow("level2", " PRINT  \"x\"", " PRINT  \"x\"")]
    public void ListingsRoundTrip(string dialect, string text, string listing)
    {
        BasicDialect basic = BasicDialect.FromName(dialect) ?? throw new AssertFailedException(dialect);
        byte[] tokens = basic.Tokenize(text);
        string listed = basic.Detokenize(tokens);
        listed.Should().Be(listing);
        basic.Tokenize(listed).Should().Equal(tokens);
    }

    /// <summary>
    ///  Bytes typing could not store still list as text that tokenizes back to them.
    /// </summary>
    /// <param name="dialect">The dialect's name.</param>
    /// <param name="hex">The stored bytes.</param>
    [TestMethod]
    [DataRow("applesoft", "9132")]
    [DataRow("applesoft", "BA6162")]
    [DataRow("applesoft", "3F20FF")]
    [DataRow("level2", "95")]
    [DataRow("level2", "B222FC22")]
    public void OddBytesRoundTrip(string dialect, string hex)
    {
        BasicDialect basic = BasicDialect.FromName(dialect) ?? throw new AssertFailedException(dialect);
        byte[] bytes = Convert.FromHexString(hex);
        basic.Tokenize(basic.Detokenize(bytes)).Should().Equal(bytes);
    }

    /// <summary>
    ///  Text that cannot be typed is reported with its column.
    /// </summary>
    /// <param name="text">The text.</param>
    [TestMethod]
    [DataRow("PRINT \"é\"")]
    [DataRow("PRINT {NOPE}")]
    [DataRow("PRINT {$00}")]
    [DataRow("PRINT \"{")]
    public void BadTextIsReported(string text) =>
        FluentActions.Invoking(() => BasicDialect.AppleSoft.Tokenize(text)).Should().Throw<FormatException>().WithMessage("Column *");

    /// <summary>
    ///  A text program takes its dialect from a pragma, and is sorted with a warning; a repeated number is an error.
    /// </summary>
    [TestMethod]
    public void TextProgramsParse()
    {
        BasicParseResult parsed = BasicProgram.Parse("REM retrocore applesoft\n20 END\n\n10 HOME\n");
        parsed.Success.Should().BeTrue();
        parsed.Dialect.Should().Be(BasicDialect.AppleSoft);
        parsed.Program?.Lines.Select(line => line.Number).Should().Equal(10, 20);
        parsed.SourceLines.Should().Equal(3, 1);
        parsed.Diagnostics.Should().ContainSingle().Which.Severity.Should().Be(BasicSeverity.Warning);
        parsed.Program?.ToText().Should().Be("10 HOME\n20 END\n");

        BasicProgram.Parse("10 CLS\n10 END\n20 PRINT", path: "game.level2.bas").Diagnostics
            .Select(diagnostic => diagnostic.Line).Should().Equal(1);

        BasicProgram.Parse("10 HOME").Success.Should().BeFalse("no dialect is named");
        BasicProgram.Parse("10 REM retrocore level2\n20 CLS").Program?.Lines.Should().HaveCount(2, "a numbered pragma is kept");
        BasicProgram.Parse("10 HOME", BasicDialect.AppleSoftOriginal).Dialect.Should().Be(BasicDialect.AppleSoftOriginal);
    }

    /// <summary>
    ///  Tokenized files link their lines for the load address, and read back without trusting the links.
    /// </summary>
    [TestMethod]
    public void ImagesRoundTrip()
    {
        BasicProgram program = Program("applesoft", "10 HOME\n20 END\n");
        byte[] image = program.ToImage();
        Convert.ToHexString(image).Should().Be("07080A0097000D08140080000000");
        BasicProgram.FromImage(BasicDialect.AppleSoft, image).ToText().Should().Be("10 HOME\n20 END\n");

        // A Level II Disk BASIC file starts with $FF.
        BasicProgram level2 = Program("level2", "10 CLS\n20 END\n");
        BasicProgram.FromImage(BasicDialect.Level2, [0xFF, .. level2.ToImage(0x6A00)]).ToText().Should().Be("10 CLS\n20 END\n");

        BasicProgram.FromImage(BasicDialect.Level2, BasicTape.Write(level2, 'A').AsSpan(BasicTapeHeader)).Lines.Should().HaveCount(2);
        BasicTape.Read(BasicTape.Write(level2, 'A'), out char name).ToText().Should().Be("10 CLS\n20 END\n");
        name.Should().Be('A');
    }

    /// <summary>
    ///  Writing a program into memory sets the pointers after it and clears the variables, and reads back.
    /// </summary>
    [TestMethod]
    public void ProgramsWriteToMemory()
    {
        byte[] ram = new byte[0x10000];
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        BasicPointers pointers = BasicDialect.AppleSoft.Pointers;
        Word(ram, pointers.ProgramStart, 0x0801);
        Word(ram, pointers.MemoryTop, 0x9600);
        BasicProgram program = Program("applesoft", "10 HOME\n20 PRINT \"HI\"\n");
        program.Write(memory);

        int end = 0x0801 + program.ToImage(0x0801).Length;
        foreach (int pointer in (int[])[pointers.Variables, pointers.Arrays, pointers.FreeStart, 0xAF])
        {
            (ram[pointer] | (ram[pointer + 1] << 8)).Should().Be(end);
        }

        (ram[pointers.StringBottom] | (ram[pointers.StringBottom + 1] << 8)).Should().Be(0x9600);
        (ram[pointers.DataPointer] | (ram[pointers.DataPointer + 1] << 8)).Should().Be(0x0800);
        BasicProgram.Read(BasicDialect.AppleSoft, memory).ToText().Should().Be(program.ToText());

        Word(ram, pointers.MemoryTop, 0x0808);
        FluentActions.Invoking(() => program.Write(memory)).Should().Throw<InvalidOperationException>();
    }

    private static BasicProgram Program(string dialect, string text) =>
        BasicProgram.Parse(text, BasicDialect.FromName(dialect)).Program ?? throw new AssertFailedException(text);

    private static void Word(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }

    /// <summary>
    ///  Color BASIC's reserved words are Color, Extended and Disk BASIC's tables, in token order, from the SDK's
    ///  sources: the commands from $80 and the functions from $FF $80.
    /// </summary>
    [TestMethod]
    public void ColorBasicKeywordsMatchTheRoms()
    {
        string roms = Path.Join(s_inputs, "Coco");
        AssemblyResult color = CocoSdkModules.AssembleColorBasic(Path.Join(roms, "ColorBasic.asm"), 12);
        AssemblyResult extended = CocoSdkModules.AssembleExtendedBasic(Path.Join(roms, "ExtendedBasic.asm"), 11);
        AssemblyResult disk = CocoSdkModules.AssembleDiskBasic(Path.Join(roms, "DiskBasic.asm"), 11);
        List<string> commands = [.. Table(color, "COMWRD", 53), .. Table(extended, "XCOMWRD", 25), .. Table(disk, "DCOMWRD", 20)];
        List<string> functions = [.. Table(color, "FUNWRD", 20), .. Table(extended, "XFUNWRD", 14), .. Table(disk, "DFUNWRD", 6)];
        commands.Should().Equal(BasicDialect.ColorBasic.Keywords);
        functions.Should().Equal(BasicDialect.ColorBasic.Functions);

        // A ROM's words, counted: the tables run on into their routines' addresses.
        static List<string> Table(AssemblyResult rom, string label, int count)
        {
            int origin = rom.Sections[0].Origin;
            List<string> words = RomWords(rom.Sections[0].Bytes.Span[((int)rom.Symbols[label] - origin)..], lastLetterMarked: true);
            return words[..count];
        }
    }

    // Reads a ROM's reserved word list: AppleSoft marks each word's last letter, Level II each word's first.
    private static List<string> RomWords(ReadOnlySpan<byte> table, bool lastLetterMarked)
    {
        List<string> words = [];
        List<char> word = [];
        int index = 0;
        while (true)
        {
            byte value = table[index++];
            if (lastLetterMarked)
            {
                if (value == 0) { break; }
                word.Add((char)(value & 0x7F));
                if (value >= 0x80)
                {
                    words.Add(new string([.. word]));
                    word.Clear();
                }

                continue;
            }

            if (value >= 0x80 && word.Count > 0)
            {
                words.Add(new string([.. word]));
                word.Clear();
            }

            if (value == 0x80) { break; }
            word.Add((char)(value & 0x7F));
        }

        return words;
    }
}
