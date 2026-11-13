// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Business BASIC's dialect: its reserved words against the interpreter's tables, its tokenizer, its program files
///  and reading a program through banked pointers.
/// </summary>
[TestClass]
public sealed class BusinessBasicDialectTests
{
    private static BasicDialect Dialect => BasicDialect.BusinessBasic;

    /// <summary>
    ///  Both reserved word lists are the interpreter's, from the SDK's source: each word where its token is, and the
    ///  placeholders, which no text can match, empty.
    /// </summary>
    [TestMethod]
    public void ReservedWordsMatchTheInterpreter()
    {
        AssemblyResult result = Interpreter();
        byte[] image = result.Sections[0].Bytes.ToArray();
        int Offset(string name) => (int)result.Symbols[name] - 0x51F2;

        Words(image, Offset("RESLST"), Offset("RESL2")).Should().Equal(Dialect.Keywords);
        Words(image, Offset("RESL2"), Offset("OPTAB")).Should().Equal(BusinessBasicDialect.Instance.Functions);

        // The tokens the tokenizer and listing depend on.
        Dialect.Keywords[(int)result.Symbols["REMTK"] - 0x80].Should().Be("REM");
        Dialect.Keywords[(int)result.Symbols["DATATK"] - 0x80].Should().Be("DATA");
        Dialect.Keywords[(int)result.Symbols["PRINTK"] - 0x80].Should().Be("PRINT");
        Dialect.Keywords[(int)result.Symbols["IMAGETK"] - 0x80].Should().Be("IMAGE");
        Dialect.Keywords[(int)result.Symbols["EXFNSTK"] - 0x80].Should().Be("EXFN%.");
        BusinessBasicDialect.Instance.Functions[(int)result.Symbols["FNTK"] - 0x80].Should().Be("FN");
        result.Symbols["SCRATK"].Should().Be(0x80 + Dialect.Keywords.Count - 1);
    }

    /// <summary>
    ///  The tokenizer: reserved words need separators around them, so names may hold them; second-list words are $FF
    ///  and a token; `?` is PRINT, `!` is REM; spaces are dropped outside quotes, REM and DATA.
    /// </summary>
    /// <param name="text">The text after a line number.</param>
    /// <param name="hex">The tokens.</param>
    [TestMethod]
    [DataRow(" PRINT X", "D9 58")]
    [DataRow(" print x", "D9 78")]
    [DataRow(" SCORE=1", "53 43 4F 52 45 3D 31")]
    [DataRow(" PRINTER=1", "50 52 49 4E 54 45 52 3D 31")]
    [DataRow(" FOR I=1 TO 10", "81 49 3D 31 FF 81 31 30")]
    [DataRow(" ?A$", "D9 41 24")]
    [DataRow(" A$=TIME$", "41 24 3D 9F")]
    [DataRow(" X=EXFN.SUM(1)", "58 3D A2 53 55 4D 28 31 29")]
    [DataRow(" Y=FNA(2)", "59 3D FF 8D 41 28 32 29")]
    [DataRow(" ! A NOTE", "C0 20 41 20 4E 4F 54 45")]
    [DataRow(" DATA 1, A B:PRINT", "D4 20 31 2C 20 41 20 42 3A D9")]
    [DataRow(" PRINT \"A  B\"", "D9 22 41 20 20 42 22")]
    [DataRow(" IF A THEN 10 ELSE 20", "BB 41 FF 84 31 30 DB 32 30")]
    [DataRow(" GOTO100", "47 4F 54 4F 31 30 30")]
    public void Tokenizes(string text, string hex) =>
        Convert.ToHexString(Dialect.Tokenize(text)).Should().Be(hex.Replace(" ", "", StringComparison.Ordinal));

    /// <summary>
    ///  A listing puts spaces where the tokenizer needs separators, and reads back to the same tokens.
    /// </summary>
    [TestMethod]
    public void ListingReadsBack()
    {
        byte[] tokens = Dialect.Tokenize(" FOR I=1 TO 10 STEP 2:A$=MID$(B$,I,1):IF A$=\"X\" THEN GOTO 100 ELSE PRINT A$");
        string text = Dialect.Detokenize(tokens);
        text.Should().Be("FOR I=1 TO 10 STEP 2:A$=MID$(B$,I,1):IF A$=\"X\" THEN GOTO 100 ELSE PRINT A$");
        Dialect.Tokenize(" " + text).Should().Equal(tokens);
    }

