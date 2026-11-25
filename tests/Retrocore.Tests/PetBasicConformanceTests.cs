// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Runs the PET's BASIC 1 and 2 <c>CRUNCH</c>, built from the SDK's sources, on lines in its input buffer, and checks
///  the library stores each exactly as the ROM did, lists it back to the same bytes, and has the ROM's reserved words
///  and pointers.
/// </summary>
/// <remarks>
///  <para>
///   The lines are uppercase and have no escapes outside strings: lowercase folding is the text form's, not the ROM's,
///   and an escaped byte is stored as given, where the ROM drops a shifted character outside a string or takes it as
///   the end of an abbreviated word.
///  </para>
/// </remarks>
[TestClass]
public sealed class PetBasicConformanceTests
{
    // Where CRUNCH returns to: the test stops when the program counter gets there.
    private const ushort Sentinel = 0xFFF0;
    private const int MaximumSteps = 200_000;

    private static string PetRoms => Path.Join(BasicNames.Inputs, "Pet");

    // Each quirk the tokenizers reproduce. None is longer than the 80 characters of the screen editor's line, which
    // is all BASIC 1's buffer holds.
    private static readonly string[] s_lines =
    [
        "PRINT \"HELLO, WORLD!\": REM GREET",
        "?A;B$",
        "IF SCORE > 5 THEN 100",
        "FOR I=S TO P",
        "FOR I = A TO B STEP 2: NEXT I",
        "GO TO 10",
        "GO  TO 10",
        "G O T O 10",
        "GO SUB 10",
        "GOTO10",
        "PRINT #1,A",
        "PRINT# 1,A",
        "DATA 1, 2 ,\"A:B\", HELLO : PRINT",
        "DATA  A B C ,\"X\" : PRINT",
        "REM  HI:THERE \"X",
        "A=1:B=2: C = A AND B OR NOT C",
        "INPUT#1,A$:INPUT \"Q\";B",
        "X=PEEK(1024)+USR(0)+FRE(0)",
        "PRINT \"UNCLOSED",
        "PRINT TAB(5);SPC( 2);\"X\"",
        "  PRINT  ",
        "F OR I=1TO10STEP2:NEXT",
        "S T O P",
        "ON X GOTO 1,2,3: ON Y GOSUB 4,5",
        "A$=LEFT$(B$,2)+MID$(C$,1,1)+RIGHT$(D$,1)+CHR$(147)+STR$(1)",
        "LOAD \"PROG\",8:SAVE\"X\":VERIFY",
        "OPEN 1,4:CMD 1:CLOSE 1:SYS 64824:CLR:GET A$",
        "WAIT 59411,8:POKE 59468,14",
        "X=SGN(1)*INT(2)/ABS(3)^SQR(4)-RND(5)+LOG(6)+EXP(7)",
        "X=COS(8)+SIN(9)+TAN(1)+ATN(2)+LEN(A$)+VAL(B$)+ASC(C$)+POS(0)",
        "DEF FN A(X)=X*2:Y=FN A(3)",
        "A>B=C<D",
        "PRINT A% , B$ ; C",
        "LIST 63999",
        "PRINT \"{$93}{$13}{$11}{$12}HI{$92}{$A0}\"",
        "A={$FF}*2",
        "DOPEN#1,\"DATA\",D0,W:DCLOSE#1:DIRECTORY D0",
        "HEADER\"DISK\",D0,I01:COLLECT D0:BACKUP D0 TO D1",
        "COPY D0,\"A\" TO D1,\"B\":APPEND#1,\"X\":DSAVE\"P\":DLOAD\"P\"",
        "CATALOG:RENAME\"A\" TO \"B\":SCRATCH\"C\":CONCAT\"A\" TO \"B\":RECORD#1,5",
        "PRINT DS;DS$"
    ];

    /// <summary>
    ///  Each version's <c>CRUNCH</c> stores what the library tokenizes.
    /// </summary>
    /// <param name="model">The model, which names the BASIC.</param>
    /// <param name="version">The BASIC version.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 1)]
    [DataRow(PetModel.Pet2001Basic2, 2)]
    [DataRow(PetModel.Pet4032, 4)]
    public void BasicStoresWhatTheLibraryTokenizes(PetModel model, int version)
    {
        AssemblyResult rom = PetSdkModules.AssembleBasic(PetRoms, model);
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        foreach (string line in s_lines)
        {
            byte[] stored = Crunch(rom, line);
            Convert.ToHexString(dialect.Tokenize(line)).Should().Be(Convert.ToHexString(stored), line);
            dialect.Tokenize(dialect.Detokenize(stored)).Should().Equal(stored, "the listing of {0}", line);
        }
    }

