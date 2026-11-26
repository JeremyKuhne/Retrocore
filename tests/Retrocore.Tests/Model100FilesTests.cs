// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Trs80Model100;

namespace Retrocore.Tests;

/// <summary>
///  The files in the Model 100's RAM: listed, read, written and removed as the ROM keeps them.
/// </summary>
[TestClass]
public sealed class Model100FilesTests
{
    // The directory and file area of a 32 KB Model 100 at the menu after a cold start (read from RAM, 2026-11-26):
    // the ROM's five programs, BASIC's unsaved program (Suzuki), the paste buffer (Hayashi) and RickY.
    private const string ColdDirectory =
        "B0496C4241534943202000B0EE5D5445585420202000B0465154454C434F4D2000B0685B4144445253532000"
            + "B06F5B53434845444C20008801800053757A756B6920C803800048617961736869480000005269636B592020";

    // The same machine after BASIC saved PROG.BA (10 PRINT "HI":A=1'C), SAVEM saved MC.CO (63000-63009, entry 63002),
    // a program wrote NOTE.DO (ABC) and BASIC saved ZED.BA (10 ?1): the directory from its sixth entry, and the
    // file area from $8000 to the variables.
    private const string SavedDirectory =
        "881F800053757A756B6920C827800048617961736869480000005269636B59202080018050524F4720204241"
            + "A028804D4320202020434FC021804E4F54452020444F8016805A45442020204241";

    private const string SavedArea =
        "0014800A00A320224849223A41DD313A8EFF430000001D800A00A33100000000004142430D0A1A1A18F60A001AF6F6D3E82AA4FA"
            + "115443C3";

    private const string Program = "14800A00A320224849223A41DD313A8EFF43000000";
    private const string Machine = "18F60A001AF6F6D3E82AA4FA115443C3";

    /// <summary>
    ///  Wraps a machine's memory for the library, reading and writing RAM without side effects.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The memory.</returns>
    internal static IBasicMemory Memory(Trs80Model100Machine machine) =>
        new DelegateBasicMemory(address => machine.Bus.Peek((ushort)address), (address, value) => machine.Bus.Write((ushort)address, value));

    /// <summary>
    ///  Files written in the order the ROM saved them lie as the ROM left them, each kind in its region, the
    ///  directory's addresses and the region pointers moved with them, and BASIC on its unsaved program.
    /// </summary>
    [TestMethod]
    public void FilesLieAsTheRomSavedThem()
    {
        byte[] ram = ColdStart();
        Model100Files files = new(DelegateBasicMemory.Of(ram));
        files.Write("PROG.BA", Convert.FromHexString(Program));
        files.Write("MC.CO", Convert.FromHexString(Machine));
        files.Write("note.do", "ABC\r\n"u8);
        files.Write("ZED.BA", Model100FilesTests.Parse("10 ?1\n").ToImage());

        Convert.ToHexString(ram, 0xF962 + (5 * 11), 7 * 11).Should().Be(SavedDirectory);
        Convert.ToHexString(ram, 0x8000, Word(ram, 0xFBB2) - 0x8000).Should().Be(SavedArea);
        Word(ram, 0xFBAE).Should().Be(0x8021);
        Word(ram, 0xFBB0).Should().Be(0x8028);
        Word(ram, 0xFBB4).Should().Be(0x8038);
        Word(ram, 0xFBB6).Should().Be(0x8038);
        Word(ram, 0xF67C).Should().Be(0x801F, "BASIC's program pointer stays on its unsaved program");

        files.List().Should().Equal(
            new Model100File("PROG.BA", Model100FileType.Basic, 0x8001),
            new Model100File("MC.CO", Model100FileType.Machine, 0x8028),
            new Model100File("NOTE.DO", Model100FileType.Text, 0x8021),
            new Model100File("ZED.BA", Model100FileType.Basic, 0x8016));

        Convert.ToHexString(files.Read("PROG.BA")).Should().Be(Program);
        Convert.ToHexString(files.Read("mc.co")).Should().Be(Machine);
        files.Read("NOTE.DO").Should().Equal("ABC\r\n\x1A"u8.ToArray());
    }

