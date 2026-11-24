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
///  Checks shared subscript and signed integer conversion against AppleSoft and PET BASIC.
/// </summary>
[TestClass]
public sealed class BasicSharedIntegerConversionTests
{
    private const ushort ReturnAddress = 0x4000;
    private const ushort NumericEvaluator = 0x5000;
    private const ushort GeneralEvaluator = 0x5010;
    private const ushort CharacterReader = 0x5020;
    private const int TextAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  Every AppleSoft model retains its whole ROM, conversion region, and legacy entry points.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedIntegerConversion(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult region = AssembleRegion(legacy, numericEvaluator: true, checkType: false);
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
        CompareRegion(legacy, native, "QINTG1");
        CompareRegion(legacy, region, "QINTG1");
        region.Symbol("INTEGER_CONVERSION_END").Should().Be(legacy.Symbol("QINTG1"));
        CheckBoundaries(legacy, region);
        CheckTypeCases(legacy, region, checkType: false);
        CheckSubscripts(legacy, region, BasicDialect.AppleSoft);
        CheckSignedExpressions(legacy, region, BasicDialect.AppleSoft);
    }

    /// <summary>
    ///  Every PET revision matches the corresponding legacy code and its conversion behavior.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedIntegerConversionMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        bool early = model == PetModel.Pet2001;
        AssemblyResult region = AssembleRegion(legacy, numericEvaluator: early, checkType: !early);
        CompareRegion(legacy, region, "ISARY");
        region.Symbol("INTEGER_CONVERSION_END").Should().Be(legacy.Symbol("ISARY"));
        CheckBoundaries(legacy, region);
        CheckTypeCases(legacy, region, checkType: !early);
        BasicDialect dialect = model switch
        {
            PetModel.Pet2001 => BasicDialect.PetBasic1,
            PetModel.Pet2001Basic2 => BasicDialect.PetBasic,
            _ => BasicDialect.PetBasic4
        };

