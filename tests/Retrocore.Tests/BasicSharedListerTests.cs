// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using ListerOptions = (
    bool CommaRange,
    bool TrackQuotes,
    bool GuardOffset,
    int ColumnMode,
    string LinePrinter,
    bool FinalCr,
    string Resume,
    int TableMode,
    bool LiteralPi,
    bool SpaceWords,
    string SecondBoundReturn);
using ListingRun = (
    Retrocore.Tests.RecordingBus Bus,
    Retrocore.Cpu.M6502.Processor<Retrocore.Tests.RecordingBus> Cpu,
    System.Collections.Generic.List<byte> Output,
    System.Collections.Generic.List<int> Numbers,
    ushort Exit,
    int? ErrorReturn);

namespace Retrocore.Tests;

/// <summary>
///  Checks shared LIST parsing and token expansion against AppleSoft and PET BASIC.
/// </summary>
[TestClass]
public sealed class BasicSharedListerTests
{
    private const ushort ReturnAddress = 0x3000;
    private const int TextAddress = 0x3500;
    private const int ProgramAddress = 0x4000;
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  Every AppleSoft model retains its whole image and legacy labels with the shared lister.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedLister(Apple2Model model)
    {
        AssemblyResult legacy = AppleLegacy(model);
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult region = AssembleRegion(legacy, AppleOptions(model));
        CompareRegion(legacy, native);
        CompareRegion(legacy, region);
        AssertEmittedSpan(region, Address(legacy, "LIST"), Address(legacy, "FOR"));
        region.Symbol("LIST_REGION_END").Should().Be(legacy.Symbol("FOR"));
        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
        CompareLabels(legacy, native, 0, 0x10000);
        AssertListerDocumentation(new SourceMapModule(region, area: null).Documentation);
    }

