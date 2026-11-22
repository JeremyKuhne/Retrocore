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
///  Checks shared string storage against AppleSoft and all PET BASIC overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedStringStorageTests
{
    private const int Apple = 0;
    private const int Pet1 = 1;
    private const int Pet2 = 2;
    private const int Pet4 = 4;
    private const ushort ReturnAddress = 0x2000;
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
    private static readonly string s_shared = Path.Join(s_inputs, "Microsoft6502Basic");

    /// <summary>
    ///  The complete AppleSoft image and every promoted legacy label remain unchanged.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedStringStorage(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), model);
        AssemblyResult standalone = AssembleStorage(legacy, bufferPage: 2, clearFacOverflow: false, linkedStrings: false);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        AssertEmittedSpan(standalone, Address(legacy, "STRINI"), Address(legacy, "GARBA2"));
        standalone.Symbols["STRING_STORAGE_END"].Should().Be(legacy.Symbols["GARBA2"]);
        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
    }

    /// <summary>
    ///  The complete region and its legacy labels match all five PET revisions.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedStringStorageMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), model, original);
        bool early = model == PetModel.Pet2001;
        bool linked = model == PetModel.Pet4032;
        AssemblyResult native = AssembleStorage(legacy, early ? 0 : 2, clearFacOverflow: !early, linkedStrings: linked);
        CompareRegion(legacy, native);
        AssertEmittedSpan(native, Address(legacy, "STRINI"), Address(legacy, "GARBA2"));
        native.Symbols["STRING_STORAGE_END"].Should().Be(legacy.Symbols["GARBA2"]);
    }

    /// <summary>
    ///  Shared entries retain accurate documentation and debugger chains through both allocator macros.
    /// </summary>
    [TestMethod]
    public void StorageEntriesRetainDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), Apple2Model.IIeEnhanced);
        int start = Address(native, "STRINI");
        int end = Address(native, "GARBA2");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["STRINI", "STRSPA", "STRLIT", "STRLT2", "PUTNEW", "GETSPA"])
        {
            DocumentationTopic topic = module.Documentation.Find(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(native.Symbols[name]);
            topic.Path.Should().EndWith("MsBasic.StringStorage.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        foreach (string name in (string[])["STRINI", "STRLIT", "PUTNEW", "GETSPA"])
        {
            ushort address = checked((ushort)native.Symbols[name]);
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.StringStorage.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.Strings.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }

        DebugPosition retry = module.Position(memory, checked((ushort)native.Symbols["TRYAG2"]))
            ?? throw new AssertFailedException("TRYAG2 has no debugger source position.");

        retry.Chain.Select(line => Path.GetFileName(line.Path))
            .Should().Equal("MsBasic.StringStorage.Classic.asm", "MsBasic.StringStorage.asm", "AppleSoft.Strings.asm");

        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.StringStorage.asm"
                or "MsBasic.StringStorage.Classic.asm"
                or "AppleSoft.Strings.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    /// <summary>
    ///  The linked allocator retains its own documentation and platform source chain.
    /// </summary>
    [TestMethod]
    public void LinkedAllocatorRetainsDocumentationAndSourceChain()
    {
        AssemblyResult legacy = Legacy(Pet4);
        AssemblyResult native = AssembleVariant(legacy, Pet4);
        int start = Address(native, "STRINI");
        int end = Address(native, "STRING_STORAGE_END");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        DocumentationTopic topic = module.Documentation.Find("LINKED_STRING_ALLOCATION")
            ?? throw new AssertFailedException("The linked allocator is not documented.");

        topic.Kind.Should().Be(DocumentationKind.Macro);
        topic.Path.Should().EndWith("MsBasic.StringStorage.Linked.asm");
        topic.Summary.Should().NotBeNullOrWhiteSpace();
        DebugPosition retry = module.Position(memory, checked((ushort)native.Symbols["TRYAG2"]))
            ?? throw new AssertFailedException("The linked retry has no debugger source position.");

        retry.Chain.Select(line => Path.GetFileName(line.Path))
            .Should().Equal("MsBasic.StringStorage.Linked.asm", "MsBasic.StringStorage.asm", "StringStorageTest.asm");

        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.StringStorage.asm" or "MsBasic.StringStorage.Linked.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    /// <summary>
    ///  Buffer-page copying, overflow-byte clearing and linked allocation can be chosen independently.
    /// </summary>
    /// <param name="bufferPage">The configured input-buffer page.</param>
    /// <param name="clearFacOverflow">Whether PUTNEW clears FACOV.</param>
    /// <param name="linkedStrings">Whether allocation uses BASIC 4's linked representation.</param>
    [TestMethod]
    [DataRow(0, false, false)]
    [DataRow(0, false, true)]
    [DataRow(0, true, false)]
    [DataRow(0, true, true)]
    [DataRow(2, false, false)]
    [DataRow(2, false, true)]
    [DataRow(2, true, false)]
    [DataRow(2, true, true)]
    [DataRow(3, false, false)]
    [DataRow(3, false, true)]
    [DataRow(3, true, false)]
    [DataRow(3, true, true)]
    public void LiteralAndOverflowChoicesAreIndependent(int bufferPage, bool clearFacOverflow, bool linkedStrings)
    {
        AssemblyResult legacy = Legacy(linkedStrings ? Pet4 : Pet2);
        AssemblyResult native = AssembleStorage(legacy, bufferPage, clearFacOverflow, linkedStrings);
        foreach (int source in (int[])[0x020A, 0x030A])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared: true);
            "Q\""u8.CopyTo(bus.Memory.AsSpan(source));
            WriteWord(bus.Memory, Address(legacy, "FACMO"), 0x4321);
            Processor<RecordingBus> cpu = Start(bus, Address(native, "STRLIT"), (byte)source, (byte)(source >> 8));
            RunTo(cpu, 10000, -1, ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
            cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
            int descriptor = ReadWord(bus.Memory, Address(legacy, "FACMO"));
            int data = ReadWord(bus.Memory, descriptor + 1);
            int allocated = linkedStrings ? 0x6FFD : 0x6FFF;
            data.Should().Be(source >> 8 == bufferPage ? allocated : source);
            bus.Memory[data].Should().Be((byte)'Q');
            bus.Memory[Address(legacy, "FACOV")].Should().Be(clearFacOverflow ? (byte)0 : (byte)(source >> 8));
        }
    }

    /// <summary>
    ///  Literals stop on the right delimiter, cross pages, and copy only from the selected starting pages.
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
    public void LiteralsRetainTheirCopyingAndTerminatorBehavior(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        AssemblyResult native = AssembleVariant(legacy, variant);
        bool linked = variant == Pet4;
        int bufferPage = variant == Pet1 ? 0 : 2;
        byte[] maximum = [.. Enumerable.Repeat((byte)'A', 255), (byte)'"'];
        (int Source, byte[] Bytes, bool QuotedEntry, byte First, byte Second, int Length, bool Skip)[]
            cases =
            [
                (0x00F0, "HI\""u8.ToArray(), true, 0, 0, 2, true),
                (0x020A, "HI\""u8.ToArray(), true, 0, 0, 2, true),
                (0x30FE, "HI\""u8.ToArray(), true, 0, 0, 2, true),
                (0x3100, "HI\0"u8.ToArray(), true, 0, 0, 2, false),
                (0x3200, "HI,TAIL"u8.ToArray(), false, (byte)',', (byte)':', 2, false),
                (0x3200, "HI:TAIL"u8.ToArray(), false, (byte)',', (byte)':', 2, false),
                (0x3200, "HI\"TAIL"u8.ToArray(), false, (byte)'"', (byte)':', 2, true),
                (0x00F0, "\""u8.ToArray(), true, 0, 0, 0, true),
                (0x32F0, maximum, true, 0, 0, 255, true)
            ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, native, useShared);
                test.Bytes.CopyTo(bus.Memory, test.Source);
                WriteWord(bus.Memory, Address(legacy, "FACMO"), 0x4321);
                WriteWord(bus.Memory, Address(legacy, "DSCPNT"), 0x5678);
                bus.Memory[Address(legacy, "CHARAC")] = test.First;
                bus.Memory[Address(legacy, "ENDCHR")] = test.Second;
                AssemblyResult code = useShared ? native : legacy;
                Processor<RecordingBus> cpu = Start(
                    bus,
                    Address(code, test.QuotedEntry ? "STRLIT" : "STRLT2"),
                    (byte)test.Source,
                    (byte)(test.Source >> 8));

                RunTo(cpu, 10000, -1, ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
                cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
                ReadWord(bus.Memory, Address(legacy, "STRNG2"))
                    .Should().Be(test.Source + test.Length + (test.Skip ? 1 : 0));

                bool copied = test.Source >> 8 == 0 || (bufferPage != 0 && test.Source >> 8 == bufferPage);
                int expectedFree = 0x7000 - (copied ? test.Length + (linked && test.Length != 0 ? 2 : 0) : 0);
                int expectedData = copied
                    ? linked && test.Length == 0 ? 0x4300 : expectedFree
                    : test.Source;

                int descriptor = ReadWord(bus.Memory, Address(legacy, "FACMO"));
                descriptor.Should().Be(Address(legacy, "TEMPST"));
                bus.Memory[descriptor].Should().Be((byte)test.Length);
                ReadWord(bus.Memory, descriptor + 1).Should().Be(expectedData);
                bus.Memory.AsSpan(expectedData, test.Length).ToArray()
                    .Should().Equal(test.Bytes.AsSpan(0, test.Length).ToArray());

                ReadWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(expectedFree);
                ReadWord(bus.Memory, Address(legacy, "DSCPNT")).Should().Be(copied ? 0x4321 : 0x5678);
                bus.Memory[Address(legacy, "VALTYP")].Should().Be(0xFF);
            }
        }
    }

    /// <summary>
    ///  PUTNEW fills three descriptors, preserves the high byte of LASTPT, and rejects the fourth.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void TemporaryDescriptorStackKeepsItsLimitAndOverflowBehavior(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleVariant(legacy, variant);
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            int temp = Address(legacy, "TEMPST");
            int temporary = Address(legacy, "DSCTMP");
            int last = Address(legacy, "LASTPT");
            bus.Memory[last + 1] = 0x7B;
            bus.Memory[temp + 9] = 0xCC;
            for (int slot = 0; slot < 3; slot++)
            {
                bus.Memory[temporary] = (byte)(slot + 1);
                WriteWord(bus.Memory, temporary + 1, 0x6120 + slot);
                bus.Memory[Address(legacy, "FACOV")] = 0xA5;
                AssemblyResult code = useShared ? native : legacy;
                Processor<RecordingBus> cpu = Start(bus, Address(code, "PUTNEW"));
                RunTo(cpu, 1000, -1, ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
                cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
                int descriptor = temp + slot * 3;
                bus.Memory.AsSpan(descriptor, 3).ToArray()
                    .Should().Equal((byte)(slot + 1), (byte)(0x20 + slot), (byte)0x61);

                ReadWord(bus.Memory, Address(legacy, "FACMO")).Should().Be(descriptor);
                bus.Memory[Address(legacy, "VALTYP")].Should().Be(0xFF);
                bus.Memory[last].Should().Be((byte)descriptor);
                bus.Memory[last + 1].Should().Be(0x7B);
                bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(descriptor + 3));
                bus.Memory[Address(legacy, "FACOV")].Should().Be(variant is Pet2 or Pet4 ? (byte)0 : (byte)0xA5);
            }

            Processor<RecordingBus> overflow = Start(bus, Address(useShared ? native : legacy, "PUTNEW"));
            ushort error = checked((ushort)legacy.Symbols["ERROR"]);
            RunTo(overflow, 1000, -1, ReturnAddress, error);
            overflow.Registers.ProgramCounter.Should().Be(error);
            overflow.Registers.X.Should().Be((byte)legacy.Symbols["ERRST"]);
            bus.Memory[Address(legacy, "TEMPPT")].Should().Be((byte)(temp + 9));
            bus.Memory[temp + 9].Should().Be(0xCC);
            bus.Memory[last + 1].Should().Be(0x7B);
        }
    }

    /// <summary>
    ///  Allocators accept the exact boundary and distinguish zero-length and linked allocations.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void AllocatorsPreserveBoundsAndEmptyStringBehavior(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleVariant(legacy, variant);
        bool linked = variant == Pet4;
        int overhead = linked ? 2 : 0;
        (int Free, int Bound, byte Length)[] cases =
        [
            (0x7002, 0x6F00, 3),
            (0x6103 + overhead, 0x6100, 3),
            (0x6201, 0x5000, 0)
        ];

        foreach (var test in cases)
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, native, useShared);
                WriteWord(bus.Memory, Address(legacy, "FRETOP"), test.Free);
                WriteWord(bus.Memory, Address(legacy, "STREND"), test.Bound);
                WriteWord(bus.Memory, Address(legacy, "FRESPC"), 0x4444);
                bus.Memory[Address(legacy, "GARBFL")] = 0x81;
                AssemblyResult code = useShared ? native : legacy;
                Processor<RecordingBus> cpu = Start(bus, Address(code, "GETSPA"), test.Length, 0xA7);
                int collections = RunTo(cpu, 1000, Address(legacy, "GARBA2"), ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
                cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
                collections.Should().Be(0);
                bus.Memory[Address(legacy, "GARBFL")].Should().Be(0x40);
                cpu.Registers.Accumulator.Should().Be(test.Length);
                int expected = test.Free - test.Length - (linked && test.Length != 0 ? 2 : 0);
                ReadWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(expected);
                if (linked && test.Length == 0)
                {
                    cpu.Registers.X.Should().Be(0);
                    cpu.Registers.Y.Should().Be(0xA7);
                    ReadWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(0x4444);
                }
                else
                {
                    cpu.Registers.X.Should().Be((byte)expected);
                    cpu.Registers.Y.Should().Be((byte)(expected >> 8));
                    ReadWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(expected);
                    if (linked)
                    {
                        bus.Memory[test.Free - 2].Should().Be(test.Length);
                        bus.Memory[test.Free - 1].Should().Be(0xFF);
                    }
                }
            }
        }
    }

    /// <summary>
    ///  STRINI saves the original descriptor and STRSPA leaves DSCPNT alone.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void InitializersBuildDescriptorsAndSaveOnlyWhenRequested(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleVariant(legacy, variant);
        foreach (bool save in (bool[])[false, true])
        {
            foreach (bool useShared in (bool[])[false, true])
            {
                RecordingBus bus = CreateBus(legacy, native, useShared);
                WriteWord(bus.Memory, Address(legacy, "FACMO"), 0x4321);
                WriteWord(bus.Memory, Address(legacy, "DSCPNT"), 0x5678);
                AssemblyResult code = useShared ? native : legacy;
                Processor<RecordingBus> cpu = Start(bus, Address(code, save ? "STRINI" : "STRSPA"), 5);
                RunTo(cpu, 1000, -1, ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
                cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
                ReadWord(bus.Memory, Address(legacy, "DSCPNT")).Should().Be(save ? 0x4321 : 0x5678);
                int descriptor = Address(legacy, "DSCTMP");
                int expected = variant == Pet4 ? 0x6FF9 : 0x6FFB;
                bus.Memory[descriptor].Should().Be(5);
                ReadWord(bus.Memory, descriptor + 1).Should().Be(expected);
                ReadWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(expected);
                ReadWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(expected);
            }
        }
    }

    /// <summary>
    ///  A real variant collector is called once before allocation succeeds or reports out of memory.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC version.</param>
    /// <param name="fits">Whether collection frees enough room.</param>
    [TestMethod]
    [DataRow(Apple, true)]
    [DataRow(Apple, false)]
    [DataRow(Pet1, true)]
    [DataRow(Pet1, false)]
    [DataRow(Pet2, true)]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, true)]
    [DataRow(Pet4, false)]
    public void AllocatorRetriesAfterTheMatchingCollector(int variant, bool fits)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleVariant(legacy, variant);
        bool linked = variant == Pet4;
        int bound = linked ? (fits ? 0x60EC : 0x60F0) : 0x6000;
        int top = linked ? 0x6100 : fits ? 0x6100 : 0x6018;
        int free = linked ? 0x60F0 : 0x6010;
        byte length = linked ? fits ? (byte)5 : (byte)15 : (byte)0x20;
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            WriteWord(bus.Memory, Address(legacy, "VARTAB"), bound);
            WriteWord(bus.Memory, Address(legacy, "ARYTAB"), bound);
            WriteWord(bus.Memory, Address(legacy, "STREND"), bound);
            WriteWord(bus.Memory, Address(legacy, "FRETOP"), free);
            WriteWord(bus.Memory, Address(legacy, "MEMSIZ"), top);
            bus.Memory[Address(legacy, "GARBFL")] = 0x81;
            if (linked)
            {
                bus.Memory[top - 2] = 14;
                bus.Memory[top - 1] = 0xFF;
            }

            AssemblyResult code = useShared ? native : legacy;
            Processor<RecordingBus> cpu = Start(bus, Address(code, "GETSPA"), length);
            ushort error = checked((ushort)legacy.Symbols["ERROR"]);
            int collections = RunTo(cpu, 20000, Address(legacy, "GARBA2"), ReturnAddress, error);
            cpu.Registers.ProgramCounter.Should().Be(fits ? ReturnAddress : error);
            collections.Should().Be(1);
            bus.Memory[Address(legacy, "GARBFL")].Should().Be(linked ? (byte)0xA0 : (byte)0x80);
            if (!fits)
            {
                cpu.Registers.X.Should().Be((byte)legacy.Symbols["ERROM"]);
                continue;
            }

            int expected = top - length - (linked ? 2 : 0);
            ReadWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(expected);
            ReadWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(expected);
            cpu.Registers.Accumulator.Should().Be(length);
            cpu.Registers.X.Should().Be((byte)expected);
            cpu.Registers.Y.Should().Be((byte)(expected >> 8));
            if (linked)
            {
                bus.Memory[top - 2].Should().Be(length);
                bus.Memory[top - 1].Should().Be(0xFF);
            }
        }
    }

    /// <summary>
    ///  When a zero-length unlinked request starts below STREND, the original code enters the collector twice.
    /// </summary>
    /// <param name="variant">The AppleSoft or unlinked PET BASIC version.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    public void EmptyUnlinkedRequestFallsThroughToTheCollectorAgain(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        AssemblyResult native = AssembleVariant(legacy, variant);
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            WriteWord(bus.Memory, Address(legacy, "VARTAB"), 0x6001);
            WriteWord(bus.Memory, Address(legacy, "ARYTAB"), 0x6001);
            WriteWord(bus.Memory, Address(legacy, "STREND"), 0x6001);
            WriteWord(bus.Memory, Address(legacy, "FRETOP"), 0x6000);
            WriteWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x6100);
            WriteWord(bus.Memory, Address(legacy, "FRESPC"), 0x4444);
            AssemblyResult code = useShared ? native : legacy;
            Processor<RecordingBus> cpu = Start(bus, Address(code, "GETSPA"));
            int collections = RunTo(cpu, 20000, Address(legacy, "GARBA2"), ReturnAddress, checked((ushort)legacy.Symbols["ERROR"]));
            cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
            collections.Should().Be(2);
            ReadWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(0x6100);
            ReadWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(0x4444);
        }
    }

    private static AssemblyResult Legacy(int variant, bool original = false) => variant switch
    {
        Apple => SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10), Apple2Model.IIeEnhanced),
        Pet1 => PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001, original),
        Pet2 => PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001Basic2),
        Pet4 => PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet4032, original),
        _ => throw new ArgumentOutOfRangeException(nameof(variant))
    };

    private static AssemblyResult AssembleVariant(AssemblyResult legacy, int variant) =>
        AssembleStorage(legacy, variant == Pet1 ? 0 : 2, variant is Pet2 or Pet4, variant == Pet4);

    private static AssemblyResult AssembleStorage(
        AssemblyResult legacy,
        int bufferPage,
        bool clearFacOverflow,
        bool linkedStrings)
    {
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StringStorage.asm"
            .org ${legacy.Symbols["STRINI"]:X4}
                STRING_STORAGE {bufferPage}, {(clearFacOverflow ? 1 : 0)}
                STRING_ALLOCATION {(linkedStrings ? 1 : 0)}
            STRING_STORAGE_END:
            """;

        string[] dependencies =
        [
            "FACMO", "FACLO", "DSCPNT", "DSCTMP", "CHARAC", "ENDCHR", "STRNG1", "STRNG2",
            "TEMPPT", "TEMPST", "STRSIZ", "NUMTMP", "ERRST", "ERROR", "VALTYP", "LASTPT",
            "GARBFL", "FRETOP", "STREND", "ERROM", "GARBA2", "MOVSTR", "FACOV", "FRESPC", "INDEX"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbols[name], StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(s_shared, "StringStorageTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = symbols
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "STRINI");
        int end = Address(legacy, "GARBA2");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant
                && !symbol.Name.StartsWith("__m10_", StringComparison.Ordinal)
                && symbol.Value >= start
                && symbol.Value < end))
        {
            native.Symbols.Should().ContainKey(label.Name);
            native.Symbols[label.Name].Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
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

        next.Should().Be(end, "the native region must end immediately before the collector");
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult native, bool useShared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (useShared)
        {
            int start = Address(native, "STRINI");
            int end = Address(native, "STRING_STORAGE_END");
            native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        int temp = Address(legacy, "TEMPST");
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)temp;
        WriteWord(bus.Memory, Address(legacy, "LASTPT"), temp - 3);
        WriteWord(bus.Memory, Address(legacy, "VARTAB"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "ARYTAB"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "STREND"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        WriteWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x7000);
        WriteWord(bus.Memory, Address(legacy, "FRESPC"), 0x4444);
        return bus;
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, int address, byte accumulator = 0, byte y = 0)
    {
        WriteWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)address),
                StackPointer = 0xFD,
                Accumulator = accumulator,
                X = 0x5A,
                Y = y,
                Status = StatusRegister.Unused
            }
        };
    }

    private static int RunTo(Processor<RecordingBus> cpu, int limit, int watched, params ushort[] exits)
    {
        int visits = 0;
        for (int instruction = 0; instruction < limit && !exits.Contains(cpu.Registers.ProgramCounter); instruction++)
        {
            if (cpu.Registers.ProgramCounter == watched) { visits++; }
            cpu.StepInstruction();
        }

        exits.Should().Contain(cpu.Registers.ProgramCounter, "the routine must reach an expected exit");
        return visits;
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbols[name]);

    private static int ReadWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void WriteWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
