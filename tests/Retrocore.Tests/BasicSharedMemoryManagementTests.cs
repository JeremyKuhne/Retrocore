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
///  Checks shared stack and block management against AppleSoft and the PET BASIC overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedMemoryManagementTests
{
    private const int Apple = 0;
    private const int Pet1 = 1;
    private const int Pet2 = 2;
    private const int Pet4 = 4;

    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");
    private static string PetBasicInputs => Path.Join(Inputs, "Pet", "Basic");

    /// <summary>
    ///  The complete AppleSoft ROM and the promoted labels retain their legacy bytes and addresses.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedMemoryManagement(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleRegion(legacy, 0x36);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("MEMORY_MANAGEMENT_END").Should().Be(legacy.Symbol("OMERR"));
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
    }

    /// <summary>
    ///  Every PET revision matches the complete shared region, including its stack-reserve byte and labels.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedMemoryManagementMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        int reserve = checked((int)(2 * legacy.Symbol("NUMLEV") + 3 * legacy.Symbol("ADDPRC") + 13));
        AssemblyResult native = AssembleRegion(legacy, reserve);
        AssemblyResult composed = AssemblePetWorkspace(legacy, model);
        native.Symbol("MEMORY_MANAGEMENT_END").Should().Be(legacy.Symbol("OMERR"));
        composed.Symbol("MEMORY_MANAGEMENT_END").Should().Be(legacy.Symbol("OMERR"));
        CompareRegion(legacy, native);
        CompareRegion(legacy, composed);
        AssemblyLocation workspace = composed.Definition("HIGHDS").Location
            ?? throw new AssertFailedException("HIGHDS lost its workspace source.");

        workspace.Path.Should().EndWith("Commodore.Equates.asm");
    }

    /// <summary>
    ///  The reserve can be selected independently and changes only GETSTK's immediate operand.
    /// </summary>
    [TestMethod]
    public void StackReserveChangesOnlyItsOperand()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult early = AssembleRegion(legacy, 0x36);
        AssemblyResult later = AssembleRegion(legacy, 0x3E);
        int start = Address(legacy, "FNDFOR");
        int end = Address(legacy, "OMERR");
        int operand = Address(legacy, "GETSTK") + 2;
        byte[] earlyBytes = early.Sections[0].Bytes.ToArray();
        byte[] laterBytes = later.Sections[0].Bytes.ToArray();

        earlyBytes[operand].Should().Be(0x36);
        laterBytes[operand].Should().Be(0x3E);
        Enumerable.Range(start, end - start).Where(address => earlyBytes[address] != laterBytes[address])
            .Should().Equal(operand);
    }

    /// <summary>
    ///  A reserve that cannot be represented in the instruction is rejected.
    /// </summary>
    /// <param name="reserve">The unsupported reserve.</param>
    [TestMethod]
    [DataRow(-1)]
    [DataRow(256)]
    public void InvalidStackReserveIsRejected(int reserve)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult invalid = AssembleRegion(legacy, reserve, expectSuccess: false);
        invalid.Success.Should().BeFalse();
        invalid.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Contain(message => message.Contains("stackReserve"));
    }

    /// <summary>
    ///  The collector-save loop requires contiguous page-zero transfer scratch.
    /// </summary>
    /// <param name="outsidePage">Whether contiguous scratch crosses the end of page zero.</param>
    /// <param name="diagnostic">The expected explanation.</param>
    [TestMethod]
    [DataRow(false, "contiguous")]
    [DataRow(true, "page-zero")]
    public void InvalidTransferScratchIsRejected(bool outsidePage, string diagnostic)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        Dictionary<string, long> changes = new()
        {
            ["HIGHTR"] = legacy.Symbol("HIGHTR") + 1
        };

        if (outsidePage)
        {
            changes["TEMPF1"] = 0xF9;
            changes["HIGHDS"] = 0xFA;
            changes["HIGHTR"] = 0xFC;
            changes["LOWTR"] = 0x101;
            changes["FAC"] = 0x103;
        }

        AssemblyResult invalid = AssembleRegion(legacy, 0x3E, expectSuccess: false, changes: changes);
        invalid.Success.Should().BeFalse();
        invalid.Diagnostics.Select(item => item.Message).Should().Contain(message => message.Contains(diagnostic));
    }

    /// <summary>
    ///  Shared definitions, the AppleSoft invocation and the unchecked entry remain visible to the debugger.
    /// </summary>
    [TestMethod]
    public void SharedEntriesRetainDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = Address(native, "FNDFOR");
        int end = Address(native, "OMERR");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);

        foreach (string name in (string[])["FNDFOR", "BLTU", "BLTUC", "GETSTK", "REASON"])
        {
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.MemoryManagement.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.MemoryManagement.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            if (name == "FNDFOR")
            {
                module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(address);
            }
        }

        foreach (string name in (string[])["FNDFOR", "BLTU", "GETSTK", "REASON"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.MemoryManagement.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        DocumentationTopic transfer = module.Documentation.FindRoutineTopic("BLTUC")
            ?? throw new AssertFailedException("BLTUC lost its entry documentation.");

        transfer.Name.Should().Be(native.DefinitionName("BLTU"));
        transfer.EntryLabels.Should().Contain(native.DefinitionName("BLTUC"));
        DocumentationSection keeps = module.Documentation.FindTopic("FNDFOR")?.Section("Keeps")
            ?? throw new AssertFailedException("FNDFOR lost its Keeps contract.");

        keeps.Items.Should().Contain("Y");
    }

    /// <summary>
    ///  FOR search handles an omitted variable, both pointer-byte mismatches and a non-FOR terminator.
    /// </summary>
    /// <param name="wanted">The initial FORPNT.</param>
    /// <param name="offset">The expected stack offset.</param>
    /// <param name="result">The final FORPNT.</param>
    /// <param name="found">The returned zero flag.</param>
    [TestMethod]
    [DataRow(0x3456, 0x66, 0x3456, true)]
    [DataRow(0x3477, 0x78, 0x3477, false)]
    [DataRow(0x0011, 0x54, 0x2122, true)]
    [DataRow(0x2123, 0x78, 0x2123, false)]
    public void FindForSearchesAndSelectsFrames(int wanted, int offset, int result, bool found)
    {
        AssemblyResult image = EdgeImage(Pet2);
        RecordingBus bus = BusFor(image);
        WriteWord(bus.Memory, Address(image, "FORPNT"), wanted);
        Frame(bus.Memory, 0x54, (byte)image.Symbol("FORTK"), 0x2122);
        Frame(bus.Memory, 0x66, (byte)image.Symbol("FORTK"), 0x3456);
        bus.Memory[0x0101 + 0x78] = 0x00;

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = (ushort)Address(image, "FNDFOR"),
                StackPointer = 0x50,
                Y = 0xA7,
                Status = StatusRegister.Unused
            }
        };

        RunTo(cpu, Address(image, "FFRTS"), 200);
        cpu.Registers.X.Should().Be((byte)offset);
        cpu.Registers.Y.Should().Be(0xA7);
        cpu.Registers.StackPointer.Should().Be(0x50);
        cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(found);
        ReadWord(bus.Memory, Address(image, "FORPNT")).Should().Be(result);
    }

    /// <summary>
    ///  Without a terminating frame, a wrapped search returns zero set even though no variable matched.
    /// </summary>
    [TestMethod]
    public void FindForReportsAStackWrapAsZero()
    {
        AssemblyResult image = EdgeImage(Pet2);
        RecordingBus bus = BusFor(image);
        WriteWord(bus.Memory, Address(image, "FORPNT"), 0x0100);
        int size = Address(image, "FORSIZ");
        for (int offset = 6; offset != 0; offset = (offset + size) & 0xFF)
        {
            bus.Memory[0x0101 + offset] = (byte)image.Symbol("FORTK");
            bus.Memory[0x0103 + offset] = (byte)image.Symbol("FORTK");
        }

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = (ushort)Address(image, "FNDFOR"),
                StackPointer = 2,
                Y = 0xA7,
                Status = StatusRegister.Unused
            }
        };

        RunTo(cpu, Address(image, "FFRTS"), 3000);
        cpu.Registers.X.Should().Be(0);
        cpu.Registers.Y.Should().Be(0xA7);
        cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeTrue();
        ReadWord(bus.Memory, Address(image, "FORPNT")).Should().Be(0x0100);
    }

    /// <summary>
    ///  The unchecked transfer handles empty, overlapping, whole-page and page-crossing blocks.
    /// </summary>
    /// <param name="variant">The workspace and stack-reserve variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void UncheckedTransferCopiesBackwardAcrossPages(int variant)
    {
        AssemblyResult image = EdgeImage(variant);
        (int Source, int Destination, int Length)[] cases =
        [
            (0x3200, 0x3300, 0),
            (0x3201, 0x3202, 1),
            (0x32F0, 0x3320, 0x100),
            (0x32F0, 0x3335, 0x159),
            (0x3202, 0x32FF, 0x101),
            (0x3200, 0x3400, 0x200)
        ];

        foreach ((int source, int destination, int length) in cases)
        {
            RecordingBus bus = BusFor(image);
            FillTransferArea(bus.Memory);
            SetTransferPointers(bus.Memory, image, source, destination, length);
            WriteWord(bus.Memory, Address(image, "STREND"), 0x2877);
            byte[] expected = (byte[])bus.Memory.Clone();
            Array.Copy(expected, source, expected, destination, length);
            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = (ushort)Address(image, "BLTUC"),
                    StackPointer = 0xE0,
                    Status = StatusRegister.Unused
                }
            };

            RunTo(cpu, Address(image, "GETSTK") - 1, 10000);
            bus.Memory.AsSpan(0x3000, 0x800).ToArray()
                .Should().Equal(expected.AsSpan(0x3000, 0x800).ToArray(), $"copying {length} bytes from ${source:X4}");

            ReadWord(bus.Memory, Address(image, "LOWTR")).Should().Be(source);
            ReadWord(bus.Memory, Address(image, "HIGHTR")).Should().Be(source - 0x100);
            ReadWord(bus.Memory, Address(image, "HIGHDS")).Should().Be(destination - 0x100);
            ReadWord(bus.Memory, Address(image, "STREND")).Should().Be(0x2877);
        }
    }

    /// <summary>
    ///  The checked transfer updates STREND only after space is available and does not copy on failure.
    /// </summary>
    /// <param name="variant">The workspace and stack-reserve variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void CheckedTransferRespectsStringSpace(int variant)
    {
        AssemblyResult image = EdgeImage(variant);
        const int source = 0x3200, destination = 0x3208, length = 0x20;
        int end = destination + length;
        foreach (bool enoughSpace in (bool[])[true, false])
        {
            RecordingBus bus = BusFor(image);
            FillTransferArea(bus.Memory);
            SetTransferPointers(bus.Memory, image, source, destination, length);
            WriteWord(bus.Memory, Address(image, "FRETOP"), enoughSpace ? end + 1 : end);
            WriteWord(bus.Memory, Address(image, "STREND"), 0x2877);
            bus.Memory[Address(image, "GARBA2")] = 0x60; // Collector returns without freeing space.
            byte[] expected = (byte[])bus.Memory.Clone();
            if (enoughSpace) { Array.Copy(expected, source, expected, destination, length); }

            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = (ushort)Address(image, "BLTU"),
                    StackPointer = 0xE0,
                    Accumulator = (byte)end,
                    Y = (byte)(end >> 8),
                    Status = StatusRegister.Unused
                }
            };

            int target = Address(image, enoughSpace ? "GETSTK" : "OMERR") - (enoughSpace ? 1 : 0);
            RunTo(cpu, target, 1000);
            bus.Memory.AsSpan(0x3000, 0x800).ToArray().Should().Equal(expected.AsSpan(0x3000, 0x800).ToArray());
            ReadWord(bus.Memory, Address(image, "STREND")).Should().Be(enoughSpace ? end : 0x2877);
        }
    }

    /// <summary>
    ///  GETSTK distinguishes equality, a one-byte shortage, addition overflow and the shifted-out carry.
    /// </summary>
    /// <param name="variant">The workspace and stack-reserve variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void StackCheckUsesTheSelectedReserve(int variant)
    {
        AssemblyResult image = EdgeImage(variant);
        int reserve = variant is Apple or Pet1 ? 0x36 : 0x3E;
        int largest = (255 - reserve) / 2;
        (int Entries, int Stack, bool Error)[] cases =
        [
            (0, reserve - 1, true),
            (0, reserve, false),
            (1, reserve + 1, true),
            (1, reserve + 2, false),
            (largest, 0xFF, false),
            (largest + 1, 0xFF, true),
            (0x80, reserve + 1, false)
        ];

        foreach ((int entries, int stack, bool error) in cases)
        {
            RecordingBus bus = BusFor(image);
            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = (ushort)Address(image, "GETSTK"),
                    StackPointer = (byte)stack,
                    Accumulator = (byte)entries,
                    Y = 0xA5,
                    Status = StatusRegister.Unused | StatusRegister.Carry
                }
            };

            int target = Address(image, error ? "OMERR" : "REASON") - (error ? 0 : 1);
            RunTo(cpu, target, 20);
            cpu.Registers.Y.Should().Be(0xA5);
            cpu.Registers.StackPointer.Should().Be((byte)stack);
        }
    }

    /// <summary>
    ///  REASON skips collection below FRETOP, restores the address and nine scratch bytes, and rejects equality.
    /// </summary>
    /// <param name="variant">The workspace and stack-reserve variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReasonChecksSpaceAndRestoresCollectorScratch(int variant)
    {
        AssemblyResult image = EdgeImage(variant);
        (int Address, int Before, int After, bool Collect, bool Error)[] cases =
        [
            (0x3300, 0x3400, 0x3400, false, false),
            (0x33FE, 0x33FF, 0x33FF, false, false),
            (0x3400, 0x3400, 0x3500, true, false),
            (0x34FF, 0x3400, 0x3500, true, false),
            (0x3501, 0x3400, 0x3501, true, true),
            (0x3501, 0x3400, 0x3500, true, true),
            (0x3500, 0x3400, 0x34FF, true, true)
        ];

        foreach ((int address, int before, int after, bool collect, bool error) in cases)
        {
            RecordingBus bus = BusFor(image);
            int scratch = Address(image, "HIGHDS");
            byte[] original = Enumerable.Range(0, 9).Select(index => (byte)(0x41 + index)).ToArray();
            original.CopyTo(bus.Memory, scratch);
            bus.Memory[scratch - 1] = 0x9A;
            bus.Memory[scratch + 9] = 0x9B;
            WriteWord(bus.Memory, Address(image, "FRETOP"), before);
            int collector = Address(image, "GARBA2");
            bus.Memory[collector] = 0x60;
            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = (ushort)Address(image, "REASON"),
                    StackPointer = 0xE0,
                    Accumulator = (byte)address,
                    X = 0x71,
                    Y = (byte)(address >> 8),
                    Status = StatusRegister.Unused
                }
            };

            int target = Address(image, error ? "OMERR" : "REARTS");
            bool collected = false;
            for (int instruction = 0; instruction < 200 && cpu.Registers.ProgramCounter != target; instruction++)
            {
                if (cpu.Registers.ProgramCounter == collector)
                {
                    collected.Should().BeFalse("the check calls the collector at most once");
                    collected = true;
                    bus.Memory.AsSpan(scratch, 9).Fill(0xE1);
                    bus.Memory[scratch - 1] = 0xD1;
                    bus.Memory[scratch + 9] = 0xD2;
                    WriteWord(bus.Memory, Address(image, "FRETOP"), after);
                    ProcessorRegisters disturbed = cpu.Registers;
                    disturbed.Accumulator = 0x12;
                    disturbed.X = 0x34;
                    disturbed.Y = 0x56;
                    cpu.Registers = disturbed;
                }

                cpu.StepInstruction();
            }

            cpu.Registers.ProgramCounter.Should().Be((ushort)target);
            collected.Should().Be(collect);
            cpu.Registers.StackPointer.Should().Be(0xE0);
            cpu.Registers.Accumulator.Should().Be((byte)address);
            cpu.Registers.Y.Should().Be((byte)(address >> 8));
            bus.Memory.AsSpan(scratch, 9).ToArray().Should().Equal(original);
            bus.Memory[scratch - 1].Should().Be(collect ? (byte)0xD1 : (byte)0x9A);
            bus.Memory[scratch + 9].Should().Be(collect ? (byte)0xD2 : (byte)0x9B);
        }
    }

    private static AssemblyResult EdgeImage(int variant)
    {
        if (variant == Apple)
        {
            return SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        }

        PetModel model = variant switch
        {
            Pet1 => PetModel.Pet2001,
            Pet2 => PetModel.Pet2001Basic2,
            Pet4 => PetModel.Pet4032,
            _ => throw new ArgumentOutOfRangeException(nameof(variant))
        };

        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        int reserve = checked((int)(2 * legacy.Symbol("NUMLEV") + 3 * legacy.Symbol("ADDPRC") + 13));
        return AssembleRegion(legacy, reserve);
    }

    private static AssemblyResult AssembleRegion(
        AssemblyResult legacy,
        int reserve,
        bool expectSuccess = true,
        IReadOnlyDictionary<string, long>? changes = null)
    {
        int start = Address(legacy, "FNDFOR");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Layouts.asm"
            .include "MsBasic.MemoryManagement.asm"
            .org ${start:X4}
                MEMORY_MANAGEMENT {reserve}
            MEMORY_MANAGEMENT_END:
            """;

        // FORSIZ comes from the layouts the source includes.
        string[] dependencies =
        [
            "FORTK", "FORPNT", "HIGHDS", "HIGHTR", "LOWTR", "INDEX", "STREND",
            "FRETOP", "TEMPF1", "FAC", "GARBA2", "OMERR"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (changes is not null)
        {
            foreach ((string name, long value) in changes) { symbols[name] = value; }
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(SharedInputs, "SharedMemoryManagementTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        if (expectSuccess)
        {
            native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
                $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));
        }

        return native;
    }

    private static AssemblyResult AssemblePetWorkspace(AssemblyResult legacy, PetModel model)
    {
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        Dictionary<string, long> symbols = new()
        {
            ["INPUT_BUFFER_PAGE"] = early ? 0 : 2,
            ["INPUT_BUFFER_LENGTH"] = early ? 80 : 81,
            ["NULL_COMMAND"] = early ? 1 : 0,
            ["TERMINAL_FIRST"] = early ? 1 : 0,
            ["FULL_STACK_TOP"] = early ? 1 : 0,
            ["STACK_RESERVE_19"] = early ? 1 : 0,
            ["LOCAL_TERMINAL_POSITION"] = early ? 1 : 0,
            ["LINE_WIDTH_STORAGE"] = disk ? 0 : 1,
            ["DISK_STATUS_STRING"] = disk ? 1 : 0,
            ["VARIABLE_LIST_IN_LINE_NUMBER"] = early ? 1 : 0,
            ["CLOCK_IN_PAGE2"] = early ? 1 : 0,
            ["STATUS_IN_PAGE2"] = early ? 1 : 0,
            ["RND_TIMER_9044"] = early ? 1 : 0,
            ["ERROR_PADDING5"] = early ? 1 : 0,
            ["EXTENDED_DISK_VECTORS"] = disk ? 1 : 0
        };

        // FORSIZ comes from the layouts the workspace includes.
        foreach (string name in (string[])["FORTK", "GARBA2", "OMERR"])
        {
            symbols.Add(name, legacy.Symbol(name));
        }

        string source = $"""
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "MsBasic.MemoryManagement.asm"
            .org ${legacy.Symbol("FNDFOR"):X4}
                MEMORY_MANAGEMENT (2 * STACK_LEVELS + 3 * ADDITIONAL_PRECISION + 13)
            MEMORY_MANAGEMENT_END:
            """;

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(PetBasicInputs, "SharedMemoryWorkspaceTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                IncludePaths = [SharedInputs],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "FNDFOR");
        int end = Address(legacy, "OMERR");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            AssemblySymbol definition = native.Definition(label.Name);
            definition.IsConstant.Should().BeFalse($"{label.Name} must remain a debugger-visible label");
            AssemblyLocation location = definition.Location
                ?? throw new AssertFailedException($"{label.Name} lost its source location.");

            location.Path.Should().EndWith("MsBasic.MemoryManagement.asm");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static RecordingBus BusFor(AssemblyResult image)
    {
        RecordingBus bus = new();
        image.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        return bus;
    }

    private static void RunTo(Processor<RecordingBus> cpu, int target, int limit)
    {
        for (int instruction = 0; instruction < limit && cpu.Registers.ProgramCounter != target; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be((ushort)target);
    }

    private static int Address(AssemblyResult image, string name) => checked((int)image.Symbol(name));

    private static int ReadWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void WriteWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }

    private static void Frame(byte[] memory, int offset, byte marker, int pointer)
    {
        memory[0x0101 + offset] = marker;
        WriteWord(memory, 0x0102 + offset, pointer);
    }

    private static void FillTransferArea(byte[] memory)
    {
        for (int address = 0x3000; address < 0x3800; address++)
        {
            memory[address] = (byte)(address ^ (address >> 3) ^ (address >> 8));
        }
    }

    private static void SetTransferPointers(byte[] memory, AssemblyResult image, int source, int destination, int length)
    {
        WriteWord(memory, Address(image, "LOWTR"), source);
        WriteWord(memory, Address(image, "HIGHTR"), source + length);
        WriteWord(memory, Address(image, "HIGHDS"), destination + length);
    }
}