    /// <summary>
    ///  All five PET revisions retain the LIST-to-FOR bytes and legacy labels.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedListerMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult region = AssembleRegion(legacy, PetOptions(model));
        CompareRegion(legacy, region);
        AssertEmittedSpan(region, Address(legacy, "LIST"), Address(legacy, "FOR"));
        region.Symbol("LIST_REGION_END").Should().Be(legacy.Symbol("FOR"));
        AssertListerDocumentation(new SourceMapModule(region, area: null).Documentation);
    }

    /// <summary>
    ///  Both AppleSoft builds retain documentation and breakpoint-capable shared source positions.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void ListerRetainsDocumentationAndSourceChains(Apple2Model model)
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        int start = Address(native, "LIST");
        int end = Address(native, "FOR");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["LIST", "LIST4", "GRODY1", "QPLOP"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(native.Symbol(name));
            topic.Path.Should().EndWith("MsBasic.Lister.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.Lister.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.Lister.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(address);
        }

        AssertListerDocumentation(module.Documentation);
    }

    /// <summary>
    ///  AppleSoft surrounds token expansions with spaces, even for an injected token inside quotes.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleListerExpandsQuotedTokensWithSpaces(Apple2Model model)
    {
        AssemblyResult legacy = AppleLegacy(model);
        ListerOptions options = AppleOptions(model);
        AssemblyResult region = AssembleRegion(legacy, options);
        byte print = BasicDialect.AppleSoft.Tokenize("PRINT").Single();
        byte[] text = [.. BasicDialect.AppleSoft.Tokenize("END:FOR:"), (byte)'"', print, (byte)'"'];
        byte[] expected = Encoding.ASCII.GetBytes("  END : FOR :\" PRINT \"");
        foreach (bool shared in (bool[])[false, true])
        {
            ListingRun run = RunLines(legacy, region, options, apple: true, shared, text);
            run.Output.Should().Equal(expected);
            run.Numbers.Should().Equal(10);
        }
    }

    /// <summary>
    ///  PET preserves quoted high-bit characters and PI, and BASIC 4 walks beyond the first table page.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void PetListerHandlesQuotesPiAndLongTokenTable(PetModel model)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        ListerOptions options = PetOptions(model);
        AssemblyResult region = AssembleRegion(legacy, options);
        BasicDialect dialect = PetDialect(model);
        byte print = dialect.Tokenize("PRINT").Single();
        byte pi = checked((byte)legacy.Symbol("PI"));
        List<byte> text = [.. dialect.Tokenize("END:FOR:"), (byte)'"', print, (byte)'"', (byte)':', print, (byte)':', pi];
        List<byte> expected = [(byte)' ', .. "END:FOR:\""u8.ToArray(), print, .. "\":PRINT:"u8.ToArray(), pi];
        if (model == PetModel.Pet4032)
        {
            text.Add((byte)':');
            text.Add(dialect.Tokenize("DIRECTORY").Single());
            expected.AddRange(":DIRECTORY"u8.ToArray());
        }

        foreach (bool shared in (bool[])[false, true])
        {
            ListingRun run = RunLines(legacy, region, options, apple: false, shared, [.. text]);
            run.Output.Should().Equal(expected);
            run.Bus.Memory[Address(legacy, "DORES")].Should().Be(1);
            if (model == PetModel.Pet4032)
            {
                GetWord(run.Bus.Memory, Address(legacy, "INDEX1"))
                    .Should().BeGreaterThan(Address(legacy, "RESLST") + 255);
            }
        }
    }

    /// <summary>
    ///  PET resets quote state on each line, even after an unterminated quoted field.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void PetQuoteStateDoesNotLeakToTheNextLine(PetModel model)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        ListerOptions options = PetOptions(model);
        AssemblyResult region = AssembleRegion(legacy, options);
        byte print = PetDialect(model).Tokenize("PRINT").Single();
        byte[] expected = [(byte)' ', (byte)'"', print, (byte)' ', .. "PRINT"u8.ToArray()];
        foreach (bool shared in (bool[])[false, true])
        {
            ListingRun run = RunLines(legacy, region, options, apple: false, shared, [(byte)'"', print], [print]);
            run.Output.Should().Equal(expected);
            run.Numbers.Should().Equal(10, 20);
            run.Bus.Memory[Address(legacy, "DORES")].Should().Be(1);
        }
    }

    /// <summary>
    ///  AppleSoft handles ranges, commas and the return flags for invalid text.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleListBoundsAndErrorFlags(Apple2Model model)
    {
        AssemblyResult legacy = AppleLegacy(model);
        ListerOptions options = AppleOptions(model);
        CheckBoundsAndErrors(legacy, AssembleRegion(legacy, options), options, BasicDialect.AppleSoft, apple: true);
    }

    /// <summary>
    ///  Each PET BASIC handles ranges, rejects commas and retains its error-return flags.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void PetListBoundsAndErrorFlags(PetModel model)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        ListerOptions options = PetOptions(model);
        CheckBoundsAndErrors(legacy, AssembleRegion(legacy, options), options, PetDialect(model), apple: false);
    }

    /// <summary>
    ///  BASIC 1 follows a malformed line after Y wraps; BASIC 2 and 4 stop before reading the link.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void PetMalformedLineRetainsItsOffsetWrapBehavior(PetModel model)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        ListerOptions options = PetOptions(model);
        AssemblyResult region = AssembleRegion(legacy, options);
        foreach (bool shared in (bool[])[false, true])
        {
            CheckMalformedLine(legacy, region, options, shared);
        }
    }

    /// <summary>
    ///  The quote and malformed-line switches can be selected independently.
    /// </summary>
    /// <param name="trackQuotes">Whether quoted high-bit bytes are printed literally.</param>
    /// <param name="guardOffset">Whether a wrapped line offset stops listing.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void QuoteTrackingAndOffsetGuardAreIndependent(bool trackQuotes, bool guardOffset)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        ListerOptions options = PetOptions(PetModel.Pet2001Basic2) with
        {
            TrackQuotes = trackQuotes,
            GuardOffset = guardOffset
        };

        AssemblyResult region = AssembleRegion(legacy, options);
        byte print = BasicDialect.PetBasic.Tokenize("PRINT").Single();
        ListingRun run = RunLines(legacy, region, options, apple: false, shared: true, [(byte)'"', print, (byte)'"']);
        byte[] expected = trackQuotes
            ? [(byte)' ', (byte)'"', print, (byte)'"']
            : Encoding.ASCII.GetBytes(" \"PRINT\"");

        run.Output.Should().Equal(expected);
        CheckMalformedLine(legacy, region, options, shared: true);
    }

    /// <summary>
    ///  The FAC table reader carries the offset and reports flags from the loaded byte without changing carry or X.
    /// </summary>
    /// <param name="offset">The offset before the read.</param>
    /// <param name="value">The table byte.</param>
    /// <param name="carry">The incoming carry.</param>
    [TestMethod]
    [DataRow(0xFE, 0x00, true)]
    [DataRow(0xFF, 0x80, false)]
    [DataRow(0xFF, 0x01, true)]
    public void TableReaderCarriesAndPreservesFlags(int offset, int value, bool carry)
    {
        AssemblyResult legacy = AppleLegacy(Apple2Model.IIeEnhanced);
        AssemblyResult region = AssembleRegion(legacy, AppleOptions(Apple2Model.IIeEnhanced));
        RecordingBus bus = CreateBus(legacy, region, shared: true);
        const int pointer = 0x2F10;
        int effective = pointer + offset + 1;
        SetWord(bus.Memory, Address(legacy, "FAC"), pointer);
        bus.Memory[effective] = (byte)value;
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)region.Symbol("GRODY1")),
                Accumulator = 0x5A,
                X = 0x42,
                Y = (byte)offset,
                StackPointer = 0xFD,
                Status = StatusRegister.Unused | (carry ? StatusRegister.Carry : 0)
            }
        };

        for (int instruction = 0; instruction < 20 && cpu.Registers.ProgramCounter != ReturnAddress; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        cpu.Registers.Accumulator.Should().Be((byte)value);
        cpu.Registers.X.Should().Be(0x42);
        cpu.Registers.Y.Should().Be(unchecked((byte)(offset + 1)));
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(carry);
        cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(value == 0);
        cpu.Registers.Status.HasFlag(StatusRegister.Negative).Should().Be((value & 0x80) != 0);
        GetWord(bus.Memory, Address(legacy, "FAC")).Should().Be(pointer + (offset == 0xFF ? 0x100 : 0));
    }

    private static void CheckBoundsAndErrors(
        AssemblyResult legacy,
        AssemblyResult region,
        ListerOptions options,
        BasicDialect dialect,
        bool apple)
    {
        (string Command, int[] Lines)[] cases =
        [
            ("", [10, 20, 30]),
            ("0", [10, 20, 30]),
            ("20", [20]),
            ("25", []),
            ("15-30", [20, 30]),
            ("-20", [10, 20]),
            ("20-", [20, 30])
        ];

        foreach (bool shared in (bool[])[false, true])
        {
            foreach ((string command, int[] lines) in cases)
            {
                ListingRun run = RunCommand(legacy, region, options, dialect, apple, shared, command);
                run.Exit.Should().Be(checked((ushort)(shared ? region : legacy).Symbol("GRODY")), command);
                run.Numbers.Should().Equal(lines, command);
            }

            ListingRun comma = RunCommand(legacy, region, options, dialect, apple, shared, "10,20");
            if (options.CommaRange)
            {
                comma.Numbers.Should().Equal(10, 20);
            }
            else
            {
                comma.Exit.Should().Be(ReturnAddress);
                comma.ErrorReturn.Should().Be(Address(legacy, "FLNRTS"));
                comma.Numbers.Should().BeEmpty();
            }

            ListingRun trailing = RunCommand(legacy, region, options, dialect, apple, shared, "10-20X");
            trailing.Exit.Should().Be(ReturnAddress);
            trailing.ErrorReturn.Should().Be(Address(legacy, options.SecondBoundReturn));
            trailing.Cpu.Registers.Accumulator.Should().Be((byte)'X');
            trailing.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
            trailing.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeFalse();

            ListingRun first = RunCommand(legacy, region, options, dialect, apple, shared, "X");
            first.Exit.Should().Be(ReturnAddress);
            first.ErrorReturn.Should().Be(Address(legacy, "STKRTS"));
            int compared = options.CommaRange ? ',' : Address(legacy, "MINUTK");
            first.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be('X' >= compared);
            first.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeFalse();
            first.Cpu.Registers.Status.HasFlag(StatusRegister.Negative)
                .Should().Be((unchecked((byte)('X' - compared)) & 0x80) != 0);
        }
    }

    private static void CheckMalformedLine(
        AssemblyResult legacy,
        AssemblyResult region,
        ListerOptions options,
        bool shared)
    {
        RecordingBus bus = CreateBus(legacy, region, shared);
        const int next = ProgramAddress + 0x100;
        SetWord(bus.Memory, ProgramAddress, next);
        SetWord(bus.Memory, ProgramAddress + 2, 10);
        bus.Memory.AsSpan(ProgramAddress + 4, 252).Fill((byte)'A');
        SetWord(bus.Memory, next, 0);
        SetWord(bus.Memory, Address(legacy, "LOWTR"), ProgramAddress);
        SetWord(bus.Memory, Address(legacy, "LINNUM"), 0xFFFF);
        ListingRun run = Execute(legacy, region, options, apple: false, shared, bus, "LIST4");
        run.Numbers.Should().Equal(10);
        run.Output.Should().HaveCount(253);
        GetWord(bus.Memory, Address(legacy, "LOWTR")).Should().Be(options.GuardOffset ? ProgramAddress : next);
    }

    private static ListingRun RunLines(
        AssemblyResult legacy,
        AssemblyResult region,
        ListerOptions options,
        bool apple,
        bool shared,
        params byte[][] lines)
    {
        RecordingBus bus = CreateBus(legacy, region, shared);
        int address = ProgramAddress;
        for (int index = 0; index < lines.Length; index++)
        {
            address = PutLine(bus.Memory, address, (index + 1) * 10, lines[index]);
        }

        SetWord(bus.Memory, Address(legacy, "LOWTR"), ProgramAddress);
        SetWord(bus.Memory, Address(legacy, "LINNUM"), 0xFFFF);
        return Execute(legacy, region, options, apple, shared, bus, "LIST4");
    }

    private static ListingRun RunCommand(
        AssemblyResult legacy,
        AssemblyResult region,
        ListerOptions options,
        BasicDialect dialect,
        bool apple,
        bool shared,
        string command)
    {
        RecordingBus bus = CreateBus(legacy, region, shared);
        int next = ProgramAddress;
        for (int number = 10; number <= 30; number += 10)
        {
            next = PutLine(bus.Memory, next, number, []);
        }

        SetWord(bus.Memory, Address(legacy, "TXTTAB"), ProgramAddress);
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        byte[] text = [.. dialect.Tokenize(command), (byte)':'];
        text.CopyTo(bus.Memory, TextAddress);
        SetWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        byte first = text[0];
        bool digit = first is >= (byte)'0' and <= (byte)'9';
        StatusRegister status = StatusRegister.Unused | (digit ? 0 : StatusRegister.Carry);
        if (first == ':') { status |= StatusRegister.Zero; }
        return Execute(legacy, region, options, apple, shared, bus, "LIST", first, status, stack: 0xFD);
    }

    private static ListingRun Execute(
        AssemblyResult legacy,
        AssemblyResult region,
        ListerOptions options,
        bool apple,
        bool shared,
        RecordingBus bus,
        string entry,
        byte accumulator = 0,
        StatusRegister status = StatusRegister.Unused,
        byte stack = 0xFF)
    {
        if (options.ColumnMode != 0) { bus.Memory[Address(legacy, "TRMPOS")] = 0; }
        AssemblyResult code = shared ? region : legacy;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)code.Symbol(entry)),
                Accumulator = accumulator,
                StackPointer = stack,
                Status = status
            }
        };

        List<byte> output = [];
        List<int> numbers = [];
        int? errorReturn = null;
        ushort finish = checked((ushort)code.Symbol("GRODY"));
        for (int instruction = 0; instruction < 30000; instruction++)
        {
            ushort pc = cpu.Registers.ProgramCounter;
            if (pc == finish || pc == ReturnAddress)
            {
                return (bus, cpu, output, numbers, pc, errorReturn);
            }

            if ((pc == Address(legacy, "STKRTS") || pc == Address(legacy, "FLNRTS"))
                && cpu.Registers.StackPointer == 0xFD)
            {
                errorReturn = pc;
            }

            if (pc == Address(legacy, "OUTDO"))
            {
                ProcessorRegisters registers = cpu.Registers;
                byte character = apple ? (byte)(registers.Accumulator & 0x7F) : registers.Accumulator;
                output.Add(character);
                registers.Accumulator = character;
                registers.Status &= ~(StatusRegister.Zero | StatusRegister.Negative);
                if (character == 0) { registers.Status |= StatusRegister.Zero; }
                if ((character & 0x80) != 0) { registers.Status |= StatusRegister.Negative; }
                cpu.Registers = registers;
                ReturnFromStub(cpu, bus.Memory);
            }
            else if (pc == Address(legacy, options.LinePrinter))
            {
                numbers.Add((cpu.Registers.Accumulator << 8) | cpu.Registers.X);
                ReturnFromStub(cpu, bus.Memory);
            }
            else if (pc == Address(legacy, "ISCNTC") || pc == Address(legacy, "CRDO"))
            {
                ReturnFromStub(cpu, bus.Memory);
            }
            else
            {
                cpu.StepInstruction();
            }
        }

        throw new AssertFailedException($"LIST did not reach an expected exit; PC=${cpu.Registers.ProgramCounter:X4}.");
    }

    private static void ReturnFromStub(Processor<RecordingBus> cpu, byte[] memory)
    {
        ProcessorRegisters registers = cpu.Registers;
        byte low = memory[0x0100 | unchecked((byte)(registers.StackPointer + 1))];
        byte high = memory[0x0100 | unchecked((byte)(registers.StackPointer + 2))];
        registers.StackPointer = unchecked((byte)(registers.StackPointer + 2));
        registers.ProgramCounter = unchecked((ushort)((low | (high << 8)) + 1));
        cpu.Registers = registers;
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, ListerOptions options)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Lister.asm"
            .org ${legacy.Symbol("LIST"):X4}
                LIST_RANGE {(options.CommaRange ? 1 : 0)}, {options.SecondBoundReturn}
                LIST_LINES {(options.TrackQuotes ? 1 : 0)}, {(options.GuardOffset ? 1 : 0)}, {options.ColumnMode}, {options.LinePrinter}, {(options.FinalCr ? 1 : 0)}, {options.Resume}
                {(options.TableMode == 2 ? "LIST_TABLE_NEXT" : "")}
                LIST_TOKENS {options.TableMode}, {(options.TrackQuotes ? 1 : 0)}, {(options.LiteralPi ? 1 : 0)}, {(options.SpaceWords ? 1 : 0)}
            LIST_REGION_END:
            """;

        List<string> dependencies =
        [
            "MINUTK", "STKRTS", "LINGET", "FNDLIN", "CHRGOT", "FLNRTS", "CHRGET", "LINNUM", "LOWTR",
            "ISCNTC", "CRDO", "LSTPNT", "OUTDO", "RESLST", "DORES", "INDEX1", "FAC", "FACHO",
            options.LinePrinter, options.Resume
        ];

        if (options.LiteralPi) { dependencies.Add("PI"); }
        if (options.ColumnMode != 0) { dependencies.Add("TRMPOS"); }
        if (options.ColumnMode == 2) { dependencies.Add("CHKCOL"); }
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "SharedListerTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "LIST");
        int end = Address(legacy, "FOR");
        CompareLabels(legacy, native, start, end);
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static void AssertListerDocumentation(DocumentationSet documentation)
    {
        DocumentationResolver resolver = new(
            documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.Lister.asm" or "AppleSoft.Lister.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static void CompareLabels(AssemblyResult legacy, AssemblyResult native, int start, int end)
    {
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            if (label.Name.StartsWith("__m10_", StringComparison.Ordinal)) { continue; }

            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }
    }

    private static void AssertEmittedSpan(AssemblyResult region, int start, int end)
    {
        int next = start;
        foreach (AssemblySourceMapEntry entry in region.SourceMap.Where(entry =>
            entry.Size > 0 && entry.Operation != ".ORG").OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            entry.Address.Should().Be(next, "the native region must not have a gap or overlap");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end);
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, bool shared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (shared)
        {
            int start = Address(region, "LIST");
            int end = Address(region, "LIST_REGION_END");
            region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        return bus;
    }

    private static int PutLine(byte[] memory, int address, int number, byte[] text)
    {
        int next = address + 5 + text.Length;
        SetWord(memory, address, next);
        SetWord(memory, address + 2, number);
        text.CopyTo(memory, address + 4);
        memory[address + 4 + text.Length] = 0;
        SetWord(memory, next, 0);
        return next;
    }

    private static AssemblyResult AppleLegacy(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), model);

    private static ListerOptions AppleOptions(Apple2Model model)
    {
        bool enhanced = model == Apple2Model.IIeEnhanced;
        return (
            CommaRange: true,
            TrackQuotes: false,
            GuardOffset: false,
            ColumnMode: enhanced ? 2 : 1,
            LinePrinter: enhanced ? "SPCLIN" : "LINPRT",
            FinalCr: true,
            Resume: "NXTCO1",
            TableMode: 2,
            LiteralPi: false,
            SpaceWords: true,
            SecondBoundReturn: "STKRTS");
    }

    private static ListerOptions PetOptions(PetModel model) =>
        (
            CommaRange: false,
            TrackQuotes: true,
            GuardOffset: model != PetModel.Pet2001,
            ColumnMode: 0,
            LinePrinter: "LINPRT",
            FinalCr: false,
            Resume: "READY",
            TableMode: model == PetModel.Pet4032 ? 1 : 0,
            LiteralPi: true,
            SpaceWords: false,
            SecondBoundReturn: "FLNRTS");

    private static BasicDialect PetDialect(PetModel model) => model switch
    {
        PetModel.Pet2001 => BasicDialect.PetBasic1,
        PetModel.Pet2001Basic2 => BasicDialect.PetBasic,
        _ => BasicDialect.PetBasic4
    };

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));

    private static int GetWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void SetWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