    /// <summary>
    ///  Removing every file leaves the cold start's RAM, and a file of a name already in RAM replaces it.
    /// </summary>
    [TestMethod]
    public void RemovingAndReplacingRestoresTheLayout()
    {
        byte[] ram = ColdStart();
        byte[] cold = (byte[])ram.Clone();
        Model100Files files = new(DelegateBasicMemory.Of(ram));
        files.Write("PROG.BA", Convert.FromHexString(Program));
        files.Write("MC.CO", Convert.FromHexString(Machine));
        files.Write("NOTE.DO", "ABC"u8);
        files.Write("NOTE.DO", "LONGER TEXT\r\n"u8);
        files.List().Select(file => file.Name).Should().Equal("PROG.BA", "MC.CO", "NOTE.DO");
        files.Read("NOTE.DO").Should().Equal("LONGER TEXT\r\n\x1A"u8.ToArray());
        Convert.ToHexString(files.Read("MC.CO")).Should().Be(Machine, "the .CO file moved past the longer text");

        files.Delete("PROG.BA");
        files.Delete("NOTE.DO");
        files.Delete("MC.CO");
        files.List().Should().BeEmpty();
        Convert.ToHexString(ram, 0xF962, 27 * 11).Should().Be(Convert.ToHexString(cold, 0xF962, 27 * 11));
        Convert.ToHexString(ram, 0x8000, 4).Should().Be(Convert.ToHexString(cold, 0x8000, 4), "the file area up to the variables");
        foreach (int pointer in (int[])[0xF67C, 0xFBAE, 0xFBB0, 0xFBB2, 0xFBB4, 0xFBB6])
        {
            Word(ram, pointer).Should().Be(Word(cold, pointer));
        }
    }

    /// <summary>
    ///  A program written over the one BASIC has open moves the files after it, and a .BA file that moves is linked
    ///  again for its new address.
    /// </summary>
    [TestMethod]
    public void MovedProgramsAreLinkedAgain()
    {
        byte[] ram = ColdStart();
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        Model100Files files = new(memory);
        files.Write("ZED.BA", Model100FilesTests.Parse("10 PRINT 2\n20 PRINT 3\n").ToImage());
        files.Write("NOTE.DO", "X"u8);
        int unsaved = 0xF962 + (5 * 11) + 1;

        // BASIC's unsaved program gets lines, then BASIC opens ZED.BA, before it, as LOAD "ZED" does, and a longer
        // program is written over it.
        BasicProgram.WriteWord(memory, 0xF67C, Word(ram, unsaved));
        Model100FilesTests.Parse("1 END\n").Write(memory);
        BasicProgram.WriteWord(memory, 0xF67C, 0x8001);
        Model100FilesTests.Parse("5 REM A LONGER FIRST LINE\n10 PRINT 2\n20 PRINT 3\n").Write(memory);
        BasicProgram.Read(BasicDialect.Model100, memory).Lines.Select(line => line.Number).Should().Equal(5, 10, 20);
        files.Read("NOTE.DO").Should().Equal("X\x1A"u8.ToArray());

        // The unsaved program moved, and reads from its new place through its new links.
        BasicProgram.WriteWord(memory, 0xF67C, Word(ram, unsaved));
        BasicProgram.Read(BasicDialect.Model100, memory).Lines.Select(line => line.Number).Should().Equal(1);

        // Another .BA file goes before the unsaved program, which moves again.
        files.Write("ABC.BA", Model100FilesTests.Parse("100 STOP\n").ToImage());
        BasicProgram.Word(memory, 0xF67C).Should().Be(Word(ram, unsaved), "BASIC's pointer moved with its program");
        BasicProgram.Read(BasicDialect.Model100, memory).Lines.Select(line => line.Number).Should().Equal(1);
        files.Read("ZED.BA").Length.Should().Be(Model100FilesTests.Parse("5 REM A LONGER FIRST LINE\n10 PRINT 2\n20 PRINT 3\n").ToImage().Length);
    }