    /// <summary>
    ///  The reserved words are the ROM's table, in token order, and the pointers are its page zero's.
    /// </summary>
    /// <param name="model">The model, which names the BASIC.</param>
    /// <param name="version">The BASIC version.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 1)]
    [DataRow(PetModel.Pet2001Basic2, 2)]
    [DataRow(PetModel.Pet4032, 4)]
    public void WordsAndPointersMatchTheRom(PetModel model, int version)
    {
        AssemblyResult rom = PetSdkModules.AssembleBasic(PetRoms, model);
        BasicDialect dialect = BasicDialect.PetBasicVersion(version);
        ReadOnlySpan<byte> image = rom.Sections[0].Bytes.Span;
        List<string> words = [];
        List<char> word = [];
        for (int at = (int)rom.Symbol("RESLST"); image[at] != 0; at++)
        {
            word.Add((char)(image[at] & 0x7F));
            if (image[at] >= 0x80)
            {
                words.Add(new string([.. word]));
                word.Clear();
            }
        }

        words.Should().Equal(dialect.Keywords);
        BasicPointers pointers = dialect.Pointers;
        string[] names = ["TXTTAB", "VARTAB", "ARYTAB", "STREND", "FRETOP", "MEMSIZ", "CURLIN", "OLDTXT", "DATPTR"];
        names.Select(name => (int)rom.Symbol(name)).Should().Equal(
            pointers.ProgramStart,
            pointers.Variables,
            pointers.Arrays,
            pointers.FreeStart,
            pointers.StringBottom,
            pointers.MemoryTop,
            pointers.CurrentLine,
            pointers.ContinueText,
            pointers.DataPointer);

        ((int)rom.Symbol("RAMLOC") + 1).Should().Be(dialect.DefaultLoadAddress);
    }

    /// <summary>
    ///  Strings the library writes into a running BASIC 4, a simple variable's and a string array's after a new
    ///  variable moves the arrays, survive BASIC 4's own garbage collector, which follows each string's link back to
    ///  its descriptor.
    /// </summary>
    [TestMethod]
    public void EditedStringsSurviveBasic4sCollector()
    {
        PetMachine machine = new(PetSdkModules.BuildRoms(PetModel.Pet4032, PetRoms), PetModel.Pet4032);
        PetMachineTests.RunToReady(machine);
        PetMachineTests.Type(machine, "A$=\"HELLO\"+\"\":DIM B$(2):B$(1)=\"WORLD\"+\"\"\r");

        BasicVariables variables = new(
            BasicDialect.PetBasic4,
            new DelegateBasicMemory(address => machine.Bus.Peek((ushort)address), (address, value) => machine.Bus.Write((ushort)address, value)));

        BasicVariable a = variables.Find("A$") ?? throw new AssertFailedException("A$");
        variables.Write(BasicVariableKind.String, a.ValueAddress, BasicValue.Of("NEW"u8.ToArray()));
        BasicVariable c = variables.Create("C$");
        variables.Write(BasicVariableKind.String, c.ValueAddress, BasicValue.Of("SEE"u8.ToArray()));

        PetMachineTests.Type(machine, "X=FRE(0):X=FRE(0):PRINT A$;B$(1);C$\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "NEWWORLDSEE", string.Join('\n', screen));
    }

    // Puts a line in BUF, points TXTPTR at it and runs CRUNCH on flat RAM holding the assembly, page zero's initial
    // values and all. CRUNCH leaves the stored line at BUF, ended by a zero.
    private static byte[] Crunch(AssemblyResult rom, string line)
    {
        RecordingBus bus = new();
        rom.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int buffer = (int)rom.Symbol("BUF");
        int pointer = (int)rom.Symbol("TXTPTR");
        byte[] text = [.. BasicText.Parse(line).Select(unit => (byte)unit), 0];
        text.CopyTo(bus.Memory, buffer);
        bus.Memory[pointer] = (byte)buffer;
        bus.Memory[pointer + 1] = (byte)(buffer >> 8);

        // RTS returns to the address after the one pushed.
        bus.Memory[0x1FF] = (Sentinel - 1) >> 8;
        bus.Memory[0x1FE] = (Sentinel - 1) & 0xFF;
        Processor<RecordingBus> processor = new(bus);
        ProcessorRegisters registers = processor.Registers;
        registers.StackPointer = 0xFD;
        registers.ProgramCounter = (ushort)rom.Symbol("CRUNCH");
        processor.Registers = registers;
        for (int steps = 0; processor.Registers.ProgramCounter != Sentinel; steps++)
        {
            steps.Should().BeLessThan(MaximumSteps, "CRUNCH returns");
            processor.StepInstruction();
            bus.Accesses.Clear();
        }

        int end = buffer;
        while (bus.Memory[end] != 0) { end++; }
        return bus.Memory[buffer..end];
    }
}
