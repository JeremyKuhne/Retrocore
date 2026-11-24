// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks PET error handling, command editing, line input and tokenization against the MACRO-10 builds.
/// </summary>
[TestClass]
public sealed class BasicSharedCommandInputTests
{
    private const ushort ReturnAddress = 0x4000;
    private static string Inputs => BasicNames.Inputs;
    private static string PetInputs => Path.Join(Inputs, "Pet");
    private static string BasicInputs => Path.Join(PetInputs, "Basic");
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  The complete standalone region has the same bytes, emitted span and every legacy label.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void CompleteRegionMatchesEachLegacyBuild(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        AssemblyResult native = AssembleRegion(legacy, model);
        int start = Address(legacy, "OMERR");
        int end = Address(legacy, "FNDLIN");
        native.Symbol("COMMAND_INPUT_END").Should().Be(end);

        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG")
            .OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            entry.Address.Should().Be(next, "the command region must not have gaps or overlaps");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end);
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first different byte is at ${start + first:X4}");

        AssemblySymbol[] labels = [.. legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end)];

        labels.Should().NotBeEmpty();
        foreach (AssemblySymbol label in labels)
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            string? path = native.Definition(label.Name).Location?.Path;
            Path.GetFileName(path).Should().BeOneOf("MsBasic.CommandCore.asm", "Commodore.CommandInput.asm");
        }

        DocumentationResolver resolver = new(
            new SourceMapModule(native, area: null).Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> diagnostics = [.. resolver.Check().Where(diagnostic =>
            Path.GetFileName(diagnostic.Path) is "MsBasic.CommandCore.asm" or "Commodore.CommandInput.asm")];

        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    /// <summary>
    ///  Extracting the common paths does not change any AppleSoft ROM or the shared entries' labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftRetainsItsImageAndSharedLabels(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
        string[] labels =
        [
            "TYPERR", "ERRFIN", "MAIN1", "QDECT1", "MLOOP", "CZLOOP", "GETBPT", "STUFFH",
            "COLIS", "NODATT", "STR1", "STRNG"
        ];

        foreach (string name in labels)
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must retain its ROM address");
            native.Definition(name).Location?.Path
                .Should().EndWith("MsBasic.CommandCore.asm");
        }
    }

    /// <summary>
    ///  BASIC 1 recognizes spaces inside keywords; BASIC 2 and 4 retain them instead.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether the original chip is selected.</param>
    /// <param name="expected">The expected tokenized bytes.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false, "89203130")]
    [DataRow(PetModel.Pet2001, true, "89203130")]
    [DataRow(PetModel.Pet2001Basic2, false, "47204F2054204F203130")]
    [DataRow(PetModel.Pet4032, false, "47204F2054204F203130")]
    [DataRow(PetModel.Pet4032, true, "47204F2054204F203130")]
    public void SpacesInsideKeywordsUseTheSelectedRule(PetModel model, bool original, string expected)
    {
        AssertTokenization(model, original, "G O T O 10"u8.ToArray(), Convert.FromHexString(expected));
    }

    /// <summary>
    ///  BASIC 4's table walker reaches disk words beyond the first 256 bytes.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is selected.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ExtendedTokenTableCrossesThePage(bool original) =>
        AssertTokenization(PetModel.Pet4032, original, "DIRECTORY D0"u8.ToArray(), [0xDA, 0x20, 0x44, 0x30]);

    /// <summary>
    ///  DATA and REM copy their text literally while a colon resumes tokenization outside quotes.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void DataQuotesAndRemProtectTheirContents(PetModel model)
    {
        byte[] expected =
        [
            0x83, 0x20, 0x22, 0x41, 0x3A, 0x42, 0x22, 0x2C, 0x50, 0x52, 0x49, 0x4E, 0x54,
            0x3A, 0x99, 0x3A, 0x8F, 0x20, 0x50, 0x52, 0x49, 0x4E, 0x54, 0x3A, 0x3F
        ];

        AssertTokenization(model, original: false, "DATA \"A:B\",PRINT:PRINT:REM PRINT:?"u8.ToArray(), expected);
    }

    /// <summary>
    ///  Shifted input is discarded outside strings except for PI; quoted bytes are preserved.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void PiAndQuotedHighBitsArePreserved(PetModel model) =>
        AssertTokenization(model, original: false, [0xC1, 0xFF, 0x22, 0xC2, 0x22, 0x3F],
            [0xFF, 0x22, 0xC2, 0x22, 0x99]);

    /// <summary>
    ///  Unquoted DATA still discards shifted non-PI characters, then resumes tokenization at a colon.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void UnquotedDataStillFiltersHighBits(PetModel model) =>
        AssertTokenization(model, original: false, [0x44, 0x41, 0x54, 0x41, 0x20, 0xC1, 0xFF, 0x3A, 0x3F],
            [0x83, 0x20, 0xFF, 0x3A, 0x99]);

    /// <summary>
    ///  Control-O toggles output suppression only for terminal input.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="channel">The selected channel.</param>
    /// <param name="expected">The final suppression flag.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0, 0xA5)]
    [DataRow(PetModel.Pet2001, 1, 0x5A)]
    [DataRow(PetModel.Pet2001Basic2, 0, 0xA5)]
    [DataRow(PetModel.Pet2001Basic2, 1, 0x5A)]
    public void ControlOSuppressesOnlyTerminalOutput(PetModel model, int channel, int expected)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] character = [0xA9, 0x0F, 0x60];
        character.CopyTo(bus.Memory, Address(native, "CQINCH"));
        bus.Memory[Address(native, "CHANNL")] = (byte)channel;
        bus.Memory[Address(native, "CNTWFL")] = 0x5A;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "INCHR"));
        StepUntil(cpu, 100, ReturnAddress);

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        cpu.Registers.Accumulator.Should().Be(0x0F);
        bus.Memory[Address(native, "CNTWFL")].Should().Be((byte)expected);
    }

    /// <summary>
    ///  BASIC 4 reads Control-O directly and leaves the disk-status descriptor untouched.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is selected.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void Basic4DoesNotTreatControlOAsAnOutputFlag(bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032, original);
        AssemblyResult native = AssembleRegion(legacy, PetModel.Pet4032);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] character = [0xA9, 0x0F, 0x60];
        character.CopyTo(bus.Memory, Address(native, "CQINCH"));
        bus.Memory[Address(native, "DSDESC")] = 0x5A;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "INLIN"));
        ushort nextCharacter = checked((ushort)native.Symbol("INLINC"));
        for (int step = 0; step < 100 && (cpu.Registers.ProgramCounter != nextCharacter || cpu.Registers.X != 1); step++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(nextCharacter);
        cpu.Registers.X.Should().Be(1);
        bus.Memory[Address(native, "BUF")].Should().Be(0x0F);
        bus.Memory[Address(native, "DSDESC")].Should().Be(0x5A);
    }

    /// <summary>
    ///  BASIC 4 rejects a full line; BASIC 2 trusts the editor and continues reading.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="reject">Whether the full buffer enters the error handler.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void FullInputBufferUsesTheVariantLimit(PetModel model, bool reject)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] character = [0xA9, (byte)'A', 0x60];
        character.CopyTo(bus.Memory, Address(native, "CQINCH"));
        bus.Memory[Address(native, "CHANNL")] = 0;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "INLIN"));
        ushort error = checked((ushort)native.Symbol("ERROR"));
        ushort nextCharacter = checked((ushort)native.Symbol("INLINC"));
        byte limit = checked((byte)native.Symbol("BUFLEN"));
        for (int step = 0; step < 5000 && cpu.Registers.ProgramCounter != error; step++)
        {
            if (!reject && cpu.Registers.ProgramCounter == nextCharacter && cpu.Registers.X == limit) { break; }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(reject ? error : nextCharacter);
        bus.Memory[Address(native, "BUF") + limit - 1].Should().Be((byte)'A');
        cpu.Registers.X.Should().Be(reject ? (byte)native.Symbol("ERRLS") : limit);
    }

    /// <summary>
    ///  BASIC 4 accepts a carriage return after exactly 80 characters, before testing for a full buffer.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is selected.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void FullCheckedInputAcceptsTheLastCarriageReturn(bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032, original);
        AssemblyResult native = AssembleRegion(legacy, PetModel.Pet4032);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] character = [0xE0, 80, 0xD0, 3, 0xA9, 13, 0x60, 0xA9, (byte)'A', 0x60];
        character.CopyTo(bus.Memory, Address(native, "CQINCH"));
        Processor<RecordingBus> cpu = Start(bus, Address(native, "INLIN"));
        ushort finish = checked((ushort)native.Symbol("FININL"));
        ushort error = checked((ushort)native.Symbol("ERROR"));
        StepUntil(cpu, 5000, finish, error);

        cpu.Registers.ProgramCounter.Should().Be(finish);
        cpu.Registers.X.Should().Be(80);
        bus.Memory.AsSpan(Address(native, "BUF"), 80).ToArray().Should().OnlyContain(value => value == (byte)'A');
    }

    /// <summary>
    ///  Error reporting restores a selected channel and outputs the unmarked error text.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="channel">The current channel.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 1)]
    [DataRow(PetModel.Pet2001Basic2, 0)]
    [DataRow(PetModel.Pet2001Basic2, 1)]
    [DataRow(PetModel.Pet4032, 1)]
    public void ErrorsRestoreChannelsAndOutputTheirMessage(PetModel model, int channel)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        string flag = model == PetModel.Pet4032 ? "DSDESC" : "CNTWFL";
        bus.Memory[Address(native, flag)] = 0xFF;
        bus.Memory[Address(native, "CHANNL")] = (byte)channel;
        foreach (string entry in (string[])["CQCCHN", "CRDO", "OUTQST", "OUTDO"])
        {
            bus.Memory[Address(native, entry)] = 0x60;
        }

        Processor<RecordingBus> cpu = Start(bus, Address(native, "ERROR"));
        cpu.Registers = cpu.Registers with { X = checked((byte)native.Symbol("ERROM")) };
        ushort finish = checked((ushort)native.Symbol("TYPERR"));
        ushort close = checked((ushort)native.Symbol("CQCCHN"));
        ushort output = checked((ushort)native.Symbol("OUTDO"));
        List<byte> text = [];
        int closes = 0;
        for (int step = 0; step < 500 && cpu.Registers.ProgramCounter != finish; step++)
        {
            if (cpu.Registers.ProgramCounter == close) { closes++; }
            if (cpu.Registers.ProgramCounter == output) { text.Add(cpu.Registers.Accumulator); }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
        closes.Should().Be(channel == 0 ? 0 : 1);
        bus.Memory[Address(native, "CHANNL")].Should().Be(0);
        bus.Memory[Address(native, flag)].Should().Be(model == PetModel.Pet4032 ? (byte)0xFF : (byte)0x7F);
        text.Should().Equal(Encoding.ASCII.GetBytes("OUT OF MEMORY"));
    }

    /// <summary>
    ///  The shared error suffix prints a line number only for program execution.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="highLine">The high byte of the current line.</param>
    /// <param name="printsLine">Whether the line-number printer is called.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0xFF, false)]
    [DataRow(PetModel.Pet2001Basic2, 0x12, true)]
    [DataRow(PetModel.Pet4032, 0xFF, false)]
    [DataRow(PetModel.Pet4032, 0x12, true)]
    public void ErrorSuffixDistinguishesDirectAndProgramMode(PetModel model, int highLine, bool printsLine)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        bus.Memory[Address(native, "CURLIN") + 1] = (byte)highLine;
        bus.Memory[Address(native, "STROUT")] = 0x60;
        bus.Memory[Address(native, "INPRT")] = 0x60;
        Processor<RecordingBus> cpu = Start(bus, Address(native, "ERRFIN"));
        cpu.Registers = cpu.Registers with { Accumulator = 0x34, Y = 0x56 };
        ushort ready = checked((ushort)native.Symbol("READY"));
        ushort output = checked((ushort)native.Symbol("STROUT"));
        ushort printLine = checked((ushort)native.Symbol("INPRT"));
        int messages = 0;
        int numbers = 0;
        for (int step = 0; step < 100 && cpu.Registers.ProgramCounter != ready; step++)
        {
            if (cpu.Registers.ProgramCounter == output)
            {
                messages++;
                cpu.Registers.Accumulator.Should().Be(0x34);
                cpu.Registers.Y.Should().Be(0x56);
            }

            if (cpu.Registers.ProgramCounter == printLine) { numbers++; }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(ready);
        messages.Should().Be(1);
        numbers.Should().Be(printsLine ? 1 : 0);
    }

    /// <summary>
    ///  Relinking carries into the next page, including BASIC 4's different high-byte addition.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether the original chip is selected.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void RelinkingCarriesAcrossPages(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] program = [1, 1, 10, 0, 65, 66, 67, 68, 69, 70, 0, 1, 1, 20, 0, 88, 0, 0, 0];
        program.CopyTo(bus.Memory, 0x40F8);
        WriteWord(bus.Memory, Address(native, "TXTTAB"), 0x40F8);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "LNKPRG"));
        ushort destination = model == PetModel.Pet2001 ? checked((ushort)native.Symbol("MAIN")) : ReturnAddress;
        StepUntil(cpu, 300, destination);

        cpu.Registers.ProgramCounter.Should().Be(destination);
        ReadWord(bus.Memory, 0x40F8).Should().Be(0x4103);
        ReadWord(bus.Memory, 0x4103).Should().Be(0x4109);
        ReadWord(bus.Memory, 0x4109).Should().Be(0);
    }

    /// <summary>
    ///  Inserting, replacing and deleting a line preserves its neighbours and links across a page boundary.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether the original chip is selected.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void NumberedEditsInsertReplaceAndDelete(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] initial = [0xFE, 0x40, 10, 0, 65, 0, 0x04, 0x41, 30, 0, 66, 0, 0, 0];
        initial.CopyTo(bus.Memory, 0x40F8);
        WriteWord(bus.Memory, Address(native, "TXTTAB"), 0x40F8);
        WriteWord(bus.Memory, Address(native, "VARTAB"), 0x4106);
        WriteWord(bus.Memory, Address(native, "MEMSIZ"), 0x8000);
        WriteWord(bus.Memory, Address(native, "FRETOP"), 0x8000);
        bus.Memory[Address(native, "CQCALL")] = 0x60;

        RunNumberedEdit(bus, native, "20 PRINT 2");
        byte[] inserted =
        [
            0xFE, 0x40, 10, 0, 65, 0,
            0x06, 0x41, 20, 0, 0x99, 0x20, 50, 0,
            0x0C, 0x41, 30, 0, 66, 0, 0, 0
        ];

        bus.Memory.AsSpan(0x40F8, inserted.Length).ToArray().Should().Equal(inserted);
        ReadWord(bus.Memory, Address(native, "VARTAB")).Should().Be(0x410E);

        RunNumberedEdit(bus, native, "20 PRINT 12345");
        byte[] replaced =
        [
            0xFE, 0x40, 10, 0, 65, 0,
            0x0A, 0x41, 20, 0, 0x99, 0x20, 49, 50, 51, 52, 53, 0,
            0x10, 0x41, 30, 0, 66, 0, 0, 0
        ];

        bus.Memory.AsSpan(0x40F8, replaced.Length).ToArray().Should().Equal(replaced);
        ReadWord(bus.Memory, Address(native, "VARTAB")).Should().Be(0x4112);

        RunNumberedEdit(bus, native, "20");
        bus.Memory.AsSpan(0x40F8, initial.Length).ToArray().Should().Equal(initial);
        ReadWord(bus.Memory, Address(native, "VARTAB")).Should().Be(0x4106);
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, PetModel model)
    {
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        int start = Address(legacy, "OMERR");
        int end = Address(legacy, "FNDLIN");
        string source = $"""
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.CommandInput.asm"
            .org ${start:X4}
                COMMODORE_ERROR_READY {Flag(!disk)}
                COMMODORE_COMMAND_LOOP {Flag(!early)}, {Flag(!early)}, {Flag(!early)}, {Flag(disk)}
                COMMODORE_TERMINAL_INPUT {Flag(early)}, {Flag(disk)}
                COMMODORE_TOKENIZE {Flag(disk)}, {Flag(early)}
            COMMAND_INPUT_END:
            """;

        string[] dependencies =
        [
            "ERROM", "ERRTAB", "ERR", "REDDY", "CRDO", "OUTQST", "OUTDO", "STKINI", "STROUT", "INPRT",
            "LINGET", "FNDLIN", "GONE", "RUNC", "BLTU", "FININL", "RESLST", "PRINTK", "DATATK", "REMTK", "LIST", "STOP"
        ];

        Dictionary<string, long> symbols = [];
        foreach (string name in dependencies.Append(disk ? "ERRLS" : "ERROM").Distinct(StringComparer.Ordinal))
        {
            AssemblySymbol definition = legacy.Definition(name);
            (definition.IsConstant || definition.Value < start || definition.Value >= end).Should().BeTrue(
                $"{name} must not predefine a label in the region under test");

            symbols.Add(name, definition.Value);
        }

        symbols.Add("BUFPAG", early ? 0 : 2);
        symbols.Add("BUFLEN", early ? 80 : 81);
        symbols.Add("NULCMD", Flag(early));
        symbols.Add("TERMINAL_FIRST", Flag(early));
        symbols.Add("FULL_STACK_TOP", Flag(early));
        symbols.Add("STACK_RESERVE_19", Flag(early));
        symbols.Add("LOCAL_TRMPOS", Flag(early));
        symbols.Add("LINE_WIDTH_STORAGE", Flag(!disk));
        symbols.Add("DISK_STATUS_STRING", Flag(disk));
        symbols.Add("VARTXT_IN_LINNUM", Flag(early));
        symbols.Add("CLOCK_IN_PAGE2", Flag(early));
        symbols.Add("STATUS_IN_PAGE2", Flag(early));
        symbols.Add("RND_TIMER_9044", Flag(early));
        symbols.Add("ERROR_PADDING5", Flag(early));
        symbols.Add("EXTENDED_DISK_VECTORS", Flag(disk));

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "CommandInputStandaloneTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                IncludePaths = [SharedInputs],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }

    private static void AssertTokenization(PetModel model, bool original, byte[] input, byte[] expected)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        AssemblyResult native = AssembleRegion(legacy, model);
        RecordingBus bus = CreateBus(legacy, native);
        int buffer = Address(native, "BUF");
        input.CopyTo(bus.Memory, buffer);
        bus.Memory[buffer + input.Length] = 0;
        WriteWord(bus.Memory, Address(native, "TXTPTR"), buffer);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "CRUNCH"));
        StepUntil(cpu, 200_000, ReturnAddress);

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        bus.Memory.AsSpan(buffer, expected.Length).ToArray().Should().Equal(expected);
        bus.Memory[buffer + expected.Length].Should().Be(0);
        bus.Memory[buffer + expected.Length + 2].Should().Be(0);
        cpu.Registers.Y.Should().Be(checked((byte)(expected.Length + 5)));
        ReadWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(buffer - 1);
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult native)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int start = Address(native, "OMERR");
        int end = Address(native, "COMMAND_INPUT_END");
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(native, "CHRGET")));
        return bus;
    }

    private static void RunNumberedEdit(RecordingBus bus, AssemblyResult native, string text)
    {
        int buffer = Address(native, "BUF");
        byte[] input = Encoding.ASCII.GetBytes(text);
        input.CopyTo(bus.Memory, buffer);
        bus.Memory[buffer + input.Length] = 0;
        WriteWord(bus.Memory, Address(native, "TXTPTR"), buffer);
        Processor<RecordingBus> cpu = Start(bus, Address(native, "MAIN1"));
        if (buffer >= 0x0200)
        {
            // The input buffer's link placeholder occupies the otherwise unused top of the stack.
            bus.Memory[buffer - 3] = 0x40;
        }

        // MAIN1 is not a subroutine; the prompt has the stack pointer left by STKINI.
        cpu.Registers = cpu.Registers with
        {
            Accumulator = input[0],
            StackPointer = checked((byte)(native.Symbol("STKEND") - 0x101)),
            Status = StatusRegister.Unused
        };

        ushort main = checked((ushort)native.Symbol("MAIN"));
        ushort error = checked((ushort)native.Symbol("ERROR"));
        Queue<ushort> trace = new();
        for (int step = 0; step < 50_000 && cpu.Registers.ProgramCounter != main && cpu.Registers.ProgramCounter != error; step++)
        {
            if (trace.Count == 24) { trace.Dequeue(); }
            trace.Enqueue(cpu.Registers.ProgramCounter);
            cpu.StepInstruction();
        }

        string details = string.Join(' ', trace.Select(address => address.ToString("X4")));
        cpu.Registers.ProgramCounter.Should().Be(main, $"edit {text}: X=${cpu.Registers.X:X2}, trace {details}");
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
        for (int step = 0; step < limit && !exits.Contains(cpu.Registers.ProgramCounter); step++)
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
