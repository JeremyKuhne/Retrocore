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
///  Checks shared program-transfer entries.
/// </summary>
[TestClass]
public sealed class BasicSharedProgramTransfersTests
{
    private const int ReturnAddress = 0x4000;
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  AppleSoft retains its program-transfer bytes and labels, including POP.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedTransfers(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, apple: true, searchLow: true);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("TRANSFER_END").Should().Be(legacy.Symbol("DATA"));
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
    }

    /// <summary>
    ///  Every PET revision retains its transfer code and its RETURN pointer choice.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedTransfersMatchPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy, apple: false, searchLow: model == PetModel.Pet2001);
        CompareRegion(legacy, native);
        native.Symbol("TRANSFER_END").Should().Be(legacy.Symbol("DATA"));
    }

    /// <summary>
    ///  GOTO finds both a later and an earlier line, updating the text pointer to its link field.
    /// </summary>
    /// <param name="forward">Whether the destination follows the current line.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void GotoSearchesInBothDirections(bool forward)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleShared(legacy, apple: false, searchLow: false);
        RecordingBus bus = CreateBus(legacy, native);
        byte[] program = forward
            ? [0x08, 0x20, 10, 0, (byte)'3', (byte)'0', (byte)'0', 0, 0x0E, 0x20, 0x2C, 1, (byte)'B', 0, 0, 0]
            : [0x06, 0x20, 10, 0, (byte)'A', 0, 0x0D, 0x20, 0x2C, 1, (byte)'1', (byte)'0', 0, 0, 0];

        program.CopyTo(bus.Memory, 0x2000);
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        SetWord(bus.Memory, Address(native, "TXTTAB"), 0x2000);
        SetWord(bus.Memory, Address(native, "CURLIN"), forward ? 10 : 300);
        SetWord(bus.Memory, Address(native, "TXTPTR"), forward ? 0x2004 : 0x200A);
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("GOTO")),
                Accumulator = (byte)(forward ? '3' : '1'),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        StepTo(cpu, ReturnAddress);
        GetWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(forward ? 0x2007 : 0x1FFF);
    }

    /// <summary>
    ///  RETURN restores the GOSUB frame and skips its target while selecting the configured FOR-pointer byte.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void ReturnRestoresTheCaller(PetModel model)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        bool searchLow = model == PetModel.Pet2001;
        AssemblyResult native = AssembleShared(legacy, apple: false, searchLow);
        RecordingBus bus = CreateBus(legacy, native);
        SetWord(bus.Memory, Address(native, "FORPNT"), 0x3412);
        PrepareReturnFrame(bus.Memory, native);
        Processor<RecordingBus> cpu = StartReturn(bus, native, y: 0);

        StepTo(cpu, ReturnAddress);
        GetWord(bus.Memory, Address(native, "FORPNT")).Should().Be(searchLow ? 0x34FF : 0xFF12);
        GetWord(bus.Memory, Address(native, "CURLIN")).Should().Be(0x012A);
        GetWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(0x3003);
    }

    /// <summary>
    ///  RETURN without a GOSUB frame reaches the error handler with the correct error offset.
    /// </summary>
    [TestMethod]
    public void ReturnWithoutGosubReportsAnError()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleShared(legacy, apple: false, searchLow: false);
        RecordingBus bus = CreateBus(legacy, native);
        bus.Memory[0x01F3] = 0;
        Processor<RecordingBus> cpu = StartReturn(bus, native, y: 0);

        StepTo(cpu, Address(native, "ERROR"));
        cpu.Registers.X.Should().Be((byte)native.Symbol("ERRRG"));
    }

    /// <summary>
    ///  The earlier low-byte check can mistake a matching FOR frame for a missing GOSUB.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="error">Whether the earlier search reaches the error handler.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    public void ReturnRetainsTheEarlierForPointerQuirk(PetModel model, bool error)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        AssemblyResult native = AssembleShared(legacy, apple: false, searchLow: error);
        RecordingBus bus = CreateBus(legacy, native);
        const byte stack = 0xC0;
        int frame = 0x0100 + stack + 3;
        bus.Memory[frame] = checked((byte)legacy.Symbol("FORTK"));
        SetWord(bus.Memory, frame + 1, 0x22FF);
        int gosub = frame + Address(legacy, "FORSIZ");
        bus.Memory[gosub] = checked((byte)legacy.Symbol("GOSUTK"));
        SetWord(bus.Memory, gosub + 1, 0x012A);
        SetWord(bus.Memory, gosub + 3, 0x3000);
        SetWord(bus.Memory, gosub + 5, ReturnAddress - 1);
        byte[] text = [(byte)'3', (byte)'0', (byte)'0', (byte)':', 0];
        text.CopyTo(bus.Memory, 0x3000);
        SetWord(bus.Memory, Address(native, "FORPNT"), 0x2212);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("RETURN")),
                StackPointer = stack,
                Status = StatusRegister.Unused | StatusRegister.Zero
            }
        };

        StepTo(cpu, error ? Address(native, "ERROR") : ReturnAddress);
        if (error)
        {
            cpu.Registers.X.Should().Be((byte)native.Symbol("ERRRG"));
        }
        else
        {
            GetWord(bus.Memory, Address(native, "CURLIN")).Should().Be(0x012A);
            GetWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(0x3003);
        }
    }

    /// <summary>
    ///  The early STOP detects direct execution from the text page, while later versions check the line number.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="savesPosition">Whether the contradictory state is treated as program execution.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001Basic2, true)]
    [DataRow(PetModel.Pet4032, true)]
    public void StopRetainsTheDirectModeCheck(PetModel model, bool savesPosition)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.ProgramTransfers.asm"
            .org ${legacy.Symbol("RESTOR"):X4}
                RestoreStatement
                StopAndContinue {(early ? 0 : 1)}, {(disk ? 0 : 1)}
            """;

        string[] dependencies =
        [
            "TXTTAB", "DATPTR", "TXTPTR", "CURLIN", "OLDTXT", "OLDLIN",
            "BRKTXT", "ERRFIN", "READY", "ERRCN", "ERROR"
        ];

        Dictionary<string, long> symbols = [];
        foreach (string name in dependencies) { symbols.Add(name, legacy.Symbol(name)); }
        if (!disk) { symbols.Add("CNTWFL", legacy.Symbol("CNTWFL")); }
        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "SharedStopTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        SetWord(bus.Memory, Address(native, "TXTPTR"), 0x00F0);
        SetWord(bus.Memory, Address(native, "CURLIN"), 0x1234);
        SetWord(bus.Memory, Address(native, "OLDTXT"), 0x7777);
        SetWord(bus.Memory, Address(native, "OLDLIN"), 0x5555);
        if (!disk) { bus.Memory[Address(native, "CNTWFL")] = 0x80; }
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("STOP")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused | StatusRegister.Carry | StatusRegister.Zero
            }
        };

        StepTo(cpu, Address(native, "ERRFIN"));
        GetWord(bus.Memory, Address(native, "OLDTXT")).Should().Be(savesPosition ? 0x00F0 : 0x7777);
        GetWord(bus.Memory, Address(native, "OLDLIN")).Should().Be(savesPosition ? 0x1234 : 0x5555);
        if (!disk) { bus.Memory[Address(native, "CNTWFL")].Should().Be(0); }
    }

    /// <summary>
    ///  AppleSoft POP discards the frame without restoring its saved line or text pointer.
    /// </summary>
    [TestMethod]
    public void PopDiscardsTheFrameWithoutTransferring()
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            Apple2Model.IIeEnhanced);

        AssemblyResult native = AssembleShared(legacy, apple: true, searchLow: true);
        RecordingBus bus = CreateBus(legacy, native);
        PrepareReturnFrame(bus.Memory, native);
        SetWord(bus.Memory, Address(native, "CURLIN"), 0x1234);
        SetWord(bus.Memory, Address(native, "TXTPTR"), 0x5678);
        byte pop = checked((byte)((native.Symbol("POPTK") - native.Symbol("ENDTK")) * 2));
        Processor<RecordingBus> cpu = StartReturn(bus, native, pop);

        StepTo(cpu, ReturnAddress);
        GetWord(bus.Memory, Address(native, "CURLIN")).Should().Be(0x1234);
        GetWord(bus.Memory, Address(native, "TXTPTR")).Should().Be(0x5678);
    }

    /// <summary>
    ///  Shared transfer entries retain their documentation and breakpoint-capable source lines.
    /// </summary>
    [TestMethod]
    public void TransfersRetainDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = Address(native, "RUN");
        int end = Address(native, "DATA");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["RUN", "GOSUB", "GOTO", "RETURN"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.ProgramTransfers.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.ProgramTransfers.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.ControlFlow.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy, bool apple, bool searchLow)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.ProgramTransfers.asm"
            .org ${legacy.Symbol("RUN"):X4}
                RunStatement
                GosubAndGoto {(apple ? "NXTCO1" : "NEWSTT")}
            {(apple ? BasicNames.Label("POP") : "")}
                ReturnStatement {(searchLow ? 1 : 0)}, {(apple ? 1 : 0)}
            TRANSFER_END:
            """;

        string[] dependencies =
        [
            "RUNC", "CLEARC", "GETSTK", "TXTPTR", "CURLIN", "GOSUTK", "CHRGOT", "LINGET",
            "REMN", "LINNUM", "TXTTAB", "FNDLNC", "LOWTR", "FORPNT", "FNDFOR", "ERRRG",
            "ERRUS", "ERROR", "SNERR"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (apple)
        {
            foreach (string name in (string[])["NXTCO1", "POPTK", "ENDTK", "REMER1"])
            {
                symbols.Add(name, legacy.Symbol(name));
            }
        }
        else
        {
            symbols.Add("NEWSTT", legacy.Symbol("NEWSTT"));
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "SharedTransfersTest.asm")),
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
        int start = Address(legacy, "RUN");
        int end = Address(legacy, "DATA");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            // A vendor's alias reaches its name only in the vendor's whole build, which this compares too.
            if (BasicNames.IsVendorName(label.Name) && !native.SymbolsWithHistoricalNames.ContainsKey(label.Name))
            {
                continue;
            }

            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult native)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int start = Address(legacy, "RUN");
        int end = Address(legacy, "DATA");
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        return bus;
    }

    private static void PrepareReturnFrame(byte[] memory, AssemblyResult native)
    {
        memory[0x01F3] = checked((byte)native.Symbol("GOSUTK"));
        SetWord(memory, 0x01F4, 0x012A);
        SetWord(memory, 0x01F6, 0x3000);
        SetWord(memory, 0x01F8, ReturnAddress - 1);
        byte[] text = [(byte)'3', (byte)'0', (byte)'0', (byte)':', (byte)'X', 0];
        text.CopyTo(memory, 0x3000);
    }

    private static Processor<RecordingBus> StartReturn(RecordingBus bus, AssemblyResult native, byte y) => new(bus)
    {
        Registers = new()
        {
            ProgramCounter = checked((ushort)native.Symbol("RETURN")),
            StackPointer = 0xF0,
            Y = y,
            Status = StatusRegister.Unused | StatusRegister.Zero
        }
    };

    private static void StepTo(Processor<RecordingBus> cpu, int address)
    {
        for (int instruction = 0; instruction < 1000 && cpu.Registers.ProgramCounter != address; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be((ushort)address);
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));
    private static int GetWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void SetWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
