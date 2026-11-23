// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks shared string functions against the AppleSoft and PET BASIC overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedStringFunctionTests
{
    private const ushort ReturnAddress = 0x2000;
    private const int TextAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  Each AppleSoft model consumes the shared region without changing its image or legacy ROM labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedStringFunctions(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult region = AssembleRegion(legacy, rejectZeroSlices: true, indirectReturn: false, sharedLenJump: false, zeroTermViaY: false);
        CompareRegion(legacy, native);
        CompareRegion(legacy, region);
        AssertEmittedSpan(region, Address(legacy, "CHR"), Address(legacy, "GETNUM"));
        region.Symbol("STRING_FUNCTIONS_END").Should().Be(legacy.Symbol("GETNUM"));
        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
        CompareLabels(legacy, native, 0, 0x10000);
    }

    /// <summary>
    ///  All five PET revisions retain the complete contiguous region and its legacy labels.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedStringFunctionsMatchPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult region = AssemblePetRegion(legacy, model);
        CompareRegion(legacy, region);
        AssertEmittedSpan(region, Address(legacy, "CHR"), Address(legacy, "GETNUM"));
        region.Symbol("STRING_FUNCTIONS_END").Should().Be(legacy.Symbol("GETNUM"));
    }

    /// <summary>
    ///  AppleSoft keeps its historical slice errors and string and numeric results.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftStringExpressionsKeepTheirBehavior(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult region = AssembleRegion(legacy, rejectZeroSlices: true, indirectReturn: false, sharedLenJump: false, zeroTermViaY: false);
        CheckExpressions(legacy, region, BasicDialect.AppleSoft, rejectZeroSlices: true);
        CheckPreamble(legacy, region, useShared: false, rejectZeroSlices: true, indirectReturn: false);
        CheckPreamble(legacy, region, useShared: true, rejectZeroSlices: true, indirectReturn: false);
        CheckValRestoration(legacy, region);
    }

    /// <summary>
    ///  PET BASIC 1 rejects zero slice counts; BASIC 2 and 4 allow them but still reject a zero MID start.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetStringExpressionsKeepEachVersionsBehavior(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult region = AssemblePetRegion(legacy, model);
        BasicDialect dialect = model switch
        {
            PetModel.Pet2001 => BasicDialect.PetBasic1,
            PetModel.Pet2001Basic2 => BasicDialect.PetBasic,
            _ => BasicDialect.PetBasic4
        };

        bool early = model == PetModel.Pet2001;
        CheckExpressions(legacy, region, dialect, rejectZeroSlices: early);
        CheckPreamble(legacy, region, useShared: false, rejectZeroSlices: early, indirectReturn: early);
        CheckPreamble(legacy, region, useShared: true, rejectZeroSlices: early, indirectReturn: early);
        CheckValRestoration(legacy, region);
    }

    /// <summary>
    ///  The early indirect return wraps at a page boundary independently of the zero-count check.
    /// </summary>
    /// <param name="rejectZeroSlices">Whether PREAM rejects a zero argument.</param>
    /// <param name="indirectReturn">Whether PREAM uses the early indirect return.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void PreambleReturnAndZeroCheckingAreIndependent(bool rejectZeroSlices, bool indirectReturn)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult region = AssembleRegion(legacy, rejectZeroSlices, indirectReturn, sharedLenJump: false, zeroTermViaY: false);
        CheckPreamble(legacy, region, useShared: true, rejectZeroSlices, indirectReturn);
    }

    /// <summary>
    ///  MID checks its start rather than the indirect return's flags in the independently selectable combination.
    /// </summary>
    [TestMethod]
    public void MidChecksTheArgumentWithAnIndirectPreamble()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult region = AssembleRegion(legacy, rejectZeroSlices: false, indirectReturn: true, sharedLenJump: true, zeroTermViaY: true);
        foreach ((byte start, string expected) in ((byte, string)[])[(0, ""), (1, "ABCDE"), (2, "BCDE"), (6, "")])
        {
            RecordingBus bus = CreateBus(legacy, region, useShared: true);
            PrepareRuntime(bus, legacy);
            bus.Memory[Address(legacy, "CHKCLS")] = 0x60;
            bus.Memory[0x5000] = 5;
            SetWord(bus.Memory, 0x5001, 0x60F0);
            "ABCDE"u8.CopyTo(bus.Memory.AsSpan(0x60F0));
            bus.Memory[Address(legacy, "FACLO")] = 0xFF;
            bus.Memory[0x01F9] = 0xAA;
            bus.Memory[0x01FA] = 0xBB;
            bus.Memory[0x01FB] = start;
            SetWord(bus.Memory, 0x01FC, 0x5000);
            SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = checked((ushort)region.Symbol("MID2")),
                    StackPointer = 0xF8,
                    Status = StatusRegister.Unused
                }
            };

            ushort error = checked((ushort)region.Symbol("GOFUC"));
            StepUntil(cpu, 10000, ReturnAddress, error, checked((ushort)legacy.Symbol("ERROR")));
            cpu.Registers.ProgramCounter.Should().Be(start == 0 ? error : ReturnAddress);
            if (start == 0) { continue; }

            int descriptor = GetWord(bus.Memory, Address(legacy, "FACMO"));
            int length = bus.Memory[descriptor];
            int data = GetWord(bus.Memory, descriptor + 1);
            bus.Memory.AsSpan(data, length).ToArray().Should().Equal(System.Text.Encoding.ASCII.GetBytes(expected));
        }
    }

    /// <summary>
    ///  The LEN/ASC jump and VAL's terminator instruction may be selected independently.
    /// </summary>
    /// <param name="sharedLenJump">Whether ASC passes through LENFLT.</param>
    /// <param name="zeroTermViaY">Whether VAL uses TYA for its terminator.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void NumericStringChoicesAreIndependent(bool sharedLenJump, bool zeroTermViaY)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult region = AssembleRegion(legacy, rejectZeroSlices: false, indirectReturn: false, sharedLenJump, zeroTermViaY);
        RecordingBus bus = CreateBus(legacy, region, useShared: true);
        PrepareRuntime(bus, legacy);
        bus.Memory[0x5000] = 1;
        SetWord(bus.Memory, 0x5001, 0x60FE);
        bus.Memory[0x60FE] = 0xFF;
        SetWord(bus.Memory, Address(legacy, "FACMO"), 0x5000);
        bus.Memory[Address(legacy, "VALTYP")] = 0xFF;
        Processor<RecordingBus> cpu = Start(bus, Address(region, "ASC"));
        StepUntil(cpu, 10000, ReturnAddress, checked((ushort)legacy.Symbol("FCERR")));
        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        GetIntegerResult(bus, legacy).Should().Be(255);
        if (sharedLenJump)
        {
            ushort jump = checked((ushort)region.Symbol("LENFLT"));
            bus.Accesses.Should().Contain(access => access.Address == jump && access.Operation == BusOperation.Read);
        }

        CheckValRestoration(legacy, region);
    }

    /// <summary>
    ///  Promoted entries retain documentation and breakpoint-capable source chains in AppleSoft.
    /// </summary>
    [TestMethod]
    public void StringFunctionsRetainDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = Address(native, "CHR");
        int end = Address(native, "GETNUM");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);

        foreach (string name in (string[])["CHR", "LEFT", "RIGHT", "MID", "PREAM", "LEN", "LEN1", "ASC", "GTBYTC", "GETBYT", "CONINT", "VAL", "ST2TXT"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(native.Symbol(name));
            topic.Path.Should().EndWith("MsBasic.StringFunctions.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        foreach (string name in (string[])["CHR", "PREAM", "VAL"])
        {
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.StringFunctions.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.Strings.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain((ushort)start);
        }

        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.StringFunctions.asm" or "AppleSoft.Strings.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static void CheckPreamble(
        AssemblyResult legacy,
        AssemblyResult region,
        bool useShared,
        bool rejectZeroSlices,
        bool indirectReturn)
    {
        foreach (ushort savedReturn in (ushort[])[0x31FF, 0x317F])
        {
            foreach (byte argument in (byte[])[0, 2])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                bus.Memory[Address(legacy, "CHKCLS")] = 0x60;
                SetWord(bus.Memory, 0x01F9, savedReturn);
                bus.Memory[0x01FB] = 0xAA;
                bus.Memory[0x01FC] = 0xBB;
                bus.Memory[0x01FD] = argument;
                bus.Memory[0x01FE] = 0x34;
                bus.Memory[0x01FF] = 0x12;
                Processor<RecordingBus> cpu = new(bus)
                {
                    Registers = new()
                    {
                        ProgramCounter = checked((ushort)(useShared ? region : legacy).Symbol("PREAM")),
                        StackPointer = 0xF8,
                        Status = StatusRegister.Unused
                    }
                };

                ushort error = checked((ushort)(useShared ? region : legacy).Symbol("GOFUC"));
                ushort target = indirectReturn
                    ? (ushort)((savedReturn & 0xFF00) | ((savedReturn + 1) & 0xFF))
                    : (ushort)(savedReturn + 1);

                StepUntil(cpu, 100, target, 0x3100, 0x3200, error);
                bool rejected = rejectZeroSlices && argument == 0;
                cpu.Registers.ProgramCounter.Should().Be(rejected ? error : target);
                GetWord(bus.Memory, Address(legacy, "DSCPNT")).Should().Be(0x1234);
                cpu.Registers.X.Should().Be(argument);
                cpu.Registers.Accumulator.Should().Be(argument);
                cpu.Registers.Y.Should().Be(0);
                if (!rejected)
                {
                    cpu.Registers.StackPointer.Should().Be(0xFF);
                    bool zero = indirectReturn ? (savedReturn & 0xFF) == 0xFF : argument == 0;
                    cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(zero);
                    bool negative = indirectReturn && (savedReturn & 0xFF) == 0x7F;
                    cpu.Registers.Status.HasFlag(StatusRegister.Negative).Should().Be(negative);
                }
            }
        }
    }

    private static void CheckExpressions(AssemblyResult legacy, AssemblyResult region, BasicDialect dialect, bool rejectZeroSlices)
    {
        (string Expression, byte[]? Text, int? Number, bool Error)[] cases =
        [
            ("LEFT$(\"ABCDE\",0)", [], null, rejectZeroSlices),
            ("RIGHT$(\"ABCDE\",0)", [], null, rejectZeroSlices),
            ("MID$(\"ABCDE\",0)", null, null, true),
            ("LEFT$(\"ABCDE\",2)", "AB"u8.ToArray(), null, false),
            ("RIGHT$(\"ABCDE\",2)", "DE"u8.ToArray(), null, false),
            ("LEFT$(\"ABCDE\",9)", "ABCDE"u8.ToArray(), null, false),
            ("RIGHT$(\"ABCDE\",9)", "ABCDE"u8.ToArray(), null, false),
            ("MID$(\"ABCDE\",2)", "BCDE"u8.ToArray(), null, false),
            ("MID$(\"ABCDE\",2,3)", "BCD"u8.ToArray(), null, false),
            ("MID$(\"ABCDE\",2,0)", [], null, false),
            ("MID$(\"ABCDE\",6)", [], null, false),
            ("CHR$(0)", [0], null, false),
            ("CHR$(255)", [255], null, false),
            ("CHR$(256)", null, null, true),
            ("ASC(\"\")", null, null, true),
            ("ASC(\"A\")", null, 65, false),
            ("LEN(\"ABCDE\")", null, 5, false),
            ("VAL(\"1234Z\")", null, 1234, false),
            ("VAL(\"\")", null, 0, false)
        ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                PrepareRuntime(bus, legacy);
                byte[] text = dialect.Tokenize(test.Expression);
                text.CopyTo(bus.Memory, TextAddress);
                SetWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
                Processor<RecordingBus> cpu = Start(bus, Address(legacy, "FRMEVL"));
                ushort error = checked((ushort)legacy.Symbol("FCERR"));
                ushort syntax = checked((ushort)legacy.Symbol("SNERR"));
                ushort otherError = checked((ushort)legacy.Symbol("ERROR"));
                StepUntil(cpu, 30000, ReturnAddress, error, syntax, otherError);
                cpu.Registers.ProgramCounter.Should().Be(
                    test.Error ? error : ReturnAddress,
                    $"{test.Expression} with {(useShared ? "shared" : "legacy")} code");

                if (test.Error) { continue; }

                if (test.Text is not null)
                {
                    (bus.Memory[Address(legacy, "VALTYP")] & 0x80).Should().Be(0x80, test.Expression);
                    int descriptor = GetWord(bus.Memory, Address(legacy, "FACMO"));
                    int length = bus.Memory[descriptor];
                    int data = GetWord(bus.Memory, descriptor + 1);
                    bus.Memory.AsSpan(data, length).ToArray().Should().Equal(test.Text, test.Expression);
                }
                else
                {
                    (bus.Memory[Address(legacy, "VALTYP")] & 0x80).Should().Be(0, test.Expression);
                    int number = test.Number ?? throw new AssertFailedException($"No expected result for {test.Expression}.");
                    GetIntegerResult(bus, legacy).Should().Be(number, test.Expression);
                }
            }
        }
    }

    private static void CheckValRestoration(AssemblyResult legacy, AssemblyResult region)
    {
        const int descriptor = 0x5000;
        const int characters = 0x60FE;
        const int terminator = characters + 4;
        const int callerText = 0x3500;
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, region, useShared);
            PrepareRuntime(bus, legacy);
            bus.Memory[descriptor] = 4;
            SetWord(bus.Memory, descriptor + 1, characters);
            "1234"u8.CopyTo(bus.Memory.AsSpan(characters));
            bus.Memory[terminator] = (byte)'9';
            SetWord(bus.Memory, Address(legacy, "FACMO"), descriptor);
            bus.Memory[Address(legacy, "VALTYP")] = 0xFF;
            SetWord(bus.Memory, Address(legacy, "TXTPTR"), callerText);
            Processor<RecordingBus> cpu = Start(bus, Address(useShared ? region : legacy, "VAL"));
            StepUntil(cpu, 30000, ReturnAddress, checked((ushort)legacy.Symbol("ERROR")));
            cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
            GetWord(bus.Memory, Address(legacy, "TXTPTR")).Should().Be(callerText);
            bus.Memory[terminator].Should().Be((byte)'9');
            bus.Accesses.Where(access => access.Address == terminator && access.Operation == BusOperation.Write)
                .Select(access => access.Value).Should().Equal(0, (byte)'9');

            GetIntegerResult(bus, legacy).Should().Be(1234);

            RecordingBus overflow = CreateBus(legacy, region, useShared);
            PrepareRuntime(overflow, legacy);
            overflow.Memory[descriptor] = 5;
            SetWord(overflow.Memory, descriptor + 1, characters);
            "1E999"u8.CopyTo(overflow.Memory.AsSpan(characters));
            overflow.Memory[characters + 5] = (byte)'9';
            SetWord(overflow.Memory, Address(legacy, "FACMO"), descriptor);
            overflow.Memory[Address(legacy, "VALTYP")] = 0xFF;
            SetWord(overflow.Memory, Address(legacy, "TXTPTR"), callerText);
            Processor<RecordingBus> failed = Start(overflow, Address(useShared ? region : legacy, "VAL"));
            ushort error = checked((ushort)legacy.Symbol("OVERR"));
            StepUntil(failed, 30000, ReturnAddress, error);
            failed.Registers.ProgramCounter.Should().Be(error);
            overflow.Memory[characters + 5].Should().Be(0);
            GetWord(overflow.Memory, Address(legacy, "TXTPTR")).Should().NotBe(callerText);
        }
    }

    private static AssemblyResult AssemblePetRegion(AssemblyResult legacy, PetModel model)
    {
        bool early = model == PetModel.Pet2001;
        return AssembleRegion(
            legacy,
            rejectZeroSlices: early,
            indirectReturn: early,
            sharedLenJump: early,
            zeroTermViaY: model == PetModel.Pet4032);
    }

    private static AssemblyResult AssembleRegion(
        AssemblyResult legacy,
        bool rejectZeroSlices,
        bool indirectReturn,
        bool sharedLenJump,
        bool zeroTermViaY)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StringFunctions.asm"
            .org ${legacy.Symbol("CHR"):X4}
                STRING_FUNCTIONS {(rejectZeroSlices ? 1 : 0)}, {(indirectReturn ? 1 : 0)}, {(sharedLenJump ? 1 : 0)}, {(zeroTermViaY ? 1 : 0)}
            STRING_FUNCTIONS_END:
            """;

        string[] dependencies =
        [
            "STRSPA", "DSCTMP", "PUTNEW", "DSCPNT", "FRETMP", "INDEX", "MOVDO", "FACMO", "FACLO", "CHRGOT",
            "CHKCOM", "CHKCLS", "JMPER", "FRESTR", "VALTYP", "SNGFLT", "FCERR", "CHRGET", "FRMNUM",
            "POSINT", "TXTPTR", "STRNG2", "INDEX2", "ZEROFC", "FIN"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "StringFunctionsTest.asm")),
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
        int start = Address(legacy, "CHR");
        int end = Address(legacy, "GETNUM");
        CompareLabels(legacy, native, start, end);
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static void CompareLabels(AssemblyResult legacy, AssemblyResult native, int start, int end)
    {
        // Macro-10's generated local names are assembler internals, not legacy source labels.
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant
                && !symbol.Name.StartsWith("__m10_", StringComparison.Ordinal)
                && symbol.Value >= start
                && symbol.Value < end))
        {
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

        next.Should().Be(end, "the native region must emit exactly CHR through VALRTS");
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, bool useShared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (useShared)
        {
            int start = Address(region, "CHR");
            int end = Address(region, "STRING_FUNCTIONS_END");
            region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        return bus;
    }

    private static void PrepareRuntime(RecordingBus bus, AssemblyResult legacy)
    {
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        bus.Memory[Address(legacy, "JMPER")] = 0x4C;
        int temp = Address(legacy, "TEMPST");
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)temp;
        SetWord(bus.Memory, Address(legacy, "LASTPT"), temp - 3);
        SetWord(bus.Memory, Address(legacy, "STREND"), 0x5000);
        SetWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        SetWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x7000);
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, int address)
    {
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
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

    private static int GetIntegerResult(RecordingBus bus, AssemblyResult legacy)
    {
        Processor<RecordingBus> cpu = Start(bus, Address(legacy, "QINT"));
        StepUntil(cpu, 10000, ReturnAddress);
        return (bus.Memory[Address(legacy, "FACMO")] << 8) | bus.Memory[Address(legacy, "FACLO")];
    }

    private static void StepUntil(Processor<RecordingBus> cpu, int limit, params ushort[] exits)
    {
        for (int instruction = 0; instruction < limit && !exits.Contains(cpu.Registers.ProgramCounter); instruction++)
        {
            cpu.StepInstruction();
        }

        exits.Should().Contain(cpu.Registers.ProgramCounter, "the routine must reach an expected exit");
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));

    private static int GetWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void SetWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
