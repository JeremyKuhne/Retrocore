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

namespace Retrocore.Tests;

/// <summary>
///  Checks shared concatenation, string moves and release against the AppleSoft and PET overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedStringConcatenationTests
{
    private const int Apple = 0;
    private const int Pet1 = 1;
    private const int Pet2 = 2;
    private const int Pet4 = 4;
    private const ushort ReturnAddress = 0x2000;
    private const int TextAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  Each AppleSoft model emits the complete region and keeps the full legacy image and labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftConcatenationMatchesLegacy(Apple2Model model)
    {
        AssemblyResult legacy = AppleLegacy(model);
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleRegion(legacy, linkedRelease: false);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        AssertSpan(standalone, Address(legacy, "CAT"), Address(legacy, "CHR"));
        standalone.Symbol("STRING_CONCATENATION_END").Should().Be(legacy.Symbol("CHR"));
        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
    }

    /// <summary>
    ///  Every PET revision matches the complete standalone span and the actual PET workspace.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetConcatenationMatchesOverlay(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        bool linked = model == PetModel.Pet4032;
        foreach (AssemblyResult region in (AssemblyResult[])
            [
                AssembleRegion(legacy, linked),
                AssemblePetWorkspace(legacy, model)
            ])
        {
            CompareRegion(legacy, region);
            AssertSpan(region, Address(legacy, "CAT"), Address(legacy, "CHR"));
            region.Symbol("STRING_CONCATENATION_END").Should().Be(legacy.Symbol("CHR"));
        }
    }

    /// <summary>
    ///  Concatenation handles empty and maximum strings, temporary operands and both error paths.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="original">Whether the original PET chip is used.</param>
    [TestMethod]
    [DataRow(Apple, false)]
    [DataRow(Pet1, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void ConcatenationEvaluatesStringsAndErrors(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        AssemblyResult region = AssembleRegion(legacy, linkedRelease: variant == Pet4);
        BasicDialect dialect = variant switch
        {
            Apple => BasicDialect.AppleSoft,
            Pet1 => BasicDialect.PetBasic1,
            Pet2 => BasicDialect.PetBasic,
            _ => BasicDialect.PetBasic4
        };

        (string Expression, string? Result, string? Error)[] cases =
        [
            ("\"HEL\"+\"LO\"", "HELLO", null),
            ("\"\"+\"\"", "", null),
            ("\"\"+\"A\"", "A", null),
            ("CHR$(65)+\"BC\"+CHR$(68)", "ABCD", null),
            ($"\"{new string('A', 255)}\"+\"\"", new string('A', 255), null),
            ($"\"{new string('A', 128)}\"+\"{new string('B', 128)}\"", null, "ERRLS"),
            ("\"A\"+1", null, "ERRTM")
        ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                PrepareRuntime(bus, legacy);
                dialect.Tokenize(test.Expression).CopyTo(bus.Memory, TextAddress);
                SetWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
                Processor<RecordingBus> cpu = Start(bus, Address(legacy, "FRMEVL"));
                ushort error = checked((ushort)legacy.Symbol("ERROR"));
                RunTo(cpu, 50000, ReturnAddress, error);
                cpu.Registers.ProgramCounter.Should().Be(
                    test.Error is null ? ReturnAddress : error,
                    $"{test.Expression} with {(useShared ? "shared" : "legacy")} code");

                if (test.Error is not null)
                {
                    cpu.Registers.X.Should().Be((byte)legacy.Symbol(test.Error));
                    continue;
                }

                string text = test.Result ?? throw new AssertFailedException("A result is required.");
                int temp = Address(legacy, "TEMPST");
                int descriptor = GetWord(bus.Memory, Address(legacy, "FACMO"));
                descriptor.Should().Be(temp);
                bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(temp + 3));
                GetWord(bus.Memory, Address(legacy, "LASTPT")).Should().Be(temp);
                bus.Memory[Address(legacy, "VALTYP")].Should().Be(0xFF);
                bus.Memory[descriptor].Should().Be((byte)text.Length);
                int characters = GetWord(bus.Memory, descriptor + 1);
                bus.Memory.AsSpan(characters, text.Length).ToArray().Should().Equal(Encoding.ASCII.GetBytes(text));
            }
        }
    }

    /// <summary>
    ///  String moves copy backward, including overlapping and cross-page ranges, and preserve X.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="original">Whether the original PET chip is used.</param>
    [TestMethod]
    [DataRow(Apple, false)]
    [DataRow(Pet1, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void StringMovesHandleEmptyOverlapAndPageCrossings(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        AssemblyResult region = AssembleRegion(legacy, linkedRelease: variant == Pet4);
        (int Source, int Destination, int Length)[] cases =
        [
            (0x60FE, 0x6100, 5),
            (0x62FE, 0x64FD, 4),
            (0x6100, 0x6202, 255),
            (0x6200, 0x64FE, 0)
        ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                byte[] characters = [.. Enumerable.Range(0, test.Length).Select(i => (byte)(i ^ 0xA5))];
                characters.CopyTo(bus.Memory, test.Source);
                SetWord(bus.Memory, Address(legacy, "FRESPC"), test.Destination);
                Processor<RecordingBus> cpu = Start(
                    bus, Address(useShared ? region : legacy, "MOVSTR"),
                    (byte)test.Length, (byte)test.Source, (byte)(test.Source >> 8));

                RunTo(cpu, 5000, ReturnAddress);
                bus.Memory.AsSpan(test.Destination, test.Length).ToArray().Should().Equal(characters);
                GetWord(bus.Memory, Address(legacy, "INDEX")).Should().Be(test.Source);
                GetWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(test.Destination + test.Length);
                cpu.Registers.X.Should().Be((byte)test.Source);
                cpu.Registers.Y.Should().Be(0);
                cpu.Registers.Accumulator.Should().Be((byte)(test.Destination + test.Length));
                if (test.Length == 0)
                {
                    bus.Accesses.Should().NotContain(access => access.Address == test.Source && access.Operation == BusOperation.Read);
                    bus.Accesses.Should().NotContain(access => access.Address == test.Destination && access.Operation == BusOperation.Write);
                }
            }
        }
    }

    /// <summary>
    ///  The descriptor stack is popped only when both address bytes match the latest temporary.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="original">Whether the original PET chip is used.</param>
    [TestMethod]
    [DataRow(Apple, false)]
    [DataRow(Pet1, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void TemporaryStackRequiresTheCompleteDescriptorAddress(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        AssemblyResult region = AssembleRegion(legacy, linkedRelease: variant == Pet4);
        int last = Address(legacy, "TEMPST") + 3;
        foreach (int lastAddress in (int[])[last, last + 0x1200])
        {
            foreach (int descriptor in (int[])[lastAddress, lastAddress - 3, lastAddress + 0x100])
            {
                foreach (bool useShared in (bool[])[false, true])
                {
                    RecordingBus bus = CreateBus(legacy, region, useShared);
                    bus.Memory[Address(legacy, "TEMPPT")] = (byte)(last + 3);
                    SetWord(bus.Memory, Address(legacy, "LASTPT"), lastAddress);
                    Processor<RecordingBus> cpu = Start(
                        bus, Address(useShared ? region : legacy, "FRETMS"),
                        (byte)descriptor, 0xA7, (byte)(descriptor >> 8),
                        StatusRegister.Unused | StatusRegister.Zero | StatusRegister.Carry);

                    RunTo(cpu, 100, ReturnAddress);
                    bool matched = descriptor == lastAddress;
                    cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(matched);
                    cpu.Registers.X.Should().Be(0xA7);
                    bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(matched ? last : last + 3));
                    GetWord(bus.Memory, Address(legacy, "LASTPT")).Should().Be(matched ? lastAddress - 3 : lastAddress);
                }
            }
        }
    }

    /// <summary>
    ///  FRESTR checks the FAC type, while FREFAC releases the descriptor without a type check.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="original">Whether the original PET chip is used.</param>
    [TestMethod]
    [DataRow(Apple, false)]
    [DataRow(Pet1, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void FacReleaseChecksTheTypeOnlyAtFrestr(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        bool linked = variant == Pet4;
        AssemblyResult region = AssembleRegion(legacy, linked);
        foreach (bool checkType in (bool[])[false, true])
        {
            foreach (bool stringType in (bool[])[false, true])
            {
                foreach (bool useShared in (bool[])[false, true])
                {
                    RecordingBus bus = CreateBus(legacy, region, useShared);
                    const int characters = 0x70FC;
                    int temp = Address(legacy, "TEMPST");
                    bus.Memory[Address(legacy, "TEMPPT")] = (byte)(temp + 3);
                    SetWord(bus.Memory, Address(legacy, "LASTPT"), temp);
                    SetWord(bus.Memory, Address(legacy, "FRETOP"), characters);
                    SetDescriptor(bus.Memory, temp, 2, characters);
                    SetWord(bus.Memory, Address(legacy, "FACMO"), temp);
                    bus.Memory[Address(legacy, "VALTYP")] = stringType ? (byte)0xFF : (byte)0;
                    string entry = checkType ? "FRESTR" : "FREFAC";
                    Processor<RecordingBus> cpu = Start(bus, Address(useShared ? region : legacy, entry));
                    ushort error = checked((ushort)legacy.Symbol("ERROR"));
                    RunTo(cpu, 500, ReturnAddress, error);
                    bool rejected = checkType && !stringType;
                    cpu.Registers.ProgramCounter.Should().Be(rejected ? error : ReturnAddress);
                    if (rejected) { cpu.Registers.X.Should().Be((byte)legacy.Symbol("ERRTM")); }
                    GetWord(bus.Memory, Address(legacy, "FRETOP"))
                        .Should().Be(characters + (rejected ? 0 : 2 + (linked ? 2 : 0)));

                    bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(rejected ? temp + 3 : temp));
                    if (!rejected)
                    {
                        cpu.Registers.Accumulator.Should().Be(2);
                        GetWord(bus.Memory, Address(legacy, "INDEX")).Should().Be(characters);
                    }
                }
            }
        }
    }

    /// <summary>
    ///  Release preserves literals and nonlatest descriptors, and handles linked heap records and carries.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="original">Whether the original PET chip is used.</param>
    [TestMethod]
    [DataRow(Apple, false)]
    [DataRow(Pet1, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void ReleaseDistinguishesHeapRecordsAndLiterals(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        bool linked = variant == Pet4;
        AssemblyResult region = AssembleRegion(legacy, linked);
        (int Characters, int Free, byte Length, bool Latest)[] cases =
        [
            (0x70FD, 0x70FD, 3, true),
            (0x70FD, 0x70FD, 1, true),
            (0x70FE, 0x70FE, 1, true),
            (0x70F0, 0x7000, 3, true),
            (0x7101, 0x70F0, 2, true),
            (0x70FD, 0x70FD, 3, false),
            (0x6030, 0x7000, 3, true),
            (0x70FF, 0x70FF, 0, true),
            (0x9000, 0x7000, 2, true)
        ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                int last = Address(legacy, "TEMPST") + 3;
                int descriptor = test.Latest ? last : last - 3;
                bus.Memory[Address(legacy, "TEMPPT")] = (byte)(last + 3);
                SetWord(bus.Memory, Address(legacy, "LASTPT"), last);
                SetWord(bus.Memory, Address(legacy, "FRETOP"), test.Free);
                SetDescriptor(bus.Memory, descriptor, test.Length, test.Characters);
                int link = test.Characters + test.Length;
                bus.Memory[link] = 0xA6;
                bus.Memory[link + 1] = 0x5C;
                Processor<RecordingBus> cpu = Start(
                    bus, Address(useShared ? region : legacy, "FRETMP"),
                    (byte)descriptor, 0xA7, (byte)(descriptor >> 8));

                RunTo(cpu, 500, ReturnAddress);
                bool marked = linked && test.Latest && test.Length != 0;
                marked &= test.Characters >= test.Free && test.Characters < 0x8000;
                bool reclaimed = test.Latest && test.Characters == test.Free && (!linked || marked);
                GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(
                    test.Free + (reclaimed ? test.Length + (linked ? 2 : 0) : 0));

                bus.Memory[link].Should().Be(marked ? test.Length : (byte)0xA6);
                bus.Memory[link + 1].Should().Be(marked ? (byte)0xFF : (byte)0x5C);
                bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(test.Latest ? last : last + 3));
                GetWord(bus.Memory, Address(legacy, "LASTPT")).Should().Be(test.Latest ? last - 3 : last);
                cpu.Registers.Accumulator.Should().Be(test.Length);
                cpu.Registers.X.Should().Be((byte)test.Characters);
                cpu.Registers.Y.Should().Be((byte)(test.Characters >> 8));
                GetWord(bus.Memory, Address(legacy, "INDEX")).Should().Be(test.Characters);
            }
        }
    }

    /// <summary>
    ///  The linked release honors each BASIC 4 revision's real disk-status eligibility helper.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is used.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void LinkedReleaseUsesTheRevisionSpecificStatusCheck(bool original)
    {
        AssemblyResult legacy = Legacy(Pet4, original);
        AssemblyResult region = AssembleRegion(legacy, linkedRelease: true);
        foreach (byte statusLength in (byte[])[0, 3])
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, region, useShared);
                const int characters = 0x70FE;
                int temp = Address(legacy, "TEMPST");
                int status = Address(legacy, "DSDESC");
                bus.Memory[Address(legacy, "TEMPPT")] = (byte)(temp + 3);
                SetWord(bus.Memory, Address(legacy, "LASTPT"), temp);
                SetWord(bus.Memory, Address(legacy, "FRETOP"), characters);
                SetDescriptor(bus.Memory, temp, 1, characters);
                SetDescriptor(bus.Memory, status, statusLength, characters);
                bus.Memory[characters + 1] = 0xA6;
                bus.Memory[characters + 2] = 0x5C;
                Processor<RecordingBus> cpu = Start(
                    bus, Address(useShared ? region : legacy, "FRETMP"), (byte)temp, 0xA7, (byte)(temp >> 8));

                RunTo(cpu, 500, ReturnAddress);
                bool reclaimed = !original && statusLength == 0;
                GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(characters + (reclaimed ? 3 : 0));
                bus.Memory[characters + 1].Should().Be(reclaimed ? (byte)1 : (byte)0xA6);
                bus.Memory[characters + 2].Should().Be(reclaimed ? (byte)0xFF : (byte)0x5C);
                GetWord(bus.Memory, Address(legacy, "INDEX")).Should().Be(characters);
                cpu.Registers.Accumulator.Should().Be(1);
            }
        }
    }

    /// <summary>
    ///  The release selection can be assembled independently of the surrounding workspace.
    /// </summary>
    /// <param name="linked">Whether release uses linked heap records.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ReleaseChoiceIsIndependent(bool linked)
    {
        AssemblyResult legacy = Legacy(Pet4, original: false);
        AssemblyResult region = AssembleRegion(legacy, linked);
        RecordingBus bus = CreateBus(legacy, region, useShared: true);
        const int characters = 0x70FE;
        int temp = Address(legacy, "TEMPST");
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)(temp + 3);
        SetWord(bus.Memory, Address(legacy, "LASTPT"), temp);
        SetWord(bus.Memory, Address(legacy, "FRETOP"), characters);
        SetDescriptor(bus.Memory, temp, 1, characters);
        bus.Memory[characters + 1] = 0xA6;
        bus.Memory[characters + 2] = 0x5C;
        Processor<RecordingBus> cpu = Start(bus, Address(region, "FRETMP"), (byte)temp, 0xA7, (byte)(temp >> 8));
        RunTo(cpu, 500, ReturnAddress);
        GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(characters + (linked ? 3 : 1));
        bus.Memory[characters + 1].Should().Be(linked ? (byte)1 : (byte)0xA6);
        bus.Memory[characters + 2].Should().Be(linked ? (byte)0xFF : (byte)0x5C);
        GetWord(bus.Memory, Address(legacy, "INDEX")).Should().Be(characters);
    }

    /// <summary>
    ///  Promoted routines retain their documentation and debugger chains in AppleSoft and linked PET code.
    /// </summary>
    [TestMethod]
    public void ConcatenationEntriesRetainDocumentationAndSourceChains()
    {
        AssemblyResult apple = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        SourceMapModule appleModule = new(apple, area: null);
        DebugTestMemory memory = new();
        int start = Address(apple, "CAT");
        int end = Address(apple, "CHR");
        memory.Set((ushort)start, apple.Sections[0].Bytes.Slice(start, end - start).ToArray());
        foreach (string name in (string[])["CAT", "MOVINS", "MOVSTR", "MOVDO", "FRESTR", "FREFAC", "FRETMP", "FRETMS"])
        {
            DocumentationTopic topic = appleModule.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(apple.Symbol(name));
            topic.Path.Should().EndWith("MsBasic.StringConcatenation.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
            DebugPosition position = appleModule.Position(memory, checked((ushort)apple.Symbol(name)))
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Select(line => Path.GetFileName(line.Path))
                .Should().Equal("MsBasic.StringConcatenation.asm", "AppleSoft.Strings.asm");
        }

        CheckDocumentation(appleModule);
        AssemblyResult pet = Legacy(Pet4, original: false);
        SourceMapModule linked = new(AssembleRegion(pet, linkedRelease: true), area: null);
        foreach (string name in (string[])["CAT", "MOVSTR", "MOVDO", "FRESTR", "FREFAC", "FRETMP", "FRETMS"])
        {
            DocumentationTopic topic = linked.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented for linked strings.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.StringConcatenation.asm");
        }

        CheckDocumentation(linked);
    }

    private static AssemblyResult AppleLegacy(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), model);

    private static AssemblyResult Legacy(int variant, bool original) => variant switch
    {
        Apple => AppleLegacy(Apple2Model.IIeEnhanced),
        Pet1 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001, original),
        Pet2 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2),
        Pet4 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet4032, original),
        _ => throw new ArgumentOutOfRangeException(nameof(variant))
    };

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, bool linkedRelease)
    {
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StringConcatenation.asm"
            .org ${legacy.Symbol("CAT"):X4}
                STRING_CONCATENATION {(linkedRelease ? 1 : 0)}
            STRING_CONCATENATION_END:
            """;

        string[] dependencies =
        [
            "FAC", "FACMO", "FACLO", "EVAL", "CHKSTR", "STRNG1", "ERRLS", "ERROR", "STRINI", "DSCPNT",
            "PUTNEW", "TSTOP", "INDEX", "FRESPC", "FRETOP", "LASTPT", "TEMPPT", "STRSIZ", "TXTPTR", "CHR"
        ];

        if (linkedRelease) { dependencies = [.. dependencies, "STRADJ"]; }
        return Assemble(legacy, source, Path.Join(SharedInputs, "StringConcatenationTest.asm"), dependencies);
    }

    private static AssemblyResult AssemblePetWorkspace(AssemblyResult legacy, PetModel model)
    {
        bool early = model == PetModel.Pet2001;
        bool linked = model == PetModel.Pet4032;
        string options = early
            ? """
                INPUT_BUFFER_PAGE = 0
                INPUT_BUFFER_LENGTH = 80
                NULL_COMMAND = 1
                FULL_STACK_TOP = 1
                STACK_RESERVE_19 = 1
                TERMINAL_FIRST = 1
                LOCAL_TERMINAL_POSITION = 1
                VARIABLE_LIST_IN_LINE_NUMBER = 1
                CLOCK_IN_PAGE2 = 1
                STATUS_IN_PAGE2 = 1
                RND_TIMER_9044 = 1
                ERROR_PADDING5 = 1
                """
            : linked
                ? """
                    LINE_WIDTH_STORAGE = 0
                    DISK_STATUS_STRING = 1
                    EXTENDED_DISK_VECTORS = 1
                    """
                : "";

        string source = $"""
            .cpu Mos6502
            {options}
            .include "Commodore.Equates.asm"
            .include <MsBasic.StringConcatenation.asm>
            .org ${legacy.Symbol("CAT"):X4}
                STRING_CONCATENATION {(linked ? 1 : 0)}
            STRING_CONCATENATION_END:
            """;

        string[] dependencies = ["EVAL", "CHKSTR", "ERRLS", "ERROR", "STRINI", "PUTNEW", "TSTOP"];
        if (linked) { dependencies = [.. dependencies, "STRADJ"]; }
        return Assemble(legacy, source, Path.Join(Inputs, "Pet", "Basic", "PetConcatenationTest.asm"), dependencies);
    }

    private static AssemblyResult Assemble(AssemblyResult legacy, string source, string path, string[] dependencies)
    {
        int start = Address(legacy, "CAT");
        int end = Address(legacy, "CHR");
        HashSet<string> regionLabels = [.. legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant && symbol.Value >= start && symbol.Value < end).Select(symbol => symbol.Name)];

        dependencies.Any(regionLabels.Contains).Should().BeFalse("no label inside the region may be predefined");
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                SdkPaths = [SharedInputs],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "CAT");
        int end = Address(legacy, "CHR");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant
                && !symbol.Name.StartsWith("__m10_", StringComparison.Ordinal)
                && symbol.Value >= start
                && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static void AssertSpan(AssemblyResult region, int start, int end)
    {
        int next = start;
        foreach (AssemblySourceMapEntry entry in region.SourceMap.Where(entry =>
            entry.Size > 0 && entry.Operation != ".ORG").OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            entry.Address.Should().Be(next, "the native region must not have a gap or overlap");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end, "the native region must end immediately before CHR");
    }

    private static void CheckDocumentation(SourceMapModule module)
    {
        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) == "MsBasic.StringConcatenation.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, bool useShared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (useShared)
        {
            int start = Address(region, "CAT");
            int end = Address(region, "STRING_CONCATENATION_END");
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

    private static Processor<RecordingBus> Start(
        RecordingBus bus, int address, byte a = 0, byte x = 0, byte y = 0, StatusRegister status = StatusRegister.Unused)
    {
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)address),
                Accumulator = a,
                X = x,
                Y = y,
                StackPointer = 0xFD,
                Status = status
            }
        };
    }

    private static void RunTo(Processor<RecordingBus> cpu, int limit, params ushort[] exits)
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

    private static void SetDescriptor(byte[] memory, int descriptor, byte length, int characters)
    {
        memory[descriptor] = length;
        SetWord(memory, descriptor + 1, characters);
    }
}