    /// <summary>
    ///  A file of a name already in RAM is replaced in its place, BASIC's open program too, and RAM is changed only once
    ///  the new one is known to fit; after a change to the open program BASIC's DATA pointer is before it and CONT is
    ///  cleared, as the ROM leaves them.
    /// </summary>
    [TestMethod]
    public void ReplacingKeepsThePlaceAndChecksTheRoomFirst()
    {
        byte[] ram = ColdStart();
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        Model100Files files = new(memory);
        files.Write("PROG.BA", Parse("10 PRINT 1\n").ToImage());
        files.Write("NOTE.DO", "ABC"u8);
        files.Write("MC.CO", Convert.FromHexString(Machine));
        BasicProgram.WriteWord(memory, 0xF67C, 0x8001);
        BasicProgram.WriteWord(memory, 0xFBAC, 0x8005);

        files.Write("PROG.BA", Parse("10 PRINT 1\n20 PRINT 2\n").ToImage());
        files.List().Select(file => file.Name).Should().Equal("PROG.BA", "NOTE.DO", "MC.CO");
        BasicProgram.Word(memory, 0xF67C).Should().Be(0x8001, "BASIC keeps its open program");
        BasicProgram.Read(BasicDialect.Model100, memory).Lines.Select(line => line.Number).Should().Equal(10, 20);
        Word(ram, 0xFBB8).Should().Be(0x8000, "DATA starts before BASIC's program");
        Word(ram, 0xFBAC).Should().Be(0, "CONT is cleared");

        byte[] before = (byte[])ram.Clone();
        ((Action)(() => files.Write("NOTE.DO", new byte[0x8000]))).Should().Throw<InvalidOperationException>().WithMessage("*bytes free*");
        ram.Should().Equal(before, "nothing changed, and the old NOTE.DO is still there");
        Convert.ToHexString(files.Read("MC.CO")).Should().Be(Machine);
    }

    /// <summary>
    ///  A file written or removed past the program BASIC has open keeps BASIC's variables, DATA pointer and CONT,
    ///  moving the variables with the files, as the ROM's OPEN and KILL do; one before it clears them.
    /// </summary>
    [TestMethod]
    public void ChangesPastTheOpenProgramKeepItsVariables()
    {
        byte[] ram = ColdStart();
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        Model100Files files = new(memory);
        files.Write("PROG.BA", Parse("10 READ A\n20 DATA 7\n").ToImage());
        BasicProgram.WriteWord(memory, 0xF67C, 0x8001);

        // Variables and arrays: any bytes do, seven for the variables and two for the arrays.
        int variables = Word(ram, 0xFBB2);
        byte[] variable = [0x04, 0x41, 0x00, 0x41, 0x70, 0x00, 0x00, 0x12, 0x34];
        variable.CopyTo(ram, variables);
        BasicProgram.WriteWord(memory, 0xFBB4, variables + 7);
        BasicProgram.WriteWord(memory, 0xFBB6, variables + variable.Length);
        BasicProgram.WriteWord(memory, 0xFBB8, 0x8008);
        BasicProgram.WriteWord(memory, 0xFBAC, 0x8006);

        files.Write("NOTE.DO", "ABC"u8);
        int moved = Word(ram, 0xFBB2);
        moved.Should().Be(variables + 4, "the variables follow NOTE.DO's four bytes");
        ram.AsSpan(moved, variable.Length).ToArray().Should().Equal(variable);
        Word(ram, 0xFBB4).Should().Be(moved + 7);
        Word(ram, 0xFBB6).Should().Be(moved + variable.Length);
        Word(ram, 0xFBB8).Should().Be(0x8008, "the DATA pointer is in the program, which did not move");
        Word(ram, 0xFBAC).Should().Be(0x8006);

        files.Delete("NOTE.DO");
        Word(ram, 0xFBB2).Should().Be(variables);
        ram.AsSpan(variables, variable.Length).ToArray().Should().Equal(variable);

        // BASIC's unsaved program is past PROG.BA, so with it open, removing PROG.BA, before it, clears them, as does
        // adding a .BA file, which goes in front of it.
        int unsaved = 0xF962 + (5 * 11) + 1;
        BasicProgram.WriteWord(memory, 0xF67C, Word(ram, unsaved));
        files.Delete("PROG.BA");
        Word(ram, 0xFBB6).Should().Be(Word(ram, 0xFBB2), "the variables are cleared");
        Word(ram, 0xFBAC).Should().Be(0);
        Word(ram, 0xF67C).Should().Be(Word(ram, unsaved), "BASIC's pointer moved with its program");
        Word(ram, 0xFBB8).Should().Be(Word(ram, unsaved) - 1);
        variable.CopyTo(ram, Word(ram, 0xFBB2));
        BasicProgram.WriteWord(memory, 0xFBB6, Word(ram, 0xFBB2) + variable.Length);
        files.Write("ZED.BA", Parse("10 END\n").ToImage());
        Word(ram, 0xFBB6).Should().Be(Word(ram, 0xFBB2), "the variables are cleared again");

        // With BASIC's pointer at no program, as in an image taken before BASIC ran, a change clears them too.
        variable.CopyTo(ram, Word(ram, 0xFBB2));
        BasicProgram.WriteWord(memory, 0xFBB6, Word(ram, 0xFBB2) + variable.Length);
        BasicProgram.WriteWord(memory, 0xF67C, 0);
        files.Write("LAST.DO", "X"u8);
        Word(ram, 0xFBB6).Should().Be(Word(ram, 0xFBB2), "with no program open, the variables are cleared");
    }

