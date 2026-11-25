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
using MemoryFeatures = (
    bool RejectNegative,
    bool PreserveAddress,
    bool HighFirst,
    bool GuardRom,
    bool PadGuard,
    bool WaitExtension,
    bool WaitAlias);

namespace Retrocore.Tests;

/// <summary>
///  Checks shared address conversion and memory access against the AppleSoft and PET ROM sources.
/// </summary>
[TestClass]
public sealed class BasicSharedMemoryAccessTests
{
    private const ushort ReturnAddress = 0x4000;
    private const int TextAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;
    private static readonly MemoryFeatures s_apple = (
        RejectNegative: false,
        PreserveAddress: true,
        HighFirst: false,
        GuardRom: false,
        PadGuard: false,
        WaitExtension: false,
        WaitAlias: true);

    /// <summary>
    ///  Each AppleSoft model keeps the complete memory-access region, labels, and address and mask behavior.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedMemoryAccess(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult region = AssembleRegion(legacy, s_apple);
        CompareRegion(legacy, region);
        CompareRegion(legacy, native);
        CheckAddressCases(legacy, region, s_apple);
        CheckPeekCases(legacy, region, s_apple);
        CheckNestedPokePeek(legacy, region, BasicDialect.AppleSoft, s_apple);
        CheckWaitMasks(legacy, region, BasicDialect.AppleSoft);

