// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the native string collectors against AppleSoft and all PET BASIC overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedGarbageCollectionTests
{
    private const ushort ReturnAddress = 0x2000;
    private const int Scalar = 0x50D5;
    private const int Array = 0x50F8;
    private const int ArrayDescriptor = Array + 7;
    private const int Top = 0x7100;
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  The complete AppleSoft image and every collector label retain their original bytes and addresses.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    /// <param name="expectedHash">The model's ROM digest.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "ED8D83176BB9445B3EAA815E07956777BDFAA9E4892A8D7F5019DEAD62434C4C")]
    [DataRow(Apple2Model.IIe, "9676882149E86EDCAA960639140BB2070439F667997A5405987B9DB8742746EB")]
    [DataRow(Apple2Model.IIeEnhanced, "498D7571F6C6A920075084B84D497619DEF48F9D5A7160A964B3B512EE5214FC")]
    public void AppleSoftCollectorRetainsBytesLabelsAndDigest(Apple2Model model, string expectedHash)
    {
        AssemblyResult legacy = AppleLegacy(model);
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult region = AssembleClassic(legacy, fullPointer: false, patchedArray: false, subtractOffset: false);
        int start = Address(legacy, "GARBA2");
        int end = Address(legacy, "CAT");
        CompareRegion(legacy, native, start, end);
        CompareRegion(legacy, region, start, end);
        AssertSpan(region, start, end);
        region.Symbol("COLLECTOR_END").Should().Be(end);
        CheckStringEntryParity(legacy, native);
        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
        Convert.ToHexString(SHA256.HashData(SdkModules.AppleSoftImage(native).Span)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  The classic PET collectors retain every byte and label and call BASIC 1's external editor-ROM patch.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    public void ClassicCollectorMatchesPetOverlays(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacy(model, original);
        bool early = model == PetModel.Pet2001;
        AssemblyResult region = AssembleClassic(legacy, fullPointer: !early, patchedArray: early, subtractOffset: early);
        int start = Address(legacy, "GARBA2");
        int end = Address(legacy, "CAT");
        CompareRegion(legacy, region, start, end);
        AssertSpan(region, start, end);
        region.Symbol("COLLECTOR_END").Should().Be(end);
        AssemblyResult composed = AssembleClassicWithPetWorkspace(legacy, early);
        CompareRegion(legacy, composed, start, end);
        AssertSpan(composed, start, end);
        composed.Symbol("COLLECTOR_END").Should().Be(end);
        CheckStringEntryParity(legacy);
        CheckPetStringSlice(legacy, early, linked: false);
        if (early)
        {
            int patch = Address(legacy, "ARYINC");
            patch.Should().Be(0xE7F3);
            region.Symbol("ARYINC").Should().Be(patch);
        }
    }

    /// <summary>
    ///  Both BASIC 4 revisions retain the complete linked collector, including all helper labels.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is used.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void LinkedCollectorMatchesPetFourOverlay(bool original)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet4032, original);
        AssemblyResult region = AssembleLinked(legacy);
        int start = Address(legacy, "GARBA2");
        int end = Address(legacy, "CAT");
        CompareRegion(legacy, region, start, end);
        AssertSpan(region, start, end);
        region.Symbol("COLLECTOR_END").Should().Be(end);
        CheckStringEntryParity(legacy);
        CheckPetStringSlice(legacy, early: false, linked: true);
        foreach (bool explicitWorkspace in (bool[])[false, true])
        {
            AssemblyResult composed = AssembleLinkedWithPetWorkspace(legacy, explicitWorkspace);
            CompareRegion(legacy, composed, start, end);
            AssertSpan(composed, start, end);
            composed.Symbol("COLLECTOR_END").Should().Be(end);
        }
    }

    /// <summary>
    ///  Classic collection compacts scalar and array strings while ignoring other types and literals.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1 or PET BASIC 2.</param>
    /// <param name="original">Whether BASIC 1 uses its original chip.</param>
    [TestMethod]
    [DataRow(0, false)]
    [DataRow(1, false)]
    [DataRow(1, true)]
    [DataRow(2, false)]
    public void ClassicCollectorHandlesScalarsAndCrossPageArrays(int variant, bool original)
    {
        AssemblyResult legacy = VariantLegacy(variant, original);
        bool early = variant == 1;
        AssemblyResult region = AssembleClassic(legacy, fullPointer: variant == 2, patchedArray: early, subtractOffset: early);
        foreach (bool shared in (bool[])[false, true])
        {
            CheckClassicCompaction(legacy, region, shared, early);
        }
    }

    /// <summary>
    ///  The page-zero sentinel bug remains in AppleSoft and BASIC 1, but BASIC 2 collects temporaries.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1 or PET BASIC 2.</param>
    /// <param name="original">Whether BASIC 1 uses its original chip.</param>
    [TestMethod]
    [DataRow(0, false)]
    [DataRow(1, false)]
    [DataRow(1, true)]
    [DataRow(2, false)]
    public void ClassicCollectorRetainsTemporaryDescriptorBehavior(int variant, bool original)
    {
        AssemblyResult legacy = VariantLegacy(variant, original);
        bool early = variant == 1;
        bool full = variant == 2;
        AssemblyResult region = AssembleClassic(legacy, full, early, early);
        foreach (bool shared in (bool[])[false, true])
        {
            CheckTemporarySelection(legacy, region, shared, full, early);
        }
    }

    /// <summary>
    ///  The classic scan includes a string at STREND but rejects one at MEMSIZ.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1 or PET BASIC 2.</param>
    [TestMethod]
    [DataRow(data: 0)]
    [DataRow(data: 1)]
    [DataRow(data: 2)]
    public void ClassicCollectorRespectsHeapBoundaries(int variant)
    {
        AssemblyResult legacy = VariantLegacy(variant, original: false);
        bool early = variant == 1;
        AssemblyResult region = AssembleClassic(legacy, fullPointer: variant == 2, patchedArray: early, subtractOffset: early);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateClassicBus(legacy, region, shared);
            const int lower = 0x5119;
            const int upper = 0x5200;
            SetWord(bus.Memory, Address(legacy, "MEMSIZ"), upper);
            SetWord(bus.Memory, Address(legacy, "FRETOP"), lower);
            SetDescriptor(bus.Memory, Scalar + 2, 6, lower);
            SetDescriptor(bus.Memory, Scalar + 21 + 2, 3, upper);
            bus.Memory[ArrayDescriptor] = 0;
            "LIMIT!"u8.CopyTo(bus.Memory.AsSpan(lower));
            Run(bus, Address(shared ? region : legacy, "GARBA2"));
            GetWord(bus.Memory, Scalar + 3).Should().Be(upper - 6);
            GetWord(bus.Memory, Scalar + 21 + 3).Should().Be(upper);
            GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(upper - 6);
            bus.Memory.AsSpan(upper - 6, 6).ToArray().Should().Equal("LIMIT!"u8.ToArray());
        }
    }

    /// <summary>
    ///  The three classic collector quirks can be selected independently, not only in historical combinations.
    /// </summary>
    /// <param name="fullPointer">Whether both bytes of the descriptor sentinel are tested.</param>
    /// <param name="patchedArray">Whether the array step is out of line.</param>
    /// <param name="subtractOffset">Whether the descriptor offset is calculated by subtraction.</param>
    [TestMethod]
    [DataRow(false, false, false)]
    [DataRow(false, false, true)]
    [DataRow(false, true, false)]
    [DataRow(false, true, true)]
    [DataRow(true, false, false)]
    [DataRow(true, false, true)]
    [DataRow(true, true, false)]
    [DataRow(true, true, true)]
    public void ClassicCollectorChoicesAreIndependent(bool fullPointer, bool patchedArray, bool subtractOffset)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet2001, original: false);
        AssemblyResult region = AssembleClassic(legacy, fullPointer, patchedArray, subtractOffset);
        CheckClassicCompaction(legacy, region, shared: true, patchedArray);
        CheckTemporarySelection(legacy, region, shared: true, fullPointer, patchedArray);
    }

    /// <summary>
    ///  Empty classic tables return even when the previous descriptor pointer was nonzero.
    /// </summary>
    /// <param name="fullPointer">Whether both bytes of the descriptor sentinel are tested.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void EmptyClassicCollectionClearsItsSentinel(bool fullPointer)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet2001, original: false);
        AssemblyResult region = AssembleClassic(legacy, fullPointer, patchedArray: false, subtractOffset: false);
        RecordingBus bus = CreateBus(legacy, region, shared: true);
        SetWord(bus.Memory, Address(legacy, "VARTAB"), 0x5000);
        SetWord(bus.Memory, Address(legacy, "ARYTAB"), 0x5000);
        SetWord(bus.Memory, Address(legacy, "STREND"), 0x5000);
        SetWord(bus.Memory, Address(legacy, "MEMSIZ"), Top);
        SetWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        SetWord(bus.Memory, Address(legacy, "GRBPNT"), 0x7FA5);
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)Address(legacy, "TEMPST");
        bus.Memory[Address(legacy, "FOUR6")] = 3;
        Run(bus, Address(region, "GARBA2"));
        GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(Top);
        bus.Memory[Address(legacy, "GRBPNT") + 1].Should().Be(0);
        bus.Memory[Address(legacy, "GRBPNT")].Should().Be(fullPointer ? (byte)0 : (byte)0xA5);
    }

    /// <summary>
    ///  Linked collection handles live links, an artificial page-zero back-link, holes and a 255-byte string.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is used.</param>
    /// <param name="holes">Whether garbage is interleaved with live strings.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void LinkedCollectorCompactsAndRepairsBackLinks(bool original, bool holes)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet4032, original);
        AssemblyResult region = AssembleLinked(legacy);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, region, shared);
            const int top = 0x7300;
            const int topDescriptor = 0x50F0;
            const int bottomDescriptor = 0x5101;
            const int literalDescriptor = 0x5110;
            const int middleDescriptor = 0x5120;
            int temporary = Address(legacy, "TEMPST");
            int cursor = top;
            byte[] longString = [.. Enumerable.Range(0, 255).Select(value => (byte)value)];
            AppendLive(bus.Memory, ref cursor, topDescriptor, "TOP"u8.ToArray());
            if (holes) { AppendGarbage(bus.Memory, ref cursor, 6); }
            AppendLive(bus.Memory, ref cursor, temporary, longString);
            AppendLive(bus.Memory, ref cursor, middleDescriptor, "YZ"u8.ToArray());
            if (holes) { AppendGarbage(bus.Memory, ref cursor, 1); }
            AppendLive(bus.Memory, ref cursor, bottomDescriptor, "HELLO"u8.ToArray());
            SetDescriptor(bus.Memory, literalDescriptor, 3, 0x4000);
            "TXT"u8.CopyTo(bus.Memory.AsSpan(0x4000));
            SetWord(bus.Memory, Address(legacy, "MEMSIZ"), top);
            SetWord(bus.Memory, Address(legacy, "FRETOP"), cursor);
            SetWord(bus.Memory, Address(legacy, "FRESPC"), 0x1234);

            Run(bus, Address(shared ? region : legacy, "GARBA2"));

            CheckLinkedString(bus.Memory, topDescriptor, 0x72FB, "TOP"u8.ToArray());
            CheckLinkedString(bus.Memory, temporary, 0x71FA, longString);
            CheckLinkedString(bus.Memory, middleDescriptor, 0x71F6, "YZ"u8.ToArray());
            CheckLinkedString(bus.Memory, bottomDescriptor, 0x71EF, "HELLO"u8.ToArray());
            GetWord(bus.Memory, literalDescriptor + 1).Should().Be(0x4000);
            bus.Memory.AsSpan(0x4000, 3).ToArray().Should().Equal("TXT"u8.ToArray());
            GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(0x71EF);
            GetWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(0x71EF);
        }
    }

    /// <summary>
    ///  Each allocator can invoke the new collector and retry an allocation after reclaiming garbage.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1, 2 or 4.</param>
    [TestMethod]
    [DataRow(data: 0)]
    [DataRow(data: 1)]
    [DataRow(data: 2)]
    [DataRow(data: 4)]
    public void AllocatorRetriesThroughTheNativeCollector(int variant)
    {
        AssemblyResult legacy = variant == 4
            ? PetLegacy(PetModel.Pet4032, original: false)
            : VariantLegacy(variant, original: false);

        bool early = variant == 1;
        AssemblyResult region = variant == 4
            ? AssembleLinked(legacy)
            : AssembleClassic(legacy, fullPointer: variant == 2, patchedArray: early, subtractOffset: early);

        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus;
            int expected;
            byte length;
            if (variant == 4)
            {
                bus = CreateBus(legacy, region, shared);
                int cursor = 0x7300;
                AppendGarbage(bus.Memory, ref cursor, 10);
                AppendLive(bus.Memory, ref cursor, 0x5000, "ALIVE"u8.ToArray());
                SetWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x7300);
                SetWord(bus.Memory, Address(legacy, "FRETOP"), cursor);
                SetWord(bus.Memory, Address(legacy, "STREND"), cursor - 4);
                expected = 0x72F1;
                length = 6;
            }
            else
            {
                bus = CreateClassicBus(legacy, region, shared);
                SetWord(bus.Memory, Address(legacy, "FRETOP"), 0x511D);
                expected = 0x70ED;
                length = 8;
            }

            bus.Memory[Address(legacy, "GARBFL")] = 0;
            Processor<RecordingBus> cpu = Run(bus, Address(legacy, "GETSPA"), length);
            GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(expected);
            GetWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(expected);
            cpu.Registers.Accumulator.Should().Be(length);
            cpu.Registers.X.Should().Be((byte)expected);
            cpu.Registers.Y.Should().Be((byte)(expected >> 8));
            if (variant == 4)
            {
                CheckLinkedString(bus.Memory, 0x5000, 0x72F9, "ALIVE"u8.ToArray());
                bus.Memory[0x72F7].Should().Be(length);
                bus.Memory[0x72F8].Should().Be(0xFF);
            }
        }
    }

    /// <summary>
    ///  BASIC 4's allocator marks an unassigned temporary as garbage, so collection can reclaim it.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is used.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void LinkedCollectorRetainsUnassignedTemporaryBehavior(bool original)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet4032, original);
        AssemblyResult region = AssembleLinked(legacy);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, region, shared);
            int temp = Address(legacy, "TEMPST");
            bus.Memory[Address(legacy, "TEMPPT")] = (byte)temp;
            SetWord(bus.Memory, Address(legacy, "LASTPT"), temp - 3);
            SetWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x7300);
            SetWord(bus.Memory, Address(legacy, "FRETOP"), 0x7300);
            SetWord(bus.Memory, Address(legacy, "STREND"), 0x72F4);
            bus.Memory[Address(legacy, "GARBFL")] = 0;
            Run(bus, Address(legacy, "STRSPA"), accumulator: 5);
            "ABCDE"u8.CopyTo(bus.Memory.AsSpan(0x72F9));
            Run(bus, Address(legacy, "PUTNEW"));
            GetWord(bus.Memory, temp + 1).Should().Be(0x72F9);
            bus.Memory[0x72FE].Should().Be(5);
            bus.Memory[0x72FF].Should().Be(0xFF);

            Run(bus, Address(legacy, "GETSPA"), accumulator: 6);

            GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(0x72F8);
            GetWord(bus.Memory, temp + 1).Should().Be(0x72F9);
            "123456"u8.CopyTo(bus.Memory.AsSpan(0x72F8));
            bus.Memory.AsSpan(0x72F9, 5).ToArray().Should().Equal("23456"u8.ToArray());
        }
    }

    /// <summary>
    ///  STR$ retains each formatter's sign convention and removes its extra return address.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1, 2 or 4.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(0, false)]
    [DataRow(1, false)]
    [DataRow(1, true)]
    [DataRow(2, false)]
    [DataRow(4, false)]
    [DataRow(4, true)]
    public void StringFromNumberKeepsFormattingAndReturnBehavior(int variant, bool original)
    {
        AssemblyResult legacy = VariantLegacy(variant, original);
        AssemblyResult region = AssembleStringEntry(legacy);
        foreach (bool negative in (bool[])[false, true])
        {
            foreach (bool shared in (bool[])[false, true])
            {
                RecordingBus bus = CreateStringEntryBus(legacy, region, shared);
                bus.Memory[Address(legacy, "VALTYP")] = 0;
                bus.Memory[Address(legacy, "FACEXP")] = 0;
                bus.Memory[Address(legacy, "FACSGN")] = negative ? (byte)0x80 : (byte)0;
                SetWord(bus.Memory, 0x01FC, 0x1234);
                SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
                Processor<RecordingBus> cpu = new(bus)
                {
                    Registers = new()
                    {
                        ProgramCounter = checked((ushort)legacy.Symbol("STR")),
                        StackPointer = 0xFB,
                        X = 0x5A,
                        Y = 0xC3,
                        Status = StatusRegister.Unused
                    }
                };

                StepToReturn(cpu);
                cpu.Registers.StackPointer.Should().Be(0xFF);
                byte[] expected = negative ? "-0"u8.ToArray() : variant == 0 ? "0"u8.ToArray() : " 0"u8.ToArray();
                CheckTemporaryString(bus.Memory, legacy, expected);
            }
        }
    }

    /// <summary>
    ///  STR$ rejects a string operand with the original type-mismatch error.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1, 2 or 4.</param>
    [TestMethod]
    [DataRow(data: 0)]
    [DataRow(data: 1)]
    [DataRow(data: 2)]
    [DataRow(data: 4)]
    public void StringFromNumberRejectsStringOperand(int variant)
    {
        AssemblyResult legacy = VariantLegacy(variant, original: false);
        AssemblyResult region = AssembleStringEntry(legacy);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateStringEntryBus(legacy, region, shared);
            bus.Memory[Address(legacy, "VALTYP")] = 0xFF;
            SetWord(bus.Memory, 0x01FC, 0x1234);
            SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
            Processor<RecordingBus> cpu = new(bus)
            {
                Registers = new()
                {
                    ProgramCounter = checked((ushort)legacy.Symbol("STR")),
                    StackPointer = 0xFB,
                    Status = StatusRegister.Unused
                }
            };

            StepTo(cpu, checked((ushort)legacy.Symbol("ERROR")));
            cpu.Registers.X.Should().Be((byte)legacy.Symbol("ERRTM"));
        }
    }

    /// <summary>
    ///  TIMSTR copies a page-crossing buffer through the quote, without discarding its return address.
    /// </summary>
    /// <param name="variant">AppleSoft, PET BASIC 1, 2 or 4.</param>
    [TestMethod]
    [DataRow(data: 0)]
    [DataRow(data: 1)]
    [DataRow(data: 2)]
    [DataRow(data: 4)]
    public void TimeStringEntryCopiesTheBufferAndReturnsNormally(int variant)
    {
        AssemblyResult legacy = VariantLegacy(variant, original: false);
        AssemblyResult region = AssembleStringEntry(legacy);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateStringEntryBus(legacy, region, shared);
            "AB\"X"u8.CopyTo(bus.Memory.AsSpan(0x00FF));
            Processor<RecordingBus> cpu = Run(bus, Address(legacy, "TIMSTR"));
            cpu.Registers.StackPointer.Should().Be(0xFF);
            CheckTemporaryString(bus.Memory, legacy, "AB"u8.ToArray());
            GetWord(bus.Memory, Address(legacy, "STRNG2")).Should().Be(0x0102);
        }
    }

    /// <summary>
    ///  An empty linked heap and a heap containing only garbage both recover the entire string space.
    /// </summary>
    /// <param name="original">Whether the original BASIC 4 chip is used.</param>
    /// <param name="garbage">Whether the heap contains garbage rather than being empty.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void LinkedCollectorHandlesEmptyAndAllGarbageHeaps(bool original, bool garbage)
    {
        AssemblyResult legacy = PetLegacy(PetModel.Pet4032, original);
        AssemblyResult region = AssembleLinked(legacy);
        foreach (bool shared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, region, shared);
            const int top = 0x7300;
            int cursor = top;
            if (garbage)
            {
                AppendGarbage(bus.Memory, ref cursor, 255);
                AppendGarbage(bus.Memory, ref cursor, 1);
            }

            SetWord(bus.Memory, Address(legacy, "MEMSIZ"), top);
            SetWord(bus.Memory, Address(legacy, "FRETOP"), cursor);
            SetWord(bus.Memory, Address(legacy, "FRESPC"), 0x1234);
            Run(bus, Address(shared ? region : legacy, "GARBA2"));
            GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(top);
            GetWord(bus.Memory, Address(legacy, "FRESPC")).Should().Be(top);
        }
    }

    /// <summary>
    ///  The collector entries retain documentation and breakpoint-capable source chains.
    /// </summary>
    [TestMethod]
    public void CollectorsRetainDocumentationAndSourcePositions()
    {
        AssemblyResult apple = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        SourceMapModule appleModule = new(apple, area: null);
        DebugTestMemory memory = new();
        int start = Address(apple, "GARBA2");
        int end = Address(apple, "CAT");
        memory.Set((ushort)start, apple.Sections[0].Bytes.Slice(start, end - start).ToArray());
        foreach (string name in (string[])["GARBA2", "DVARS", "DVAR", "GRBPAS"])
        {
            DocumentationTopic topic = appleModule.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.StringGarbageCollection.asm");
            DebugPosition position = appleModule.Position(memory, checked((ushort)apple.Symbol(name)))
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Select(line => Path.GetFileName(line.Path))
                .Should().Equal("MsBasic.StringGarbageCollection.asm", "AppleSoft.Strings.asm");
        }

        CheckDocumentation(appleModule, "MsBasic.StringGarbageCollection.asm");
        int stringStart = Address(apple, "STR");
        int stringEnd = Address(apple, "STRINI");
        memory.Set((ushort)stringStart, apple.Sections[0].Bytes.Slice(stringStart, stringEnd - stringStart).ToArray());
        foreach (string name in (string[])["STR", "TIMSTR"])
        {
            DocumentationTopic topic = appleModule.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.StringConversion.asm");
            DebugPosition position = appleModule.Position(memory, checked((ushort)apple.Symbol(name)))
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Select(line => Path.GetFileName(line.Path))
                .Should().Equal("MsBasic.StringConversion.asm", "AppleSoft.Strings.asm");
        }

        CheckDocumentation(appleModule, "MsBasic.StringConversion.asm");
        AssemblyResult pet = PetLegacy(PetModel.Pet4032, original: false);
        SourceMapModule linked = new(AssembleLinked(pet), area: null);
        foreach (string name in (string[])["GARBA2", "ENDGRB", "SKIP2", "MOVPNT", "MOVTOP", "SETINX"])
        {
            DocumentationTopic topic = linked.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("Commodore.StringGarbageCollection.asm");
        }

        CheckDocumentation(linked, "Commodore.StringGarbageCollection.asm");
        AssemblyResult petOne = PetLegacy(PetModel.Pet2001, original: false);
        AssemblyResult patchedRegion = AssembleClassic(petOne, fullPointer: false, patchedArray: true, subtractOffset: true);
        SourceMapModule patched = new(patchedRegion, area: null);
        CheckDocumentation(patched, "MsBasic.StringGarbageCollection.asm");
    }

    private static AssemblyResult AppleLegacy(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), model);

    private static AssemblyResult PetLegacy(PetModel model, bool original) =>
        PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);

    private static AssemblyResult VariantLegacy(int variant, bool original) => variant switch
    {
        0 => AppleLegacy(Apple2Model.IIeEnhanced),
        1 => PetLegacy(PetModel.Pet2001, original),
        2 => PetLegacy(PetModel.Pet2001Basic2, original),
        4 => PetLegacy(PetModel.Pet4032, original),
        _ => throw new ArgumentOutOfRangeException(nameof(variant))
    };

    private static AssemblyResult AssembleStringEntry(AssemblyResult legacy)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StringConversion.asm"
            .org ${legacy.Symbol("STR"):X4}
                STRING_FROM_NUMBER
            STRING_ENTRY_END:
            """;

        string[] dependencies =
        [
            "CHKNUM", "FOUTC", "STRLIT", "LOFBUF", "FAC", "FACEXP", "FACSGN", "VALTYP", "FACMO", "FACLO"
        ];

        return Assemble(legacy, source, Path.Join(folder, "StringEntryTest.asm"), dependencies);
    }

    private static void CheckStringEntryParity(AssemblyResult legacy, AssemblyResult? native = null)
    {
        int start = Address(legacy, "STR");
        int end = Address(legacy, "STRINI");
        AssemblyResult region = AssembleStringEntry(legacy);
        CompareRegion(legacy, region, start, end);
        AssertSpan(region, start, end);
        region.Symbol("STRING_ENTRY_END").Should().Be(end);
        if (native is not null) { CompareRegion(legacy, native, start, end); }
    }

    private static AssemblyResult AssembleClassic(
        AssemblyResult legacy, bool fullPointer, bool patchedArray, bool subtractOffset)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StringGarbageCollection.asm"
            .org ${legacy.Symbol("GARBA2"):X4}
                STRING_GARBAGE_COLLECTION {(fullPointer ? 1 : 0)}, {(patchedArray ? 1 : 0)}, {(subtractOffset ? 1 : 0)}
            COLLECTOR_END:
            """;

        string[] dependencies =
        [
            "MEMSIZ", "FRETOP", "STREND", "GRBPNT", "GRBTOP", "TEMPST", "TEMPPT", "INDEX",
            "VARTAB", "ARYTAB", "ARYPNT", "FOUR6", "ADDPRC", "INTPRC", "STRSIZ", "SIZE",
            "HIGHTR", "HIGHDS", "BLTUC"
        ];

        if (patchedArray) { dependencies = [.. dependencies, "ARYINC"]; }

        return Assemble(legacy, source, Path.Join(folder, "GarbageCollectionTest.asm"), dependencies);
    }

    private static AssemblyResult AssembleLinked(AssemblyResult legacy)
    {
        string folder = Path.Join(Inputs, "Pet", "Basic");
        string source = $"""
            .cpu Mos6502
            .include "Commodore.StringGarbageCollection.asm"
            .org ${legacy.Symbol("GARBA2"):X4}
                LINKED_STRING_GARBAGE_COLLECTION
            COLLECTOR_END:
            """;

        string[] dependencies = ["MEMSIZ", "FRETOP", "FRESPC", "HIGHDS", "GRBTOP", "GRBPNT", "INDEX"];
        return Assemble(legacy, source, Path.Join(folder, "LinkedGarbageCollectionTest.asm"), dependencies);
    }

    private static AssemblyResult AssembleClassicWithPetWorkspace(AssemblyResult legacy, bool early)
    {
        string folder = Path.Join(Inputs, "Pet", "Basic");
        string options = PetWorkspaceOptions(early, linked: false);

        string source = $"""
            .cpu Mos6502
            {options}
            .include "Commodore.Equates.asm"
            .include <MsBasic.StringGarbageCollection.asm>
            .org ${legacy.Symbol("GARBA2"):X4}
                STRING_GARBAGE_COLLECTION {(early ? 0 : 1)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}
            COLLECTOR_END:
            """;

        string[] dependencies = early ? ["BLTUC", "ARYINC"] : ["BLTUC"];
        return Assemble(legacy, source, Path.Join(folder, "PetClassicCollectorTest.asm"), dependencies);
    }

    private static void CheckPetStringSlice(AssemblyResult legacy, bool early, bool linked)
    {
        string folder = Path.Join(Inputs, "Pet", "Basic");
        string options = PetWorkspaceOptions(early, linked);
        string linkedSource = linked ? ".include \"Commodore.StringGarbageCollection.asm\"" : "";
        string collector = linked
            ? "LINKED_STRING_GARBAGE_COLLECTION"
            : $"STRING_GARBAGE_COLLECTION {(early ? 0 : 1)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}";

        string source = $"""
            .cpu Mos6502
            {options}
            .include "Commodore.Equates.asm"
            .include <MsBasic.StringConversion.asm>
            .include <MsBasic.StringStorage.asm>
            .include <MsBasic.StringGarbageCollection.asm>
            {linkedSource}
            .org ${legacy.Symbol("STR"):X4}
                STRING_FROM_NUMBER
                STRING_STORAGE BUFPAG, {(early ? 0 : 1)}
                STRING_ALLOCATION {(linked ? 1 : 0)}
                {collector}
            STRING_SLICE_END:
            """;

        string[] dependencies = ["CHKNUM", "FOUTC", "ERROR", "ERRST", "ERROM", "MOVSTR"];
        if (!linked) { dependencies = [.. dependencies, "BLTUC"]; }
        if (early) { dependencies = [.. dependencies, "ARYINC"]; }
        AssemblyResult composed = Assemble(legacy, source, Path.Join(folder, "PetStringSliceTest.asm"), dependencies);
        int start = Address(legacy, "STR");
        int end = Address(legacy, "CAT");
        CompareRegion(legacy, composed, start, end);
        AssertSpan(composed, start, end);
        composed.Symbol("STRING_SLICE_END").Should().Be(end);
    }

    private static string PetWorkspaceOptions(bool early, bool linked) => early
        ? """
            BUFPAG = 0
            BUFLEN = 80
            NULCMD = 1
            FULL_STACK_TOP = 1
            STACK_RESERVE_19 = 1
            TERMINAL_FIRST = 1
            LOCAL_TRMPOS = 1
            VARTXT_IN_LINNUM = 1
            CLOCK_IN_PAGE2 = 1
            STATUS_IN_PAGE2 = 1
            RND_TIMER_9044 = 1
            ERROR_PADDING5 = 1
            """
        : linked
            ? """
                LINE_WIDTH_STORAGE = 0
                DISK_STATUS_STRING = 1
                """
            : "";

    private static AssemblyResult AssembleLinkedWithPetWorkspace(AssemblyResult legacy, bool explicitWorkspace)
    {
        string folder = Path.Join(Inputs, "Pet", "Basic");
        string workspace = explicitWorkspace
            ? """
                LINE_WIDTH_STORAGE = 0
                DISK_STATUS_STRING = 1
                .include "Commodore.Equates.asm"
                """
            : "";

        string source = $"""
            .cpu Mos6502
            {workspace}
            .include "Commodore.StringGarbageCollection.asm"
            .org ${legacy.Symbol("GARBA2"):X4}
                LINKED_STRING_GARBAGE_COLLECTION
            COLLECTOR_END:
            """;

        return Assemble(legacy, source, Path.Join(folder, "PetLinkedCollectorTest.asm"), []);
    }

    private static AssemblyResult Assemble(AssemblyResult legacy, string source, string path, string[] dependencies)
    {
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                SdkPaths = [Path.Join(Inputs, "Microsoft6502Basic")],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, int start, int end)
    {
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
            entry.Size > 0 && entry.Operation != ".ORG" && entry.Address >= start && entry.Address < end)
            .OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            entry.Address.Should().Be(next, "the native region must not have a gap or overlap");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end, "the native region must end at the next legacy label");
    }

    private static void CheckClassicCompaction(AssemblyResult legacy, AssemblyResult region, bool shared, bool patchedArray)
    {
        RecordingBus bus = CreateClassicBus(legacy, region, shared);
        Run(bus, Address(shared ? region : legacy, "GARBA2"));
        GetWord(bus.Memory, Scalar + 3).Should().Be(0x70FA);
        GetWord(bus.Memory, ArrayDescriptor + 1).Should().Be(0x70F5);
        bus.Memory.AsSpan(0x70FA, 6).ToArray().Should().Equal("SCALAR"u8.ToArray());
        bus.Memory.AsSpan(0x70F5, 5).ToArray().Should().Equal("ARRAY"u8.ToArray());
        GetWord(bus.Memory, Scalar + 7 + 3).Should().Be(0x70C0);
        GetWord(bus.Memory, Scalar + 14 + 3).Should().Be(0x70C8);
        GetWord(bus.Memory, Scalar + 21 + 3).Should().Be(0x70B0);
        GetWord(bus.Memory, Scalar + 28 + 3).Should().Be(0x4000);
        GetWord(bus.Memory, 0x5102 + 8).Should().Be(0x70E0);
        GetWord(bus.Memory, 0x510D + 8).Should().Be(0x70E4);
        GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(0x70F5);
        if (patchedArray)
        {
            ushort patch = checked((ushort)legacy.Symbol("ARYINC"));
            bus.Accesses.Should().Contain(access => access.Address == patch && access.Operation == BusOperation.Read);
        }
    }

    private static void CheckTemporarySelection(
        AssemblyResult legacy, AssemblyResult region, bool shared, bool fullPointer, bool patchedArray)
    {
        RecordingBus bus = CreateClassicBus(legacy, region, shared);
        int temp = Address(legacy, "TEMPST");
        SetDescriptor(bus.Memory, temp, 4, 0x70E8);
        "TEMP"u8.CopyTo(bus.Memory.AsSpan(0x70E8));
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)(temp + 3);
        Run(bus, Address(shared ? region : legacy, "GARBA2"));
        GetWord(bus.Memory, temp + 1).Should().Be(fullPointer ? 0x70FC : 0x70E8);
        GetWord(bus.Memory, Scalar + 3).Should().Be(fullPointer ? 0x70F6 : 0x70D0);
        GetWord(bus.Memory, ArrayDescriptor + 1).Should().Be(fullPointer ? 0x70F1 : 0x7000);
        GetWord(bus.Memory, Address(legacy, "FRETOP")).Should().Be(fullPointer ? 0x70F1 : Top);
        bus.Memory.AsSpan(fullPointer ? 0x70FC : 0x70E8, 4).ToArray().Should().Equal("TEMP"u8.ToArray());
        if (patchedArray)
        {
            ushort patch = checked((ushort)legacy.Symbol("ARYINC"));
            bus.Accesses.Should().Contain(access => access.Address == patch && access.Operation == BusOperation.Read);
        }
    }

    private static RecordingBus CreateClassicBus(AssemblyResult legacy, AssemblyResult region, bool shared)
    {
        RecordingBus bus = CreateBus(legacy, region, shared);
        byte[] memory = bus.Memory;
        SetWord(memory, Address(legacy, "VARTAB"), Scalar);
        SetWord(memory, Address(legacy, "ARYTAB"), Array);
        SetWord(memory, Address(legacy, "STREND"), 0x5119);
        SetWord(memory, Address(legacy, "MEMSIZ"), Top);
        SetWord(memory, Address(legacy, "FRETOP"), 0x7000);
        SetWord(memory, Address(legacy, "GRBPNT"), 0x7FA5);
        memory[Address(legacy, "TEMPPT")] = (byte)Address(legacy, "TEMPST");
        memory[Address(legacy, "FOUR6")] = 3;
        SetVariable(memory, Scalar, (byte)'A', 0x80, 6, 0x70D0);
        SetVariable(memory, Scalar + 7, (byte)'B', 0x00, 2, 0x70C0);
        SetVariable(memory, Scalar + 14, 0xC3, 0x80, 3, 0x70C8);
        SetVariable(memory, Scalar + 21, (byte)'D', 0x80, 0, 0x70B0);
        SetVariable(memory, Scalar + 28, (byte)'E', 0x80, 3, 0x4000);
        SetArray(memory, Array, (byte)'F', 0x80, 10);
        SetDescriptor(memory, ArrayDescriptor, 5, 0x7000);
        SetArray(memory, 0x5102, 0xC7, 0x80, 11);
        SetDescriptor(memory, 0x5102 + 7, 3, 0x70E0);
        SetArray(memory, 0x510D, (byte)'H', 0x00, 12);
        SetDescriptor(memory, 0x510D + 7, 3, 0x70E4);
        "SCALAR"u8.CopyTo(memory.AsSpan(0x70D0));
        "ARRAY"u8.CopyTo(memory.AsSpan(0x7000));
        "TXT"u8.CopyTo(memory.AsSpan(0x4000));
        return bus;
    }

    private static RecordingBus CreateStringEntryBus(AssemblyResult legacy, AssemblyResult region, bool shared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (shared)
        {
            int start = Address(region, "STR");
            int end = Address(region, "STRING_ENTRY_END");
            region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        int temp = Address(legacy, "TEMPST");
        bus.Memory[Address(legacy, "TEMPPT")] = (byte)temp;
        SetWord(bus.Memory, Address(legacy, "LASTPT"), temp - 3);
        SetWord(bus.Memory, Address(legacy, "STREND"), 0x5000);
        SetWord(bus.Memory, Address(legacy, "MEMSIZ"), 0x7000);
        SetWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        return bus;
    }

    private static void CheckTemporaryString(byte[] memory, AssemblyResult legacy, byte[] expected)
    {
        int descriptor = GetWord(memory, Address(legacy, "FACMO"));
        descriptor.Should().Be(Address(legacy, "TEMPST"));
        memory[descriptor].Should().Be((byte)expected.Length);
        int text = GetWord(memory, descriptor + 1);
        memory.AsSpan(text, expected.Length).ToArray().Should().Equal(expected);
        memory[Address(legacy, "VALTYP")].Should().Be(0xFF);
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult region, bool shared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (shared)
        {
            int start = Address(region, "GARBA2");
            int end = Address(region, "COLLECTOR_END");
            region.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        return bus;
    }

    private static void SetVariable(byte[] memory, int address, byte first, byte second, byte length, int data)
    {
        memory[address] = first;
        memory[address + 1] = second;
        SetDescriptor(memory, address + 2, length, data);
    }

    private static void SetArray(byte[] memory, int address, byte first, byte second, byte size)
    {
        memory[address] = first;
        memory[address + 1] = second;
        memory[address + 2] = size;
        memory[address + 3] = 0;
        memory[address + 4] = 1;
        memory[address + 5] = 0;
        memory[address + 6] = 1;
    }

    private static void SetDescriptor(byte[] memory, int descriptor, byte length, int data)
    {
        memory[descriptor] = length;
        SetWord(memory, descriptor + 1, data);
    }

    private static void AppendLive(byte[] memory, ref int cursor, int descriptor, byte[] text)
    {
        cursor -= 2;
        SetWord(memory, cursor, descriptor);
        cursor -= text.Length;
        text.CopyTo(memory, cursor);
        SetDescriptor(memory, descriptor, checked((byte)text.Length), cursor);
    }

    private static void AppendGarbage(byte[] memory, ref int cursor, int length)
    {
        cursor -= 2;
        memory[cursor] = checked((byte)length);
        memory[cursor + 1] = 0xFF;
        cursor -= length;
        memory.AsSpan(cursor, length).Fill(0xCC);
    }

    private static void CheckLinkedString(byte[] memory, int descriptor, int address, byte[] expected)
    {
        memory[descriptor].Should().Be((byte)expected.Length);
        GetWord(memory, descriptor + 1).Should().Be(address);
        memory.AsSpan(address, expected.Length).ToArray().Should().Equal(expected);
        GetWord(memory, address + expected.Length).Should().Be(descriptor);
    }

    private static Processor<RecordingBus> Run(RecordingBus bus, int address, byte accumulator = 0)
    {
        SetWord(bus.Memory, 0x01FE, ReturnAddress - 1);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)address),
                StackPointer = 0xFD,
                Accumulator = accumulator,
                X = 0x5A,
                Y = 0,
                Status = StatusRegister.Unused
            }
        };

        StepToReturn(cpu);
        return cpu;
    }

    private static void StepToReturn(Processor<RecordingBus> cpu) => StepTo(cpu, ReturnAddress);

    private static void StepTo(Processor<RecordingBus> cpu, ushort destination)
    {
        for (int instruction = 0; instruction < 100000 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination, "the routine must reach the expected exit");
    }

    private static void CheckDocumentation(SourceMapModule module, string file)
    {
        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) == file)];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));

    private static int GetWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void SetWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }
}