    /// <summary>
    ///  BASIC is at its prompt only when its current line is the direct mode's and BASIC is the program running, by
    ///  the name the ROM keeps at $FDD9; a program is written only over a .BA file or BASIC's unsaved program.
    /// </summary>
    [TestMethod]
    public void BasicIsAtItsPromptOnlyInBasic()
    {
        byte[] ram = ColdStart();
        IBasicMemory memory = DelegateBasicMemory.Of(ram);
        BasicProgram.WriteWord(memory, 0xF67A, 0xFFFF);
        foreach ((string running, bool prompt) in (ValueTuple<string, bool>[])[
            ("", false), ("TEXT", false), ("TELCOM", false), ("ADRS.DO", false), ("BASIC", true), ("PROG.BA", true)])
        {
            Array.Clear(ram, 0xFDD9, 9);
            System.Text.Encoding.ASCII.GetBytes(running).CopyTo(ram, 0xFDD9);
            BasicDialect.Model100.InDirectMode(memory).Should().Be(prompt, "with {0} running", running);
        }

        BasicProgram.WriteWord(memory, 0xF67A, 10);
        BasicDialect.Model100.InDirectMode(memory).Should().BeFalse("BASIC is running line 10");

        BasicProgram.WriteWord(memory, 0xF67C, 0x8003);
        ((Action)(() => Parse("10 END\n").Write(memory))).Should().Throw<InvalidOperationException>().WithMessage("*not at a .BA file*");
        BasicProgram.WriteWord(memory, 0xF67C, 0);
        ((Action)(() => Parse("10 END\n").Write(memory))).Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  Names and contents that are not a Model 100 file's are refused, as are a full directory, a lack of room and
    ///  removing the program BASIC has open.
    /// </summary>
    [TestMethod]
    public void BadFilesAreRefused()
    {
        byte[] ram = ColdStart();
        Model100Files files = new(DelegateBasicMemory.Of(ram));
        foreach (string name in (string[])["TOOLONG.BA", "1ST.BA", "A.TXT", "NOEXT", "A-B.DO"])
        {
            ((Action)(() => files.Write(name, "X"u8))).Should().Throw<ArgumentException>(name);
        }

        ((Action)(() => files.Write("A.CO", [0, 0xF0, 5, 0, 0, 0xF0, 1]))).Should().Throw<ArgumentException>("its length says 5 bytes");
        ((Action)(() => files.Write("A.BA", [0x10, 0x80, 10, 0]))).Should().Throw<InvalidDataException>("the line never ends");
        ((Action)(() => files.Read("GONE.DO"))).Should().Throw<FileNotFoundException>();
        ((Action)(() => files.Write("BIG.DO", new byte[0x8000]))).Should().Throw<InvalidOperationException>().WithMessage("*bytes free*");

        for (int index = 0; index < 19; index++) { files.Write($"F{index}.DO", "X"u8); }
        ((Action)(() => files.Write("LAST.DO", "X"u8))).Should().Throw<InvalidOperationException>().WithMessage("*directory is full*");

        files.Delete("F0.DO");
        files.Write("OPEN.BA", Model100FilesTests.Parse("10 END\n").ToImage());
        BasicProgram.WriteWord(DelegateBasicMemory.Of(ram), 0xF67C, 0x8001);
        ((Action)(() => files.Delete("OPEN.BA"))).Should().Throw<InvalidOperationException>().WithMessage("*open*");
    }

    /// <summary>
    ///  Files written into a Model 100's RAM at the menu lie byte for byte as the ROM's own SAVE, SAVEM and OPEN leave
    ///  them, and the ROM runs and reads them; inconclusive without the user's ROM.
    /// </summary>
    /// <param name="rom">The ROM's file, the Model 100's or the Tandy 102's.</param>
    [TestMethod]
    [DataRow("m100.bin")]
    [DataRow("t102.bin")]
    public void TheRomUsesWrittenFiles(string rom)
    {
        // The ROM saves the files itself.
        Trs80Model100Machine saved = Trs80Model100RomTests.Boot(rom);
        Trs80Model100RomTests.Type(saved, "BASIC\r");
        saved.RunSeconds(1);
        foreach (string line in (string[])[
            "10 PRINT \"HI\":A=1'C\r", "SAVE \"PROG\"\r", "SAVEM \"MC\",63000,63009,63002\r",
            "OPEN \"NOTE\" FOR OUTPUT AS 1:PRINT #1,\"ABC\":CLOSE\r", "MENU\r"])
        {
            Trs80Model100RomTests.Type(saved, line);
            saved.RunSeconds(1);
        }

        saved.RunSeconds(2);
        Model100Files savedFiles = new(Memory(saved));

        // Then the library writes them into a machine at the menu.
        Trs80Model100Machine written = Trs80Model100RomTests.Boot(rom);
        IBasicMemory memory = Memory(written);
        Model100Files files = new(memory);
        foreach (Model100File file in savedFiles.List())
        {
            files.Write(file.Name, savedFiles.Read(file.Name));
        }

        IBasicMemory before = Memory(saved);
        for (int address = 0xF962; address < 0xF962 + (27 * 11); address++)
        {
            memory.Read(address).Should().Be(before.Read(address), "the directory at ${0:X4}", address);
        }

        int end = BasicProgram.Word(before, 0xFBB2);
        BasicProgram.Word(memory, 0xFBB2).Should().Be(end);
        for (int address = 0x8000; address < end; address++)
        {
            memory.Read(address).Should().Be(before.Read(address), "the file area at ${0:X4}", address);
        }

        // BASIC runs and reads them, and the menu lists them when it is drawn again.
        Trs80Model100RomTests.Type(written, "BASIC\r");
        written.RunSeconds(1);
        Trs80Model100RomTests.Type(written, "RUN \"PROG\"\r");
        written.RunSeconds(1);
        string.Join("\n", written.ScreenText()).Should().Contain("HI");
        foreach (string line in (string[])["NEW\r", "10 OPEN \"NOTE\" FOR INPUT AS 1:INPUT #1,A$:CLOSE:PRINT A$;\"!\"\r", "RUN\r"])
        {
            Trs80Model100RomTests.Type(written, line);
            written.RunSeconds(1);
        }

        string.Join("\n", written.ScreenText()).Should().Contain("ABC!");
        Trs80Model100RomTests.Type(written, "MENU\r");
        written.RunSeconds(2);
        string menu = string.Join("\n", written.ScreenText());
        menu.Should().Contain("PROG.BA").And.Contain("MC.CO").And.Contain("NOTE.DO");
    }

    /// <summary>
    ///  Parses a Model 100 program's text.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>The program.</returns>
    internal static BasicProgram Parse(string text) =>
        BasicProgram.Parse(text, BasicDialect.Model100).Program ?? throw new InvalidOperationException($"{text} does not parse.");

    /// <summary>
    ///  Builds a 64K image of a cold start's directory, file area and pointers.
    /// </summary>
    /// <returns>The image.</returns>
    internal static byte[] ColdStart()
    {
        byte[] ram = new byte[0x10000];
        Convert.FromHexString(ColdDirectory).CopyTo(ram, 0xF962);
        ram[0xF962 + (27 * 11)] = 0xFF;
        ram[0x8003] = 0x1A;
        foreach ((int pointer, int value) in (ValueTuple<int, int>[])[
            (0xF67C, 0x8001), (0xFBAE, 0x8003), (0xFBB0, 0x8004), (0xFBB2, 0x8004), (0xFBB4, 0x8004), (0xFBB6, 0x8004),
            (0xFBB8, 0x8000), (0xF678, 0xF3D8)])
        {
            ram[pointer] = (byte)value;
            ram[pointer + 1] = (byte)(value >> 8);
        }

        return ram;
    }

    private static int Word(byte[] ram, int address) => ram[address] | (ram[address + 1] << 8);
}
