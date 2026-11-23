// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Runs the converted program and statement modules' routines (Basic.md, B1) in the shipped AppleSoft and PET
///  BASIC 4 builds and checks what their documentation says they take, return and keep.
/// </summary>
[TestClass]
public sealed class BasicStatementRoutineTests
{
    // Where a test puts its text and its program.
    private const int Text = 0x0900;
    private const int Program = 0x0A01;

    // The values a routine that keeps X and Y must hand back.
    private const int KeptX = 0x5A;
    private const int KeptY = 0xA5;

    /// <summary>
    ///  <c>IsLetter</c> sets carry for A through Z only: not for the characters either side of them, a lowercase
    ///  letter, or a letter with bit 7 set; it keeps A, X and Y.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="character">The character in A.</param>
    /// <param name="letter">Whether it is an uppercase letter.</param>
    [TestMethod]
    [DataRow(true, '@', false)]
    [DataRow(true, 'A', true)]
    [DataRow(true, 'M', true)]
    [DataRow(true, 'Z', true)]
    [DataRow(true, '[', false)]
    [DataRow(true, 'a', false)]
    [DataRow(true, (char)0xC1, false)]
    [DataRow(false, '@', false)]
    [DataRow(false, 'A', true)]
    [DataRow(false, 'Z', true)]
    [DataRow(false, '[', false)]
    [DataRow(false, 'a', false)]
    [DataRow(false, (char)0xC1, false)]
    public void IsLetterSetsCarryForUppercaseLetters(bool apple, char character, bool letter)
    {
        BasicMathMachine machine = new(apple);
        machine.Call("IsLetter", a: character, x: KeptX, y: KeptY, carry: !letter);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(letter);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)character);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  The character reader, copied from its template to page zero as startup copies it, advances
    ///  <c>TextPointer</c> past spaces to the next character and returns it in A, with carry clear only for a digit and
    ///  zero set only for a null or a colon, keeping X and Y.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="text">The text after the current character.</param>
    /// <param name="expected">The character returned.</param>
    /// <param name="skipped">The spaces skipped before it.</param>
    [TestMethod]
    [DataRow(true, "5", '5', 0)]
    [DataRow(true, "  0", '0', 2)]
    [DataRow(true, " 9", '9', 1)]
    [DataRow(true, ":", ':', 0)]
    [DataRow(true, " \0", '\0', 1)]
    [DataRow(true, "A", 'A', 0)]
    [DataRow(true, "!", '!', 0)]
    [DataRow(true, "/", '/', 0)]
    [DataRow(true, ";", ';', 0)]
    [DataRow(false, "  7", '7', 2)]
    [DataRow(false, ":", ':', 0)]
    [DataRow(false, "\0", '\0', 0)]
    [DataRow(false, "Z", 'Z', 0)]
    public void CharacterReaderSkipsSpacesAndClassifies(bool apple, string text, char expected, int skipped)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        PutText(machine, " " + text);
        SetWord(machine, "TextPointer", Text);

        machine.Call("GetNextCharacter", x: KeptX, y: KeptY);

        StatusRegister status = machine.Cpu.Registers.Status;
        machine.Cpu.Registers.Accumulator.Should().Be((byte)expected);
        Word(machine, "TextPointer").Should().Be(Text + 1 + skipped);
        status.HasFlag(StatusRegister.Carry).Should().Be(expected is < '0' or > '9', "carry is clear only for a digit");
        status.HasFlag(StatusRegister.Zero).Should().Be(expected is '\0' or ':', "zero is set only for a null or colon");
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  The character reader's second entry, <c>GetCurrentCharacter</c>, returns the character at <c>TextPointer</c>
    ///  without advancing to it first, but skips spaces from there, which advances the pointer.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="text">The text from <c>TextPointer</c>.</param>
    /// <param name="expected">The character returned.</param>
    /// <param name="skipped">The spaces skipped before it.</param>
    [TestMethod]
    [DataRow(true, "A", 'A', 0)]
    [DataRow(true, "  A", 'A', 2)]
    [DataRow(true, ":", ':', 0)]
    [DataRow(false, "7", '7', 0)]
    [DataRow(false, " 7", '7', 1)]
    public void GetCurrentCharacterStaysUnlessItSkipsSpaces(bool apple, string text, char expected, int skipped)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        PutText(machine, text);
        SetWord(machine, "TextPointer", Text);

        machine.Call("GetCurrentCharacter", x: KeptX, y: KeptY);

        machine.Cpu.Registers.Accumulator.Should().Be((byte)expected);
        Word(machine, "TextPointer").Should().Be(Text + skipped);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  <c>ReadLineNumber</c> reads the digits from the current character on, skipping the spaces the character reader
    ///  skips, into <c>LineNumber</c>, and returns at the terminator with it in A and carry set.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="text">The text, starting at the current character.</param>
    /// <param name="number">The line number.</param>
    /// <param name="terminator">The offset of the terminator in the text.</param>
    [TestMethod]
    [DataRow(true, "1234:", 1234, 4)]
    [DataRow(true, "0\0", 0, 1)]
    [DataRow(true, "63999,", 63999, 5)]
    [DataRow(true, "1 2 3-", 123, 5)]
    [DataRow(true, "X", 0, 0)]
    [DataRow(false, "10\0", 10, 2)]
    [DataRow(false, "6400:", 6400, 4)]
    public void ReadLineNumberReturnsTheNumberAndTerminator(bool apple, string text, int number, int terminator)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        PutText(machine, text);
        SetWord(machine, "TextPointer", Text);

        machine.Call("ReadLineNumber", a: text[0], carry: !char.IsAsciiDigit(text[0]));

        Word(machine, "LineNumber").Should().Be(number);
        Word(machine, "TextPointer").Should().Be(Text + terminator);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)text[terminator]);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(
            terminator == 0 || text[terminator] is '\0' or ':', "zero is set when no digit was read or at a null or colon");
    }

    /// <summary>
    ///  Before adding a digit to a value of 6400 or more, <c>ReadLineNumber</c> branches to ON's GOTO test with the
    ///  value's high byte in A: a high byte other than the GOTO token is a syntax error, but one equal to it (43776 to
    ///  44031 in AppleSoft, 35072 to 35327 on the PET) goes on into ON's selection loop.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="text">The digits.</param>
    /// <param name="intoOn">Whether the number reaches ON's loop rather than the syntax error.</param>
    [TestMethod]
    [DataRow(true, "437760", true)]
    [DataRow(true, "440319", true)]
    [DataRow(true, "440320", false)]
    [DataRow(true, "64000", false)]
    [DataRow(false, "350720", true)]
    [DataRow(false, "353280", false)]
    public void ReadLineNumberSendsAGotoTokenHighByteIntoOn(bool apple, string text, bool intoOn)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        PutText(machine, text + "\0");
        SetWord(machine, "TextPointer", Text);
        int loop = machine.Address("ONGLOP");
        int syntaxError = machine.Address("SNERR2");

        int reached = machine.CallUntil("ReadLineNumber", [loop, syntaxError], a: text[0], carry: false);

        reached.Should().Be(intoOn ? loop : syntaxError);
        Word(machine, "TextPointer").Should().Be(Text + text.Length - 1, "the last digit is the one not added");
    }

    /// <summary>
    ///  <c>EraseProgram</c> stores a zero link at <c>ProgramStart</c> and sets <c>VariablesStart</c> two bytes on in PET
    ///  BASIC 4, which clears carry first, but adds the incoming carry too in AppleSoft, so its <c>NEW</c>, which
    ///  arrives with carry set, leaves three.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="carry">The incoming carry.</param>
    /// <param name="offset">How far past <c>ProgramStart</c> the variables start.</param>
    [TestMethod]
    [DataRow(true, false, 2)]
    [DataRow(true, true, 3)]
    [DataRow(false, false, 2)]
    [DataRow(false, true, 2)]
    public void EraseProgramAddsTheCarryWhereTheBuildKeepsIt(bool apple, bool carry, int offset)
    {
        BasicMathMachine machine = new(apple);
        machine.Memory.AsSpan(Program, 2).Fill(0xEE);
        SetWord(machine, "ProgramStart", Program);
        SetWord(machine, "VariablesStart", 0);

        int reached = machine.CallUntil("EraseProgram", [machine.Address("ResetProgramState")], carry: carry);

        reached.Should().Be(machine.Address("ResetProgramState"), "it falls into ResetProgramState");
        machine.Memory.AsSpan(Program, 2).ToArray().Should().Equal(0, 0);
        Word(machine, "VariablesStart").Should().Be(Program + offset);
    }

    /// <summary>
    ///  GOTO searches from just past the current statement only when the target's high byte is greater than the
    ///  current line's; a forward jump within the same 256-line block, or a backward one, searches from
    ///  <c>ProgramStart</c>.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="current">The current line number.</param>
    /// <param name="target">The target line number.</param>
    /// <param name="fromStart">Whether the search starts at <c>ProgramStart</c>.</param>
    [TestMethod]
    [DataRow(true, 10, 300, false)]
    [DataRow(true, 10, 200, true)]
    [DataRow(true, 300, 5, true)]
    [DataRow(true, 300, 400, true)]
    [DataRow(false, 10, 300, false)]
    [DataRow(false, 10, 200, true)]
    public void GotoSearchesOnOnlyForALaterBlock(bool apple, int current, int target, bool fromStart)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        string text = target.ToString(System.Globalization.CultureInfo.InvariantCulture) + "\0";
        PutText(machine, text);
        SetWord(machine, "TextPointer", Text);
        SetWord(machine, "ProgramStart", Program);
        SetWord(machine, "CurrentLine", current);
        int search = machine.Address("FindLine::FromAddress");

        int reached = machine.CallUntil("Statements::GoTo", [search], a: text[0], carry: false);

        reached.Should().Be(search);
        int from = machine.Cpu.Registers.Accumulator | (machine.Cpu.Registers.X << 8);
        from.Should().Be(fromStart ? Program : Text + text.Length, "past the statement is just past its terminator");
    }

    /// <summary>
    ///  <c>FindLine</c> leaves <c>SourceStart</c> at the line equal to or after <c>LineNumber</c>, or at the end
    ///  marker, with carry set only for an exact match.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="number">The line number to find.</param>
    /// <param name="index">The line found: 0 to 2, or 3 for the end marker.</param>
    /// <param name="exact">Whether the line has that number.</param>
    [TestMethod]
    [DataRow(true, 5, 0, false)]
    [DataRow(true, 10, 0, true)]
    [DataRow(true, 20, 1, true)]
    [DataRow(true, 25, 2, false)]
    [DataRow(true, 30, 2, true)]
    [DataRow(true, 31, 3, false)]
    [DataRow(true, 65535, 3, false)]
    [DataRow(false, 20, 1, true)]
    [DataRow(false, 11, 1, false)]
    [DataRow(false, 40, 3, false)]
    public void FindLineStopsAtTheLineOrTheOneAfter(bool apple, int number, int index, bool exact)
    {
        BasicMathMachine machine = new(apple);
        int[] lines = PutProgram(machine, [10, 20, 30]);
        SetWord(machine, "LineNumber", number);

        machine.Call("FindLine", carry: !exact);

        Word(machine, "SourceStart").Should().Be(lines[index]);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(exact);
    }

    /// <summary>
    ///  <c>FindStatementEnd</c> returns in Y the offset from <c>TextPointer</c> of the first colon outside quotes, or
    ///  of the line's zero; <c>FindLineEnd</c> returns the zero's, past any colon. Both return the terminator in A, with
    ///  zero set; carry is whatever the last comparison left, so it is not a result.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="routine">The routine.</param>
    /// <param name="text">The text from <c>TextPointer</c>.</param>
    /// <param name="offset">The terminator's offset.</param>
    [TestMethod]
    [DataRow(true, "FindStatementEnd", "AB:C\0", 2)]
    [DataRow(true, "FindStatementEnd", "A\"B:C\":D\0", 6)]
    [DataRow(true, "FindStatementEnd", "A\"B:C\0", 5)]
    [DataRow(true, "FindStatementEnd", "ABC\0", 3)]
    [DataRow(true, "FindLineEnd", "AB:C\0", 4)]
    [DataRow(true, "FindLineEnd", "A\"B\0", 3)]
    [DataRow(true, "FindLineEnd", "A \0", 2)]
    [DataRow(true, "FindStatementEnd", "A !\0", 3)]
    [DataRow(false, "FindStatementEnd", "A\"B:C\":D\0", 6)]
    [DataRow(false, "FindLineEnd", "A:B:C\0", 5)]
    public void ScansStopAtTheirTerminator(bool apple, string routine, string text, int offset)
    {
        BasicMathMachine machine = new(apple);
        PutText(machine, text);
        SetWord(machine, "TextPointer", Text);

        machine.Call(routine, y: 0xFF);

        machine.Cpu.Registers.Y.Should().Be((byte)offset);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)text[offset], "A is the terminator");
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeTrue();
        Word(machine, "TextPointer").Should().Be(Text, "the scan leaves the pointer for the caller to advance");
    }

    // Copies the character reader's template where startup copies it, as the build's own copy loop does.
    private static void InstallCharacterReader(BasicMathMachine machine)
    {
        int template = machine.Address("CharacterReaderTemplate");
        int reader = machine.Address("GetNextCharacter");
        machine.Memory.AsSpan(template, 24).CopyTo(machine.Memory.AsSpan(reader));
        (reader + 7).Should().Be(machine.Address("TextPointer"), "the copy's load operand is the text pointer");
    }

    private static void PutText(BasicMathMachine machine, string text)
    {
        for (int index = 0; index < text.Length; index++)
        {
            machine.Memory[Text + index] = (byte)text[index];
        }
    }

    // Stores lines of one statement byte each from Program, linked, then the end marker; returns each line's
    // address and the end marker's.
    private static int[] PutProgram(BasicMathMachine machine, int[] numbers)
    {
        int[] addresses = new int[numbers.Length + 1];
        int address = Program;
        for (int line = 0; line < numbers.Length; line++)
        {
            addresses[line] = address;
            int next = address + 6;
            machine.Memory[address] = (byte)next;
            machine.Memory[address + 1] = (byte)(next >> 8);
            machine.Memory[address + 2] = (byte)numbers[line];
            machine.Memory[address + 3] = (byte)(numbers[line] >> 8);
            machine.Memory[address + 4] = 0x99;
            machine.Memory[address + 5] = 0;
            address = next;
        }

        addresses[^1] = address;
        machine.Memory[address] = 0;
        machine.Memory[address + 1] = 0;
        SetWord(machine, "ProgramStart", Program);
        return addresses;
    }

    private static void SetWord(BasicMathMachine machine, string name, int value)
    {
        int address = machine.Address(name);
        machine.Memory[address] = (byte)value;
        machine.Memory[address + 1] = (byte)(value >> 8);
    }

    private static int Word(BasicMathMachine machine, string name)
    {
        int address = machine.Address(name);
        return machine.Memory[address] | (machine.Memory[address + 1] << 8);
    }
}