    /// <summary>
    ///  Flat addresses run from page $81 of one bank pair into page $02 of the next, as BASIC's pointers do.
    /// </summary>
    [TestMethod]
    public void FlatAddressesRunAcrossBanks()
    {
        int last = BusinessBasicDialect.Flat(0x81, 0x81FF);
        BusinessBasicDialect.Split(last + 1).Should().Be(((byte)0x82, 0x0200));
        BusinessBasicDialect.Flat(0x82, 0x0200).Should().Be(last + 1);
        BusinessBasicDialect.Split(BusinessBasicDialect.Flat(0x83, 0x1234)).Should().Be(((byte)0x83, 0x1234));
        BusinessBasicDialect.Split(0x5308).Should().Be(((byte)0, 0x5308));
    }

    /// <summary>
    ///  A program in memory is read through TXTTAB's and ARYTAB's X-bytes, across a bank pair's end.
    /// </summary>
    [TestMethod]
    public void ReadsAProgramAcrossBanks()
    {
        BasicProgram program = new(Dialect, [new(10, Dialect.Tokenize(" PRINT \"HELLO\"")), new(20, Dialect.Tokenize(" GOTO 10"))]);
        byte[] image = program.ToImage()[2..];
        BankedBasicMemory memory = new();
        int start = BusinessBasicDialect.Flat(0x81, 0x81F8);
        for (int index = 0; index < image.Length; index++) { memory.WriteFlat(start + index, image[index]); }
        memory.SetPointer(0x1A39, start);
        memory.SetPointer(0x1A3D, start + image.Length);

        BasicProgram read = BasicProgram.Read(Dialect, memory);
        read.ToText().Should().Be("10 PRINT\"HELLO\"\n20 GOTO 10\n");
    }

    /// <summary>
    ///  A program written into memory goes at TXTTAB, across a bank pair's end, and leaves BASIC as a typed line does:
    ///  no variables or strings, DATA from the start, and no CONT.
    /// </summary>
    [TestMethod]
    public void WritesAProgramAcrossBanks()
    {
        BankedBasicMemory memory = new();
        int start = BusinessBasicDialect.Flat(0x81, 0x81FA);
        int top = BusinessBasicDialect.Flat(0x83, 0x7000);
        memory.SetPointer(0x1A39, start);
        memory.SetPointer(0x1A49, top);
        memory.Write(0x1650, 0x81);
        BasicProgram program = new(Dialect, [new(10, Dialect.Tokenize(" PRINT \"HELLO\"")), new(20, Dialect.Tokenize(" GOTO 10"))]);

        program.Write(memory);

        int end = start + program.ToImage().Length - 2;
        BasicProgram.Read(Dialect, memory).ToText().Should().Be("10 PRINT\"HELLO\"\n20 GOTO 10\n");
        int Pointer(int at) => BusinessBasicDialect.Pointer(memory, at);
        (Pointer(0x1A3D), Pointer(0x1A3B), Pointer(0x1A3F)).Should().Be((end, end, end), "ARYTAB, VARTAB and STREND");
        Pointer(0x1A41).Should().Be(top, "FRETOP is HIMEM");
        Pointer(0x1A53).Should().Be(start - 1, "DATA reads from the start");
        memory.Read(0x1650).Should().Be(0, "CONT is not allowed");
    }