        AssemblySymbol definition = native.Definition("PEEK");
        definition.Location?.Path.Should().EndWith("MsBasic.MemoryAccess.asm");
    }

    /// <summary>
    ///  Every PET revision matches the shared region, including its sign, PEEK, and WAIT choices.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedMemoryAccessMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        bool early = model == PetModel.Pet2001;
        bool message = model == PetModel.Pet2001Basic2;
        MemoryFeatures features = (
            RejectNegative: true,
            PreserveAddress: !early,
            HighFirst: true,
            GuardRom: early,
            PadGuard: message,
            WaitExtension: message,
            WaitAlias: false);

        BasicDialect dialect = model switch
        {
            PetModel.Pet2001 => BasicDialect.PetBasic1,
            PetModel.Pet2001Basic2 => BasicDialect.PetBasic,
            _ => BasicDialect.PetBasic4
        };

        AssemblyResult region = AssembleRegion(legacy, features);
        CompareRegion(legacy, region);
        CheckAddressCases(legacy, region, features);
        CheckPeekCases(legacy, region, features);
        CheckNestedPokePeek(legacy, region, dialect, features);
        CheckWaitMasks(legacy, region, dialect);
    }

    /// <summary>
    ///  Promoted routines and their AppleSoft invocations remain documented and usable for breakpoints.
    /// </summary>
    [TestMethod]
    public void SharedEntriesRetainDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = Address(native, "GETNUM");
        int end = Address(native, "FADDH");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);

        foreach (string name in (string[])["GETNUM", "PEEK", "POKE", "FNWAIT"])
        {
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.MemoryAccess.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.NumericConversion.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(address);
        }

        foreach (string name in (string[])["GETNUM", "COMBYT", "GETADR", "PEEK", "POKE", "FNWAIT", "WAIT"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            // AppleSoft's own WAIT is an alias of the shared Statements::Wait in its historical names (Basic.md E).
            bool alias = name == "WAIT";
            topic.Kind.Should().Be(alias ? DocumentationKind.Constant : DocumentationKind.Routine);
            topic.Value.Should().Be(native.Symbol(name));
            topic.Path.Should().EndWith(alias ? "AppleSoft.HistoricalNames.asm" : "MsBasic.MemoryAccess.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.MemoryAccess.asm" or "AppleSoft.NumericConversion.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    /// <summary>
    ///  Address preservation, saved-byte order, the ROM guard and its padding can be selected independently.
    /// </summary>
    [TestMethod]
    public void PeekChoicesCanBeCombinedIndependently()
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            Apple2Model.IIeEnhanced);

        foreach (bool highFirst in (bool[])[false, true])
        {
            long unpaddedRead = 0;
            foreach (bool padded in (bool[])[false, true])
            {
                AssemblyResult peek = AssemblePeek(legacy, highFirst, padded);
                if (!padded)
                {
                    unpaddedRead = peek.Symbol("GETCON");
                }
                else
                {
                    peek.Symbol("GETCON").Should().Be(unpaddedRead + 8);
                }

                int start = Address(peek, "PEEK");
                int end = Address(peek, "PEEK_END");
                RecordingBus bus = CreateBus(legacy, peek, start, end);
                SetFac(bus, legacy, 0x8F, 0x80, 0, 0, 0, 0x80);
                int poker = Address(legacy, "POKER");
                SetWord(bus.Memory, poker, 0x5678);
                bus.Memory[0xC000] = 0x5A;
                Processor<RecordingBus> cpu = Start(bus, peek, "PEEK");
                StepUntil(cpu, 100, checked((ushort)legacy.Symbol("GETADR")));
                CheckSavedOrder(cpu, bus, highFirst);
                StepUntil(cpu, 3000, checked((ushort)legacy.Symbol("SNGFLT")));
                cpu.Registers.Y.Should().Be(0, "negative $4000 wraps to guarded address $C000");
                GetWord(bus.Memory, poker).Should().Be(0x5678);
                bus.Accesses.Should().NotContain(access => access.Address == 0xC000 && access.Operation == BusOperation.Read);
            }
        }
    }

    /// <summary>
    ///  BASIC 2's omitted-mask extension writes its message, including the zero-count wrap, but an explicit
    ///  second mask uses the ordinary wait.
    /// </summary>
    [TestMethod]
    public void Basic2WaitExtensionIsOnlyForAnOmittedMask()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        MemoryFeatures features = (
            RejectNegative: true,
            PreserveAddress: true,
            HighFirst: true,
            GuardRom: false,
            PadGuard: true,
            WaitExtension: true,
            WaitAlias: false);

        AssemblyResult region = AssembleRegion(legacy, features);
        byte[] message = [0x0D, 0x09, 0x03, 0x12, 0x0F, 0x13, 0x0F, 0x06, 0x14, 0x21];

        foreach ((int count, int repetitions) in ((int, int)[])[(2, 2), (0, 256)])
        {
            RecordingBus bus = CreateRegionBus(legacy, region);
            PrepareText(bus, legacy, BasicDialect.PetBasic, $"6502,{count}");
            byte[] expected = [.. Enumerable.Range(0, repetitions).SelectMany(_ => message)];
            bus.Memory[0x8000 + expected.Length] = 0xAA;
            Processor<RecordingBus> cpu = Start(bus, region, "FNWAIT");
            StepUntil(cpu, 40000, ReturnAddress);
            bus.Memory.AsSpan(0x8000, expected.Length).ToArray().Should().Equal(expected);
            bus.Memory[0x8000 + expected.Length].Should().Be(0xAA);
            bus.Memory[Address(legacy, "ANDMSK")].Should().Be(0);
        }

        RecordingBus explicitMask = CreateRegionBus(legacy, region);
        PrepareText(explicitMask, legacy, BasicDialect.PetBasic, "6502,1,0");
        explicitMask.Memory[6502] = 1;
        explicitMask.Memory[0x8000] = 0xAA;
        Processor<RecordingBus> ordinary = Start(explicitMask, region, "FNWAIT");
        StepUntil(ordinary, 10000, ReturnAddress);
        explicitMask.Memory[0x8000].Should().Be(0xAA);
        GetWord(explicitMask.Memory, Address(legacy, "POKER")).Should().Be(6502);
        explicitMask.Memory[Address(legacy, "EORMSK")].Should().Be(0);
    }

    private static void CheckAddressCases(AssemblyResult legacy, AssemblyResult region, MemoryFeatures features)
    {
        (string Name, byte Exponent, byte High, byte MiddleHigh, byte Middle, byte Low, byte Sign, int Address)[] cases =
        [
            ("zero", 0x00, 0x55, 0, 0, 0, 0, 0),
            ("one", 0x81, 0x80, 0, 0, 0, 0, 1),
            ("65535 with a fraction", 0x90, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0xFFFF),
            ("65536", 0x91, 0x80, 0, 0, 0, 0, -1),
            ("minus one", 0x81, 0x80, 0, 0, 0, 0x80, 0xFFFF),
            ("minus one half", 0x80, 0x80, 0, 0, 0, 0x80, 0xFFFF),
            ("negative value just above minus 65536", 0x90, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0),
            ("negative zero", 0x00, 0, 0, 0, 0, 0x80, 0)
        ];

        ushort error = checked((ushort)legacy.Symbol("GOFUC"));
        int poker = Address(legacy, "POKER");
        foreach (var value in cases)
        {
            RecordingBus bus = CreateRegionBus(legacy, region);
            SetFac(bus, legacy, value.Exponent, value.High, value.MiddleHigh, value.Middle, value.Low, value.Sign);
            SetWord(bus.Memory, poker, 0x5678);
            Processor<RecordingBus> cpu = Start(bus, region, "GETADR");
            StepUntil(cpu, 3000, ReturnAddress, error);
            bool rejected = value.Address < 0 || (features.RejectNegative && value.Sign != 0);
            cpu.Registers.ProgramCounter.Should().Be(rejected ? error : ReturnAddress, value.Name);
            if (rejected)
            {
                GetWord(bus.Memory, poker).Should().Be(0x5678, value.Name);
                continue;
            }

            GetWord(bus.Memory, poker).Should().Be(value.Address, value.Name);
            cpu.Registers.Accumulator.Should().Be((byte)(value.Address >> 8), value.Name);
            cpu.Registers.Y.Should().Be((byte)value.Address, value.Name);
        }
    }

    private static void CheckPeekCases(AssemblyResult legacy, AssemblyResult region, MemoryFeatures features)
    {
        foreach ((int address, bool guardedPage) in ((int, bool)[])
            [(0xBFFF, false), (0xC000, true), (0xE0FF, true), (0xE100, false)])
        {
            RecordingBus bus = CreateRegionBus(legacy, region);
            SetFac(bus, legacy, 0x90, (byte)(address >> 8), (byte)address, 0, 0, 0);
            int poker = Address(legacy, "POKER");
            SetWord(bus.Memory, poker, 0x5678);
            bus.Memory[address] = 0x5A;
            Processor<RecordingBus> cpu = Start(bus, region, "PEEK");
            StepUntil(cpu, 3000, checked((ushort)legacy.Symbol("SNGFLT")));
            bool blocked = features.GuardRom && guardedPage;
            cpu.Registers.Y.Should().Be(blocked ? (byte)0 : (byte)0x5A);
            GetWord(bus.Memory, poker).Should().Be(features.PreserveAddress ? 0x5678 : address);
            bus.Accesses.Any(access => access.Address == address && access.Operation == BusOperation.Read)
                .Should().Be(!blocked, $"PEEK of ${address:X4} must perform or suppress the read");
        }

        RecordingBus stack = CreateRegionBus(legacy, region);
        SetWord(stack.Memory, Address(legacy, "POKER"), 0x5678);
        Processor<RecordingBus> entry = Start(stack, region, "PEEK");
        StepUntil(entry, 100, checked((ushort)legacy.Symbol("GETADR")));
        if (features.PreserveAddress)
        {
            CheckSavedOrder(entry, stack, features.HighFirst);
        }
        else
        {
            entry.Registers.StackPointer.Should().Be(0xFB);
        }
    }

    private static void CheckSavedOrder(Processor<RecordingBus> cpu, RecordingBus bus, bool highFirst)
    {
        cpu.Registers.StackPointer.Should().Be(0xF9);
        bus.Memory[0x01FD].Should().Be(highFirst ? (byte)0x56 : (byte)0x78);
        bus.Memory[0x01FC].Should().Be(highFirst ? (byte)0x78 : (byte)0x56);
    }

    private static void CheckNestedPokePeek(
        AssemblyResult legacy,
        AssemblyResult region,
        BasicDialect dialect,
        MemoryFeatures features)
    {
        RecordingBus bus = CreateRegionBus(legacy, region);
        PrepareText(bus, legacy, dialect, "1024,PEEK(1025)");
        bus.Memory[1024] = 0xA5;
        bus.Memory[1025] = 77;
        Processor<RecordingBus> cpu = Start(bus, region, "POKE");
        StepUntil(cpu, 10000, ReturnAddress);
        bus.Memory[1024].Should().Be(features.PreserveAddress ? (byte)77 : (byte)0xA5);
        bus.Memory[1025].Should().Be(77);
        int destination = features.PreserveAddress ? 1024 : 1025;
        bus.Accesses.Should().Contain(access =>
            access.Address == destination && access.Operation == BusOperation.Write && access.Value == 77);
    }

    private static void CheckWaitMasks(AssemblyResult legacy, AssemblyResult region, BasicDialect dialect)
    {
        foreach (bool supplied in (bool[])[false, true])
        {
            RecordingBus bus = CreateRegionBus(legacy, region);
            PrepareText(bus, legacy, dialect, supplied ? "1024,1,1" : "1024,1");
            bus.Memory[1024] = supplied ? (byte)1 : (byte)0;
            bus.Memory[Address(legacy, "EORMSK")] = 0xAA;
            int reads = 0;
            bus.ReadCallback = address =>
            {
                if (address == 1024 && ++reads == 1) { bus.Memory[address] = supplied ? (byte)0 : (byte)1; }
            };

            Processor<RecordingBus> cpu = Start(bus, region, "FNWAIT");
            StepUntil(cpu, 10000, ReturnAddress);
            reads.Should().Be(2);
            bus.Memory[Address(legacy, "ANDMSK")].Should().Be(1);
            bus.Memory[Address(legacy, "EORMSK")].Should().Be(supplied ? (byte)1 : (byte)0);
        }

        RecordingBus zeroMask = CreateRegionBus(legacy, region);
        PrepareText(zeroMask, legacy, dialect, "1024,0");
        zeroMask.Memory[1024] = 0xFF;
        Processor<RecordingBus> waiting = Start(zeroMask, region, "FNWAIT");
        ushort loop = checked((ushort)region.Symbol("WAITER"));
        StepUntil(waiting, 10000, loop);
        for (int instruction = 0; instruction < 50; instruction++) { waiting.StepInstruction(); }
        waiting.Registers.ProgramCounter.Should().BeInRange(loop, checked((ushort)(region.Symbol("ZERRTS") - 1)));
        zeroMask.Accesses.Count(access => access.Address == 1024 && access.Operation == BusOperation.Read)
            .Should().BeGreaterThan(1);
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, MemoryFeatures features)
    {
        int start = Address(legacy, "GETNUM");
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string target = features.WaitExtension ? "WAIT_DEFAULT" : "STORDO";
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.MemoryAccess.asm"
            .org ${start:X4}
                AddressConversion {(features.RejectNegative ? 1 : 0)}
                PeekFunction {(features.PreserveAddress ? 1 : 0)}, {(features.HighFirst ? 1 : 0)}, {(features.GuardRom ? 1 : 0)}, {(features.PadGuard ? 1 : 0)}
                PokeStatement
            {(features.WaitAlias ? BasicNames.Label("WAIT") : "")}
                WaitStatement {target}
            MEMORY_ACCESS_END:
            """;

        string[] dependencies =
        [
            "FRMNUM", "CHKCOM", "GETBYT", "FACSGN", "FACEXP", "GOFUC", "QINT", "FACMO", "FACLO",
            "POKER", "ROMLOC", "LASTWR", "SNGFLT", "ANDMSK", "EORMSK", "CHRGOT"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (features.WaitExtension) { symbols.Add(target, legacy.Symbol("ZSTORD")); }
        AssemblyResult result = Assemble(source, folder, symbols);
        result.Symbol("MEMORY_ACCESS_END").Should().Be(legacy.Symbol("FADDH"));
        return result;
    }

    private static AssemblyResult AssemblePeek(AssemblyResult legacy, bool highFirst, bool padded)
    {
        int start = Address(legacy, "PEEK");
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.MemoryAccess.asm"
            .org ${start:X4}
                PeekFunction 1, {(highFirst ? 1 : 0)}, 1, {(padded ? 1 : 0)}
            PEEK_END:
            """;

        Dictionary<string, long> symbols = new(StringComparer.Ordinal)
        {
            ["GETADR"] = legacy.Symbol("GETADR"),
            ["POKER"] = legacy.Symbol("POKER"),
            ["SNGFLT"] = legacy.Symbol("SNGFLT"),
            ["ROMLOC"] = 0xC000,
            ["LASTWR"] = 0xE100
        };

        return Assemble(source, folder, symbols);
    }

    private static AssemblyResult Assemble(string source, string folder, Dictionary<string, long> symbols)
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "MemoryAccessTest.asm")),
            options);

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "GETNUM");
        int end = Address(legacy, "FADDH");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static RecordingBus CreateRegionBus(AssemblyResult legacy, AssemblyResult region) =>
        CreateBus(legacy, region, Address(legacy, "GETNUM"), Address(legacy, "FADDH"));

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, int start, int end)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
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
        byte sign)
    {
        bus.Memory[Address(legacy, "FACEXP")] = exponent;
        bus.Memory[Address(legacy, "FACHO")] = high;
        bus.Memory[Address(legacy, "FACMOH")] = middleHigh;
        bus.Memory[Address(legacy, "FACMO")] = middle;
        bus.Memory[Address(legacy, "FACLO")] = low;
        bus.Memory[Address(legacy, "FACSGN")] = sign;
        bus.Memory[Address(legacy, "FACOV")] = 0;
        bus.Memory[Address(legacy, "BITS")] = 0;
    }

    private static void PrepareText(RecordingBus bus, AssemblyResult legacy, BasicDialect dialect, string text)
    {
        // Startup normally copies CHRGET and installs the writable JMP used by function dispatch.
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        bus.Memory[Address(legacy, "JMPER")] = 0x4C;
        byte[] bytes = dialect.Tokenize(text);
        bytes.CopyTo(bus.Memory, TextAddress);
        bus.Memory[TextAddress + bytes.Length] = 0;
        SetWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, AssemblyResult region, string entry)
    {
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)region.Symbol(entry)),
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
