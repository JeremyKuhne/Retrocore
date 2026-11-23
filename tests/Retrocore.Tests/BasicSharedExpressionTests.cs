// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the shared expression evaluator against the AppleSoft and PET ROM sources.
/// </summary>
[TestClass]
public sealed class BasicSharedExpressionTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  AppleSoft retains its expression code and labels when it uses the shared evaluator.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedExpressionCore(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), model);

        CompareRegion(legacy, AssembleRegion(legacy, carryReturn: false));
        CompareRegion(legacy, native);
        AssemblySymbol definition = native.SymbolDefinitions.Single(symbol => symbol.Name == "FRMEVL");
        definition.Location?.Path.Should().EndWith("MsBasic.ExpressionCore.asm");
    }

    /// <summary>
    ///  Every PET revision uses the same evaluator with its historical PUSHF page-carry behavior.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedExpressionCoreMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), model, original);
        AssemblyResult native = AssembleRegion(legacy, model == PetModel.Pet4032);
        native.Symbols["EXPRESSION_END"].Should().Be(legacy.Symbols["EVAL"]);
        CompareRegion(legacy, native);
    }

    /// <summary>
    ///  The evaluator's shared definition and AppleSoft invocation both retain debugger locations.
    /// </summary>
    [TestMethod]
    public void ExpressionCoreRetainsDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), Apple2Model.IIeEnhanced);
        ushort start = checked((ushort)native.Symbols["FRMEVL"]);
        int length = checked((int)(native.Symbols["EVAL"] - start));
        DebugTestMemory memory = new();
        memory.Set(start, native.Sections[0].Bytes.Slice(start, length).ToArray());
        SourceMapModule module = new(native, area: null);
        DebugPosition position = module.Position(memory, start)
            ?? throw new AssertFailedException("FRMEVL has no debugger source position.");

        position.Chain.Should().HaveCount(2);
        position.Chain[0].Path.Should().EndWith("MsBasic.ExpressionCore.asm");
        position.Chain[1].Path.Should().EndWith("AppleSoft.Expressions.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(start);
        module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(start);

        foreach (string name in (string[])["FRMEVL", "PUSHF", "FORPSH"])
        {
            DocumentationTopic topic = module.Documentation.Find(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.ExpressionCore.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }
    }

    /// <summary>
    ///  Earlier PUSHF entries increment only the low return byte; BASIC 4 carries into the high byte.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="returnLow">The low byte of the JSR return address on the stack.</param>
    /// <param name="expectedHigh">The high byte of the continuation.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0xFF, 0x30)]
    [DataRow(PetModel.Pet2001Basic2, 0xFF, 0x30)]
    [DataRow(PetModel.Pet4032, 0xFF, 0x31)]
    [DataRow(PetModel.Pet4032, 0xFE, 0x30)]
    public void PushfPreservesEachVersionsReturnAddressBehavior(PetModel model, int returnLow, int expectedHigh)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), model);
        AssemblyResult native = AssembleRegion(legacy, model == PetModel.Pet4032);
        int index = checked((int)native.Symbols["INDEX1"]);
        ushort continueAt = checked((ushort)native.Symbols["FORPSH"]);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[0x01FE] = (byte)returnLow;
        bus.Memory[0x01FF] = 0x30;

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbols["PUSHF"]),
                StackPointer = 0xFD,
                Accumulator = 0x5A,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 16 && cpu.Registers.ProgramCounter != continueAt; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(continueAt);
        bus.Memory[index].Should().Be((byte)(returnLow + 1));
        bus.Memory[index + 1].Should().Be((byte)expectedHigh);
        cpu.Registers.StackPointer.Should().Be(0xFE);
        bus.Memory[0x01FF].Should().Be(0x5A, "the sign must remain on the stack");
    }

    /// <summary>
    ///  A true relation produces one in AppleSoft and minus one in PET BASIC; a false relation produces zero.
    /// </summary>
    /// <param name="apple">Whether to use AppleSoft's result convention.</param>
    /// <param name="equal">Whether the mask accepts an equal comparison.</param>
    [TestMethod]
    [DataRow(true, true)]
    [DataRow(true, false)]
    [DataRow(false, true)]
    [DataRow(false, false)]
    public void RelationalResultUsesTheVariantsTrueValue(bool apple, bool equal)
    {
        AssemblyResult legacy = apple
            ? SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10), Apple2Model.IIeEnhanced)
            : PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001Basic2);

        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Relational.asm"
            .org ${legacy.Symbols["DOREL"]:X4}
                RELATIONAL_OPERATORS {(apple ? "$01" : "$FF")}
            RELATIONAL_END:
            """;

        string[] dependencies =
        [
            "CHKVAL", "ARGSGN", "ARGHO", "ARGEXP", "FCOMP", "VALTYP", "OPMASK", "FREFAC",
            "DSCTMP", "ARGMO", "ARGLO", "FRETMP", "FACSGN", "DOMASK", "FLOAT"
        ];

        Dictionary<string, long> symbols = [];
        foreach (string name in dependencies)
        {
            symbols.Add(name, legacy.Symbols[name]);
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "RelationalTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = symbols
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        int start = checked((int)legacy.Symbols["DOREL"]);
        int end = checked((int)legacy.Symbols[apple ? "PDL" : "DIM3"]);
        native.Symbols["RELATIONAL_END"].Should().Be(end);
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());

        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbols["DOMASK"])] = equal ? (byte)2 : (byte)1;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbols["DOCMP"]),
                X = 0,
                Status = StatusRegister.Unused
            }
        };

        ushort destination = checked((ushort)native.Symbols["FLOAT"]);
        for (int instruction = 0; instruction < 20 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
        cpu.Registers.Accumulator.Should().Be(equal ? (apple ? (byte)1 : (byte)255) : (byte)0);
    }

    /// <summary>
    ///  PET logical operations combine both bytes of their signed integer operands.
    /// </summary>
    /// <param name="or">Whether to execute OR rather than AND.</param>
    /// <param name="expected">The resulting 16-bit value.</param>
    [TestMethod]
    [DataRow(true, 0xAFFA)]
    [DataRow(false, 0x0550)]
    public void PetLogicalOperatorsCombineBothIntegerBytes(bool or, int expected)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleLogicalOperators(legacy, bitwise: true);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        byte high = checked((byte)native.Symbols["FACMO"]);
        byte low = checked((byte)native.Symbols["FACLO"]);
        bus.Memory[high] = 0xA5;
        bus.Memory[low] = 0x5A;
        bus.Memory[checked((int)native.Symbols["AYINT"])] = 0x60;
        byte[] moveArgument = [0xA9, 0x0F, 0x85, high, 0xA9, 0xF0, 0x85, low, 0x60];
        moveArgument.CopyTo(bus.Memory, checked((int)native.Symbols["MOVFA"]));

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbols[or ? "OROP" : "ANDOP"]),
                StackPointer = 0xFF,
                Status = StatusRegister.Unused
            }
        };

        ushort destination = checked((ushort)native.Symbols["GIVAYF"]);
        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
        cpu.Registers.Accumulator.Should().Be((byte)(expected >> 8));
        cpu.Registers.Y.Should().Be((byte)(expected & 0xFF));
    }

    /// <summary>
    ///  AppleSoft logical operations return Boolean zero or one instead of PET bitwise results.
    /// </summary>
    /// <param name="or">Whether to execute OR rather than AND.</param>
    /// <param name="argumentNonzero">Whether the argument is nonzero.</param>
    /// <param name="expected">The Boolean result.</param>
    [TestMethod]
    [DataRow(true, false, 1)]
    [DataRow(false, false, 0)]
    [DataRow(false, true, 1)]
    public void AppleSoftLogicalOperatorsReturnBooleans(bool or, bool argumentNonzero, int expected)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10), Apple2Model.IIeEnhanced);

        AssemblyResult native = AssembleLogicalOperators(legacy, bitwise: false);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbols["ARGEXP"])] = argumentNonzero ? (byte)0x81 : (byte)0;
        bus.Memory[checked((int)native.Symbols["FACEXP"])] = 0x81;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbols[or ? "OROP" : "OROP1"]),
                Status = StatusRegister.Unused
            }
        };

        ushort destination = checked((ushort)native.Symbols["SNGFLT"]);
        for (int instruction = 0; instruction < 20 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
        cpu.Registers.Y.Should().Be((byte)expected);
    }

    private static AssemblyResult AssembleLogicalOperators(AssemblyResult legacy, bool bitwise)
    {
        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.OperandEvaluation.asm"
            .org ${legacy.Symbols["OROP"]:X4}
                LOGICAL_OPERATORS {(bitwise ? 1 : 0)}
            """;

        string[] dependencies = bitwise
            ? ["COUNT", "AYINT", "FACMO", "INTEGR", "FACLO", "MOVFA", "GIVAYF"]
            : ["ARGEXP", "FACEXP", "SNGFLT"];

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = dependencies.ToDictionary(
                name => name, name => legacy.Symbols[name], StringComparer.Ordinal)
        };

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "LogicalOperatorsTest.asm")), options);

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, bool carryReturn)
    {
        int start = checked((int)legacy.Symbols["FRMEVL"]);
        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.ExpressionCore.asm"
            .org ${start:X4}
                EXPRESSION_CORE {(carryReturn ? 1 : 0)}
            EXPRESSION_END:
            """;

        string[] dependencies =
        [
            "TXTPTR", "GETSTK", "EVAL", "OPMASK", "CHRGOT", "GREATK", "PLUSTK", "VALTYP", "CAT",
            "INDEX1", "OPTAB", "CHKNUM", "OPPTR", "PTDORL", "CHRGET", "SNERR", "FACSGN", "ROUND",
            "FACLO", "FACMO", "FACMOH", "FACHO", "FACEXP", "DOMASK", "ARGEXP", "ARGHO", "ARGMOH",
            "ARGMO", "ARGLO", "ARGSGN", "ARISGN"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbols[name], StringComparer.Ordinal);

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = symbols
        };

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "ExpressionCoreTest.asm")),
            options);

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbols["FRMEVL"]);
        int end = checked((int)legacy.Symbols["EVAL"]);
        IEnumerable<AssemblySymbol> labels = legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end);

        foreach (AssemblySymbol label in labels)
        {
            native.Symbols.Should().ContainKey(label.Name);
            native.Symbols[label.Name].Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }
}