    /// <summary>
    ///  A name runs to the 64 characters PTRGET takes, a type character among them, and its entry reads back; one
    ///  longer is refused.
    /// </summary>
    [TestMethod]
    public void NamesRunTo64Characters()
    {
        BasicVariables variables = new(Dialect, EmptyProgram(out _));
        string real = "R" + new string('.', 62) + "L";
        string integer = new string('I', 63) + "%";
        variables.Create(real);
        variables.Create(integer);
        variables.Create("NEXT.ONE");
        variables.Simple().Select(variable => variable.Name).Should().Equal(real, integer, "NEXT.ONE");
        variables.Find(real).Should().NotBeNull();

        Action tooLong = () => variables.Create(new string('I', 64) + "%");
        tooLong.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  A string with no room for it leaves the variable's old string where it was, still in use.
    /// </summary>
    [TestMethod]
    public void AStringThatDoesNotFitKeepsTheOld()
    {
        BasicVariables variables = new(Dialect, EmptyProgram(out BankedBasicMemory memory));
        BasicVariable name = variables.Create("N$");
        variables.Write(name.Kind, name.ValueAddress, BasicValue.Of("AB"u8.ToArray()));
        int bottom = BusinessBasicDialect.Pointer(memory, 0x1A41);
        byte information = memory.Read(bottom + 2);

        // Leave room for only a few more characters below the string.
        memory.SetPointer(0x1A3F, bottom - 6);
        Action write = () => variables.Write(name.Kind, name.ValueAddress, BasicValue.Of("TOO LONG"u8.ToArray()));
        write.Should().Throw<InvalidOperationException>().WithMessage("?OUT OF MEMORY*");

        variables.Read(name.Kind, name.ValueAddress).Text.Should().Equal("AB"u8.ToArray());
        memory.Read(bottom + 2).Should().Be(information, "the old string is not marked free");
    }

    /// <summary>
    ///  The programs on Apple's Business BASIC 1.23 disk read from their files and list as text that tokenizes back
    ///  to the same lines.
    /// </summary>
    [TestMethod]
    public void DiskProgramsListAndReadBack()
    {
        SosVolume volume = SosVolumeTests.Volume("Apple3BusBasic1.23.dsk");
        List<SosFileEntry> programs = [.. volume.Files.Where(file => file.FileType == 0x09)];
        programs.Should().HaveCountGreaterThan(5);
        foreach (SosFileEntry file in programs)
        {
            BasicProgram program = BasicProgram.FromImage(Dialect, volume.ReadFile(file.Name));
            program.Lines.Should().NotBeEmpty(file.Name);
            foreach (BasicLine line in program.Lines)
            {
                string text = Dialect.Detokenize(line.Tokens.Span);
                text.Should().NotContain("{$", $"{file.Name} line {line.Number} lists without escapes");
                Dialect.Tokenize(" " + text).Should().Equal(line.Tokens.ToArray(), $"{file.Name} line {line.Number}");
            }
        }

        BasicProgram hello = BasicProgram.FromImage(Dialect, volume.ReadFile("HELLO"));
        hello.ToImage()[2..^3].Should().Equal(volume.ReadFile("HELLO")[2..^3]);
    }

    // The words of a reserved word list, each ending with bit 7 set; a placeholder (an A and spaces) is empty.
    private static List<string> Words(byte[] image, int start, int end)
    {
        List<string> words = [];
        string word = "";
        for (int index = start; index < end; index++)
        {
            word += (char)(image[index] & 0x7F);
            if ((image[index] & 0x80) == 0) { continue; }
            words.Add(word.TrimEnd() == "A" && word.Length > 1 ? "" : word);
            word = "";
        }

        return words;
    }

    // Memory with an empty program in bank pair $81, string space up to HIMEM in the next.
    private static BankedBasicMemory EmptyProgram(out BankedBasicMemory memory)
    {
        memory = new();
        int start = BusinessBasicDialect.Flat(0x81, 0x2000);
        int top = BusinessBasicDialect.Flat(0x82, 0x7000);
        memory.SetPointer(0x1A39, start);
        memory.SetPointer(0x1A3D, start + 3);
        memory.SetPointer(0x1A3B, start + 3);
        memory.SetPointer(0x1A3F, start + 3);
        memory.SetPointer(0x1A41, top);
        memory.SetPointer(0x1A49, top);
        return memory;
    }

    private static AssemblyResult Interpreter()
    {
        string path = Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "BusinessBasic", "BusinessBasic.asm");
        if (!File.Exists(path)) { Assert.Inconclusive("The Business BASIC source is not in the test inputs."); }
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0x51F2, 25963)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        result.Diagnostics.Should().BeEmpty();
        return result;
    }
}