        CheckSubscripts(legacy, region, dialect);
        CheckSignedExpressions(legacy, region, dialect);
    }

    /// <summary>
    ///  Choosing the evaluator and inserting POSINT's type check are independently configurable.
    /// </summary>
    /// <param name="numericEvaluator">Whether the numeric rather than general evaluator is selected.</param>
    /// <param name="checkType">Whether POSINT checks the type.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void EvaluatorAndTypeCheckAreIndependent(bool numericEvaluator, bool checkType)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            Apple2Model.IIeEnhanced);

        AssemblyResult region = AssembleRegion(legacy, numericEvaluator, checkType, stubEvaluator: true);
        RecordingBus bus = CreateBus(legacy, region, shared: true);
        InstallCounter(bus.Memory, NumericEvaluator, 0x0600);
        InstallCounter(bus.Memory, GeneralEvaluator, 0x0601);
        InstallCounter(bus.Memory, CharacterReader, 0x0602);
        SetFac(bus, legacy, 0, 0, 0, 0, 0, 0, 0);
        bus.Memory[Address(legacy, "VALTYP")] = 0;
        Processor<RecordingBus> cpu = Start(bus, region, "INTIDX");
        ushort finish = checked((ushort)legacy.Symbol("QINT"));
        ushort typeCheck = checked((ushort)legacy.Symbol("CHKNUM"));
        int checks = 0;
        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != finish; instruction++)
        {
            if (cpu.Registers.ProgramCounter == typeCheck) { checks++; }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
        bus.Memory[0x0600].Should().Be(numericEvaluator ? (byte)1 : (byte)0);
        bus.Memory[0x0601].Should().Be(numericEvaluator ? (byte)0 : (byte)1);
        bus.Memory[0x0602].Should().Be(1);
        checks.Should().Be(checkType ? 1 : 0);
        CheckTypeCases(legacy, region, checkType, includeLegacy: false);
    }

    /// <summary>
    ///  The comparison prefix cannot be separated from the JSR opcode that supplies its fifth byte.
    /// </summary>
    [TestMethod]
    public void BoundaryMustImmediatelyPrecedeConversion()
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            Apple2Model.IIeEnhanced);

        AssemblyResult separated = AssembleRegion(legacy, numericEvaluator: true, checkType: false, insertGap: true);
        separated.Success.Should().BeFalse();
        separated.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains(
            "IntegerConversion must immediately follow IntegerConversionBoundary", StringComparison.Ordinal));
    }

    /// <summary>
    ///  Shared entries are documented and support breakpoints; the invocation binds to INTIDX.
    /// </summary>
    [TestMethod]
    public void EntriesRetainDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs),
            Apple2Model.IIeEnhanced);

        int start = Address(native, "N32768");
        int end = Address(native, "QINTG1");
        ushort firstEntry = checked((ushort)native.Symbol("INTIDX"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["INTIDX", "POSINT", "AYINT", "QINTGO"])
        {
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.IntegerConversion.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.Arrays.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(firstEntry);
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(address);
            topic.Path.Should().EndWith("MsBasic.IntegerConversion.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        DocumentationTopic constant = module.Documentation.FindTopic("N32768")
            ?? throw new AssertFailedException("N32768 is not documented.");

        constant.Kind.Should().Be(DocumentationKind.Table);
        constant.Path.Should().EndWith("MsBasic.IntegerConversion.asm");
        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) == "MsBasic.IntegerConversion.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static void CheckBoundaries(AssemblyResult legacy, AssemblyResult region)
    {
        (string Name, string Entry, byte Exponent, byte High, byte MiddleHigh, byte Middle, byte Low, byte Sign, byte Guard, int? Result)[] cases =
        [
            ("zero", "POSINT", 0x00, 0x55, 0, 0, 0, 0, 0, 0),
            ("positive half", "POSINT", 0x80, 0x80, 0, 0, 0, 0, 0, 0),
            ("positive one and a half", "POSINT", 0x81, 0xC0, 0, 0, 0, 0, 0, 1),
            ("largest positive fraction below 32768", "POSINT", 0x8F, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0x7FFF),
            ("positive 32768", "POSINT", 0x90, 0x80, 0, 0, 0, 0, 0, null),
            ("negative half", "POSINT", 0x80, 0x80, 0, 0, 0, 0x80, 0, null),
            ("negative sign on zero", "POSINT", 0x00, 0, 0, 0, 0, 0x80, 0, null),
            ("signed negative half", "AYINT", 0x80, 0x80, 0, 0, 0, 0x80, 0, 0xFFFF),
            ("signed negative one and a half", "AYINT", 0x81, 0xC0, 0, 0, 0, 0x80, 0, 0xFFFE),
            ("fraction just above -32768", "AYINT", 0x8F, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0, 0x8000),
            ("exact -32768", "AYINT", 0x90, 0x80, 0, 0, 0, 0x80, 0, null),
            ("overlapped comparison byte", "AYINT", 0x90, 0x80, 0, 0, 0x20, 0x80, 0, 0x7FFF),
            ("overlapped comparison with guard", "AYINT", 0x90, 0x80, 0, 0, 0x1F, 0x80, 0x80, 0x7FFF),
            ("past the overlapped comparison", "AYINT", 0x90, 0x80, 0, 0, 0x21, 0x80, 0, null),
            ("negative 65536", "AYINT", 0x91, 0x80, 0, 0, 0, 0x80, 0, null),
            ("unchecked positive 32768", "QINTGO", 0x90, 0x80, 0, 0, 0, 0, 0, 0x8000),
            ("unchecked negative half", "QINTGO", 0x80, 0x80, 0, 0, 0, 0x80, 0, 0xFFFF)
        ];

        ushort error = checked((ushort)legacy.Symbol("FCERR"));
        foreach (var value in cases)
        {
            foreach (bool shared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, shared);
                SetFac(bus, legacy, value.Exponent, value.High, value.MiddleHigh, value.Middle, value.Low, value.Sign, value.Guard);
                bus.Memory[Address(legacy, "VALTYP")] = 0;
                Processor<RecordingBus> cpu = Start(bus, shared ? region : legacy, value.Entry);
                StepUntil(cpu, 3000, ReturnAddress, error);
                cpu.Registers.ProgramCounter.Should().Be(value.Result is null ? error : ReturnAddress, value.Name);
                if (value.Result is { } result)
                {
                    ReadInteger(bus.Memory, legacy).Should().Be(result, value.Name);
                }
            }
        }
    }

    private static void CheckTypeCases(
        AssemblyResult legacy,
        AssemblyResult region,
        bool checkType,
        bool includeLegacy = true)
    {
        (byte Type, byte Sign)[] cases = [(0, 0), (0x80, 0), (0x80, 0x80)];
        foreach (bool shared in includeLegacy ? (bool[])[false, true] : [true])
        {
            foreach ((byte type, byte sign) in cases)
            {
                RecordingBus bus = CreateBus(legacy, region, shared);
                SetFac(bus, legacy, 0, 0, 0, 0, 0, sign, 0);
                bus.Memory[Address(legacy, "VALTYP")] = type;
                Processor<RecordingBus> cpu = Start(bus, shared ? region : legacy, "POSINT");
                ushort functionError = checked((ushort)legacy.Symbol("FCERR"));
                ushort typeError = checked((ushort)legacy.Symbol("ERROR"));
                StepUntil(cpu, 3000, ReturnAddress, functionError, typeError);
                ushort expected = checkType && type != 0 ? typeError : sign != 0 ? functionError : ReturnAddress;
                cpu.Registers.ProgramCounter.Should().Be(expected, $"type ${type:X2}, sign ${sign:X2}");
                if (expected == typeError)
                {
                    cpu.Registers.X.Should().Be((byte)legacy.Symbol("ERRTM"));
                }
                else if (expected == ReturnAddress)
                {
                    ReadInteger(bus.Memory, legacy).Should().Be(0);
                }
            }
        }
    }

    private static void CheckSubscripts(AssemblyResult legacy, AssemblyResult region, BasicDialect dialect)
    {
        (string Text, int? Result, bool TypeError)[] cases =
        [
            ("0", 0, false),
            ("12.75", 12, false),
            ("32767.5", 32767, false),
            ("32768", null, false),
            ("-0.5", null, false),
            ("\"A\"", null, true)
        ];

        foreach (var value in cases)
        {
            foreach (bool shared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, shared);
                byte[] text = dialect.Tokenize(value.Text);
                PrepareText(bus, legacy, text);
                Processor<RecordingBus> cpu = Start(bus, shared ? region : legacy, "INTIDX");
                ushort functionError = checked((ushort)legacy.Symbol("FCERR"));
                ushort typeError = checked((ushort)legacy.Symbol("ERROR"));
                StepUntil(cpu, 10000, ReturnAddress, functionError, typeError);
                ushort expected = value.TypeError ? typeError : value.Result is null ? functionError : ReturnAddress;
                cpu.Registers.ProgramCounter.Should().Be(expected, value.Text);
                if (value.TypeError)
                {
                    cpu.Registers.X.Should().Be((byte)legacy.Symbol("ERRTM"));
                }
                else if (value.Result is { } result)
                {
                    ReadInteger(bus.Memory, legacy).Should().Be(result, value.Text);
                    ReadWord(bus.Memory, Address(legacy, "TXTPTR")).Should().Be(TextAddress + 1 + text.Length);
                }
            }
        }
    }

    private static void CheckSignedExpressions(AssemblyResult legacy, AssemblyResult region, BasicDialect dialect)
    {
        (string Text, int? Result)[] cases =
        [
            ("-0.5", 0xFFFF),
            ("-32767.5", 0x8000),
            ("-32768", null),
            ("32768", null)
        ];

        foreach (var value in cases)
        {
            foreach (bool shared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, shared);
                PrepareText(bus, legacy, dialect.Tokenize(value.Text));
                WriteWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress + 1);
                Processor<RecordingBus> cpu = Start(bus, legacy, "FRMNUM");
                ushort functionError = checked((ushort)legacy.Symbol("FCERR"));
                ushort typeError = checked((ushort)legacy.Symbol("ERROR"));
                StepUntil(cpu, 10000, ReturnAddress, functionError, typeError);
                cpu.Registers.ProgramCounter.Should().Be(ReturnAddress, $"evaluating {value.Text}");

                cpu = Start(bus, shared ? region : legacy, "AYINT");
                StepUntil(cpu, 3000, ReturnAddress, functionError);
                cpu.Registers.ProgramCounter.Should().Be(value.Result is null ? functionError : ReturnAddress, value.Text);
                if (value.Result is { } result)
                {
                    ReadInteger(bus.Memory, legacy).Should().Be(result, value.Text);
                }
            }
        }
    }

    private static AssemblyResult AssembleRegion(
        AssemblyResult legacy,
        bool numericEvaluator,
        bool checkType,
        bool stubEvaluator = false,
        bool insertGap = false)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string evaluator = numericEvaluator ? "FRMNUM" : "FRMEVL";
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.IntegerConversion.asm"
            .org ${legacy.Symbol("N32768"):X4}
                IntegerConversionBoundary
            {(insertGap ? "    .byte $00" : "")}
                IntegerConversion {evaluator}, {(checkType ? 1 : 0)}
            INTEGER_CONVERSION_END:
            """;

        string[] dependencies = ["CHRGET", "FRMNUM", "FRMEVL", "CHKNUM", "FACSGN", "FACEXP", "FCOMP", "FCERR", "QINT"];
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (stubEvaluator)
        {
            symbols["FRMNUM"] = NumericEvaluator;
            symbols["FRMEVL"] = GeneralEvaluator;
            symbols["CHRGET"] = CharacterReader;
        }

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "IntegerConversionTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        if (!insertGap)
        {
            result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
                $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));
        }

        return result;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, string endLabel)
    {
        int start = Address(legacy, "N32768");
        int end = Address(legacy, endLabel);
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, bool shared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (shared)
        {
            int start = Address(region, "N32768");
            int end = Address(region, "INTEGER_CONVERSION_END");
            region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        return bus;
    }

    private static void SetFac(
        RecordingBus bus,
        AssemblyResult legacy,
        byte exponent,
        byte high,
        byte middleHigh,
        byte middle,
        byte low,
        byte sign,
        byte guard)
    {
        bus.Memory[Address(legacy, "FACEXP")] = exponent;
        bus.Memory[Address(legacy, "FACHO")] = high;
        bus.Memory[Address(legacy, "FACMOH")] = middleHigh;
        bus.Memory[Address(legacy, "FACMO")] = middle;
        bus.Memory[Address(legacy, "FACLO")] = low;
        bus.Memory[Address(legacy, "FACSGN")] = sign;
        bus.Memory[Address(legacy, "FACOV")] = guard;
        bus.Memory[Address(legacy, "BITS")] = 0;
    }

    private static void PrepareText(RecordingBus bus, AssemblyResult legacy, byte[] text)
    {
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        bus.Memory[Address(legacy, "JMPER")] = 0x4C;
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)legacy.Symbol("TEMPST");
        bus.Memory[TextAddress] = (byte)'(';
        text.CopyTo(bus.Memory, TextAddress + 1);
        bus.Memory[TextAddress + 1 + text.Length] = (byte)')';
        bus.Memory[TextAddress + 2 + text.Length] = 0;
        WriteWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
    }

    private static void InstallCounter(byte[] memory, int routine, int counter)
    {
        memory[routine] = 0xEE;
        memory[routine + 1] = (byte)counter;
        memory[routine + 2] = (byte)(counter >> 8);
        memory[routine + 3] = 0x60;
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, AssemblyResult source, string entry)
    {
        WriteWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)source.Symbol(entry)),
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

    private static int Address(AssemblyResult source, string name) => checked((int)source.Symbol(name));

    private static int ReadInteger(byte[] memory, AssemblyResult source) =>
        (memory[Address(source, "FACMO")] << 8) | memory[Address(source, "FACLO")];

    private static int ReadWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void WriteWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
