// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the shared READ and variable-input processing against the AppleSoft and PET sources.
/// </summary>
[TestClass]
public sealed class BasicSharedVariableInputTests
{
    private const int Apple = 0;
    private const int Pet1 = 1;
    private const int Pet2 = 2;
    private const int Pet4 = 4;
    private const ushort ReturnAddress = 0x3000;

    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");
    private static string PetInputs => Path.Join(Inputs, "Pet");

    /// <summary>
    ///  Every native AppleSoft build uses the shared block without moving bytes or labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedVariableInput(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, Apple);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        AssertEmittedSpan(legacy, standalone);
    }

    /// <summary>
    ///  Each PET revision matches the overlay with both legacy and native workspace definitions.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedVariableInputMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        int variant = model == PetModel.Pet2001 ? Pet1 : model == PetModel.Pet2001Basic2 ? Pet2 : Pet4;
        foreach (bool nativeWorkspace in (bool[])[false, true])
        {
            AssemblyResult native = AssembleShared(legacy, variant, nativeWorkspace);
            CompareRegion(legacy, native);
            AssertEmittedSpan(legacy, native);
            if (nativeWorkspace)
            {
                native.Definition("INPFLG").Location?.Path
                    .Should().EndWith("Commodore.Equates.asm");
            }

            DocumentationResolver resolver = new(
                new SourceMapModule(native, area: null).Documentation,
                isDirective: name => DirectiveDocs.Describe(name) is not null,
                isInstruction: InstructionDocs.IsMnemonic);

            List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
                Path.GetFileName(problem.Path) == "MsBasic.VariableInput.asm")];

            problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
                $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
        }
    }

    /// <summary>
    ///  READ and INPUT set distinct source flags even when their cursors lie in page zero.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReadAndInputEntriesSetTheirSourceFlags(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        WriteWord(bus.Memory, Address(native, "DATPTR"), 0x0030);
        Processor<RecordingBus> read = Start(bus, Address(native, "READ"));
        StepUntil(read, 20, checked((ushort)native.Symbol("INPCO1")));
        read.Registers.ProgramCounter.Should().Be((ushort)native.Symbol("INPCO1"));
        read.Registers.Accumulator.Should().Be(0x98);
        read.Registers.X.Should().Be(0x30);
        read.Registers.Y.Should().Be(0);

        Processor<RecordingBus> input = Start(bus, Address(native, "INPCON"));
        input.Registers = input.Registers with { X = 0xA5, Y = variant == Pet1 ? (byte)0 : (byte)1 };
        StepUntil(input, 5, checked((ushort)native.Symbol("INPCO1")));
        input.Registers.ProgramCounter.Should().Be((ushort)native.Symbol("INPCO1"));
        input.Registers.Accumulator.Should().Be(0);
        input.Registers.X.Should().Be(0xA5);
        input.Registers.Y.Should().Be(variant == Pet1 ? (byte)0 : (byte)1);
    }

    /// <summary>
    ///  GET makes a one-character string, including the early PET patch and Apple's high-bit masking.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="expected">The stored character.</param>
    [TestMethod]
    [DataRow(Apple, 0x41)]
    [DataRow(Pet1, 0xC1)]
    [DataRow(Pet2, 0xC1)]
    [DataRow(Pet4, 0xC1)]
    public void GetStringUsesTheVariantCharacterAndBuffer(int variant, int expected)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        int buffer = Address(native, "BUF");
        int type = Address(native, "VALTYP");
        byte[] variableStub = [0xA9, 0xFF, 0x85, (byte)type, 0xA9, 0x34, 0xA0, 0x12, 0x60];
        variableStub.CopyTo(bus.Memory, Address(native, "PTRGET"));
        byte[] characterStub = [0xA9, 0xC1, 0x60];
        characterStub.CopyTo(bus.Memory, Address(native, "CZGETL"));
        bus.Memory[buffer + 1] = 0;
        bus.Memory[Address(native, "INPFLG")] = 0x40;
        WriteWord(bus.Memory, Address(native, "INPPTR"), buffer + 1);
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x4000);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "INLOOP"));
        ushort finish = checked((ushort)native.Symbol("STRLT2"));
        int getString = variant == Pet1 ? Address(legacy, "GETSTR") : -1;
        int getContinuation = variant == Pet1 ? Address(legacy, "GETST1") : -1;
        bool sawGetString = false;
        bool sawGetContinuation = false;
        for (int instruction = 0; instruction < 200 && cpu.Registers.ProgramCounter != finish; instruction++)
        {
            sawGetString |= cpu.Registers.ProgramCounter == getString;
            sawGetContinuation |= cpu.Registers.ProgramCounter == getContinuation;
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
        if (variant == Pet1)
        {
            sawGetString.Should().BeTrue();
            sawGetContinuation.Should().BeTrue();
        }

        bus.Memory[buffer].Should().Be((byte)expected);
        bus.Memory[Address(native, "CHARAC")].Should().Be(0);
        bus.Memory[Address(native, "ENDCHR")].Should().Be(0);
        (cpu.Registers.Accumulator | (cpu.Registers.Y << 8)).Should().Be(buffer);
        ReadWord(bus.Memory, Address(native, "FORPNT")).Should().Be(0x1234);
        ReadWord(bus.Memory, Address(native, "VARTXT")).Should().Be(0x4000);
        cpu.Registers.StackPointer.Should().Be(0xFB, "STRLT2 was entered through JSR");
    }

    /// <summary>
    ///  Quoted and unquoted DATA strings receive the right terminators and quote-skip carry.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="quoted">Whether the first character is a quote at the end of a page.</param>
    [TestMethod]
    [DataRow(Apple, true)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, true)]
    public void DataStringSelectsDelimitersAndCrossesPages(int variant, bool quoted)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        bus.Memory[0x40FF] = quoted ? (byte)'"' : (byte)'A';
        bus.Memory[0x4100] = (byte)'B';
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x40FE);
        bus.Memory[Address(native, "VALTYP")] = 0xFF;
        bus.Memory[Address(native, "INPFLG")] = 0x98;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "DATBK1"));
        StepUntil(cpu, 100, checked((ushort)native.Symbol("STRLT2")));

        cpu.Registers.ProgramCounter.Should().Be((ushort)native.Symbol("STRLT2"));
        bus.Memory[Address(native, "CHARAC")].Should().Be(quoted ? (byte)'"' : (byte)':');
        bus.Memory[Address(native, "ENDCHR")].Should().Be(quoted ? (byte)'"' : (byte)',');
        (cpu.Registers.Accumulator | (cpu.Registers.Y << 8)).Should().Be(quoted ? 0x4100 : 0x40FF);
    }

    /// <summary>
    ///  AppleSoft retries an empty numeric INPUT but still converts READ and GET; PET converts INPUT.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="flag">The input-source flag.</param>
    /// <param name="retry">Whether the INPUT retry entry should be reached.</param>
    [TestMethod]
    [DataRow(Apple, 0x00, true)]
    [DataRow(Apple, 0x40, false)]
    [DataRow(Apple, 0x98, false)]
    [DataRow(Pet2, 0x00, false)]
    public void BlankNumericInputRetainsTheAppleRetry(int variant, int flag, bool retry)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        int buffer = Address(native, "BUF");
        bus.Memory[buffer] = 0;
        bus.Memory[Address(native, "VALTYP")] = 0;
        bus.Memory[Address(native, "INPFLG")] = (byte)flag;
        WriteWord(bus.Memory, Address(native, "TXTPTR"), buffer - 1);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "DATBK1"));
        ushort finish = checked((ushort)legacy.Symbol(retry ? "DOAGIN" : "FIN"));
        StepUntil(cpu, 100, finish);

        cpu.Registers.ProgramCounter.Should().Be(finish);
        cpu.Registers.StackPointer.Should().Be(retry ? (byte)0xFD : (byte)0xFB);
    }

    /// <summary>
    ///  READ converts and assigns multiple integer values, then preserves the DATA cursor.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReadAssignsSeveralIntegerVariables(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] variables =
        [
            0xC1, 0x80, 0, 0, 0, 0, 0,
            0xC2, 0x80, 0, 0, 0, 0, 0
        ];

        variables.CopyTo(bus.Memory, 0x5000);
        byte[] names = [(byte)'A', (byte)'%', (byte)',', (byte)'B', (byte)'%', (byte)':'];
        names.CopyTo(bus.Memory, 0x4000);
        byte[] data = [(byte)',', (byte)'1', (byte)',', (byte)'2', (byte)':'];
        data.CopyTo(bus.Memory, 0x4100);
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x4000);
        WriteWord(bus.Memory, Address(native, "DATPTR"), 0x4100);
        WriteWord(bus.Memory, Address(legacy, "VARTAB"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "ARYTAB"), 0x500E);
        WriteWord(bus.Memory, Address(legacy, "STREND"), 0x500E);
        WriteWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "READ"));
        StepUntil(cpu, 5000, ReturnAddress, checked((ushort)legacy.Symbol("ERROR")));

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        bus.Memory.AsSpan(0x5002, 2).ToArray().Should().Equal(0, 1);
        bus.Memory.AsSpan(0x5009, 2).ToArray().Should().Equal(0, 2);
        ReadWord(bus.Memory, Address(native, "DATPTR")).Should().Be(0x4104);
        ReadWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(0x4005);
    }

    /// <summary>
    ///  DATA search ignores quoted colons, advances to a later line, and records that line number.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReadSearchesPastStatementsAndTracksTheDataLine(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] text =
        [
            (byte)'"', (byte)':', (byte)'"', (byte)':', 0x01, (byte)'X', 0,
            0x00, 0x44, 0x34, 0x12, (byte)native.Symbol("DATATK"), (byte)'7', 0
        ];

        text.CopyTo(bus.Memory, 0x4400);
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x4400);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "DATLOP"));
        StepUntil(cpu, 300, checked((ushort)native.Symbol("DATBK1")));

        cpu.Registers.ProgramCounter.Should().Be((ushort)native.Symbol("DATBK1"));
        ReadWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(0x440B);
        ReadWord(bus.Memory, Address(native, "DATLIN")).Should().Be(0x1234);
    }

    /// <summary>
    ///  Running out of program lines reports the OUT OF DATA error.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet4)]
    public void ReadAtEndOfProgramReportsOutOfData(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        bus.Memory[0x4400] = 0;
        bus.Memory[0x4402] = 0;
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x4400);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "DATLOP"));
        ushort error = checked((ushort)native.Symbol("ERRGO5"));
        StepUntil(cpu, 100, error);

        cpu.Registers.ProgramCounter.Should().Be(error);
        cpu.Registers.X.Should().Be((byte)native.Symbol("ERROD"));
    }

    /// <summary>
    ///  Value terminators restore the variable cursor; malformed trailing characters enter the error handler.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="terminator">The character after the value.</param>
    /// <param name="valid">Whether the character is an accepted terminator.</param>
    [TestMethod]
    [DataRow(Apple, 0x3A, true)]
    [DataRow(Apple, 0x58, false)]
    [DataRow(Pet1, 0x00, true)]
    [DataRow(Pet1, 0x3A, true)]
    [DataRow(Pet2, 0x2C, true)]
    [DataRow(Pet4, 0x58, false)]
    public void ValueTerminatorRestoresTheVariableCursor(int variant, int terminator, bool valid)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        bus.Memory[0x4400] = (byte)terminator;
        bus.Memory[0x4500] = (byte)':';
        WriteWord(bus.Memory, Address(native, "TXTPTR"), 0x4400);
        WriteWord(bus.Memory, Address(native, "INPPTR"), 0x3333);
        WriteWord(bus.Memory, Address(native, "VARTXT"), 0x4500);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "STRDN2"));
        ushort finish = checked((ushort)native.Symbol(valid ? "VAREND" : "TRMNOK"));
        StepUntil(cpu, 100, finish);

        cpu.Registers.ProgramCounter.Should().Be(finish);
        ReadWord(bus.Memory, Address(native, "INPPTR")).Should().Be(valid ? 0x4400 : 0x3333);
        ReadWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(valid ? 0x4500 : 0x4400);
    }

    /// <summary>
    ///  Extra terminal input warns, while an empty remainder or selected file channel does not.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="channel">The selected PET channel, or zero for AppleSoft.</param>
    /// <param name="extra">Whether the input cursor has an extra value.</param>
    /// <param name="warning">Whether the warning should be printed.</param>
    [TestMethod]
    [DataRow(Apple, 0, true, true)]
    [DataRow(Apple, 0, false, false)]
    [DataRow(Pet1, 0, true, true)]
    [DataRow(Pet1, 1, true, false)]
    [DataRow(Pet2, 1, true, false)]
    [DataRow(Pet4, 0, true, true)]
    [DataRow(Pet4, 1, true, false)]
    public void ExtraInputWarningHonorsTheChannel(int variant, int channel, bool extra, bool warning)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        WriteWord(bus.Memory, Address(native, "INPPTR"), 0x5000);
        bus.Memory[0x5000] = extra ? (byte)',' : (byte)0;
        bus.Memory[Address(native, "INPFLG")] = 0;
        if (variant != Apple) { bus.Memory[Address(native, "CHANNL")] = (byte)channel; }
        Processor<RecordingBus> cpu = Start(bus, Address(native, "VAREND"));
        ushort print = checked((ushort)native.Symbol("STROUT"));
        StepUntil(cpu, 100, print, ReturnAddress);

        cpu.Registers.ProgramCounter.Should().Be(warning ? print : ReturnAddress);
        if (warning)
        {
            (cpu.Registers.Accumulator | (cpu.Registers.Y << 8))
                .Should().Be(Address(native, "EXIGNT"));
        }
    }

    /// <summary>
    ///  Completing READ saves its cursor rather than printing an extra-input warning.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReadCompletionSavesTheDataCursor(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleShared(legacy, variant);
        RecordingBus bus = CreateBus(legacy, native);
        WriteWord(bus.Memory, Address(native, "INPPTR"), 0x50FF);
        bus.Memory[Address(native, "INPFLG")] = 0x98;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "VAREND"));
        StepUntil(cpu, 50, ReturnAddress);

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        ReadWord(bus.Memory, Address(native, "DATPTR")).Should().Be(0x50FF);
    }

    /// <summary>
    ///  The shared routines remain documented and their macro source lines accept breakpoints.
    /// </summary>
    [TestMethod]
    public void SharedInputRetainsDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);

        int start = Address(native, "READ");
        int end = Address(native, "NEXT");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["READ", "INPCON", "INPCO1", "DATBK1", "RESETC", "NOWGET", "STRDN2", "DATLOP", "VAREND"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.VariableInput.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.VariableInput.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.InputOutput.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }

        SourceAnalysis analysis = SourceAnalysis.Assemble(Path.Join(Inputs, "AppleSoft", "AppleSoft.asm"), _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.VariableInput.asm" or "AppleSoft.InputOutput.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static AssemblyResult Legacy(int variant) => variant switch
    {
        Apple => SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), Apple2Model.IIeEnhanced),
        Pet1 => PetLegacyBasic.Assemble(PetInputs, PetModel.Pet2001),
        Pet2 => PetLegacyBasic.Assemble(PetInputs, PetModel.Pet2001Basic2),
        Pet4 => PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032),
        _ => throw new ArgumentOutOfRangeException(nameof(variant))
    };

    private static AssemblyResult AssembleShared(AssemblyResult legacy, int variant, bool nativeWorkspace = false)
    {
        bool apple = variant == Apple;
        bool early = variant == Pet1;
        bool disk = variant == Pet4;
        string source = $"""
            .cpu Mos6502
            {(nativeWorkspace ? ".include \"Commodore.Equates.asm\"" : "")}
            .include "MsBasic.VariableInput.asm"
            .org ${legacy.Symbol("READ"):X4}
                VariableInput {(early ? 0 : 2)}, {Flag(apple)}, {Flag(early)}, {Flag(early)}, {Flag(!apple)}, {Flag(apple)}
                VariableInputMessages {Flag(apple)}, {Flag(early || variant == Pet2)}
            VARIABLE_INPUT_END:
            """;

        string[] dependencies =
        [
            "BUF", "DATPTR", "INPFLG", "INPPTR", "PTRGET", "FORPNT", "TXTPTR", "VARTXT",
            "CHRGOT", "CZGETL", "OUTQST", "QINLIN", "CHRGET", "VALTYP", "CHARAC", "ENDCHR",
            "STRLT2", "ST2TXT", "INPCOM", "FIN", "INTFLG", "QINTGR", "TRMNOK", "CHKCOM",
            "DATAN", "ERROD", "ERRGO5", "DATLIN", "ADDON", "DATATK", "RESFIN", "RESTOR", "STROUT"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (apple) { symbols.Add("SNERR6", legacy.Symbol("SNERR6")); }
        else { symbols.Add("CHANNL", legacy.Symbol("CHANNL")); }
        if (early)
        {
            symbols.Add("GETSTR", legacy.Symbol("GETSTR"));
            symbols.Add("GETST1", legacy.Symbol("GETST1"));
        }

        if (nativeWorkspace)
        {
            string[] workspace =
            [
                "BUF", "DATPTR", "INPFLG", "INPPTR", "FORPNT", "TXTPTR", "VARTXT", "CHRGOT", "CZGETL",
                "CHRGET", "VALTYP", "CHARAC", "ENDCHR", "INTFLG", "DATLIN", "CHANNL"
            ];

            foreach (string name in workspace) { symbols.Remove(name); }
            symbols.Add("INPUT_BUFFER_PAGE", early ? 0 : 2);
            symbols.Add("INPUT_BUFFER_LENGTH", early ? 80 : 81);
            symbols.Add("NULL_COMMAND", Flag(early));
            symbols.Add("TERMINAL_FIRST", Flag(early));
            symbols.Add("FULL_STACK_TOP", Flag(early));
            symbols.Add("STACK_RESERVE_19", Flag(early));
            symbols.Add("LOCAL_TERMINAL_POSITION", Flag(early));
            symbols.Add("LINE_WIDTH_STORAGE", Flag(!disk));
            symbols.Add("DISK_STATUS_STRING", Flag(disk));
            symbols.Add("VARIABLE_LIST_IN_LINE_NUMBER", Flag(early));
            symbols.Add("CLOCK_IN_PAGE2", Flag(early));
            symbols.Add("STATUS_IN_PAGE2", Flag(early));
            symbols.Add("RND_TIMER_9044", Flag(early));
            symbols.Add("ERROR_PADDING5", Flag(early));
            symbols.Add("EXTENDED_DISK_VECTORS", Flag(disk));
        }

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(SharedInputs, "VariableInputTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                IncludePaths = [Path.Join(PetInputs, "Basic")],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "READ");
        int end = Address(legacy, "NEXT");
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first different byte is at ${start + first:X4}");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            // A vendor's alias reaches its name only in a build that includes the vendor's historical names: a
            // standalone build of the module skips it, and a whole build must have it.
            if (BasicNames.IsVendorName(label.Name) && !BasicNames.IncludesHistoricalNames(native))
            {
                continue;
            }

            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            BasicNames.DefiningSymbol(native, label.Name).Location?.Path
                .Should().EndWith("MsBasic.VariableInput.asm", $"{label.Name} must be defined by the shared block");
        }
    }

    private static void AssertEmittedSpan(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "READ");
        int end = Address(legacy, "NEXT");
        native.Symbol("VARIABLE_INPUT_END").Should().Be(end);
        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG")
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the shared input block must not have gaps or overlaps");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end);
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult native)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int start = Address(native, "READ");
        int end = Address(native, "VARIABLE_INPUT_END");
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        return bus;
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, int address)
    {
        WriteWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)address),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };
    }

    private static void StepUntil(Processor<RecordingBus> cpu, int limit, params ushort[] exits)
    {
        for (int instruction = 0; instruction < limit && !exits.Contains(cpu.Registers.ProgramCounter); instruction++)
        {
            cpu.StepInstruction();
        }
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));
    private static int Flag(bool value) => value ? 1 : 0;
    private static int ReadWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void WriteWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
