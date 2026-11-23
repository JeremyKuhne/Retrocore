// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using LookupFeatures = (
    bool FixedVectors,
    int VectorByte,
    bool RejectAnyFlag,
    bool ExistingArrays,
    bool ClearWithY,
    bool LongFound,
    bool CheckCallerHigh,
    bool InlineZero,
    bool UseSimzer,
    bool ClockNames,
    bool StatusName,
    bool DiskNames,
    bool LinkedArrays,
    bool ArrayEntryAlias,
    bool NumericEvaluator,
    bool CheckType);

namespace Retrocore.Tests;

/// <summary>
///  Checks shared variable-name parsing and scalar lookup against the AppleSoft and PET overlays.
/// </summary>
[TestClass]
public sealed class BasicSharedVariableLookupTests
{
    private const int Apple = 0;
    private const int Pet1 = 1;
    private const int Pet2 = 2;
    private const int Pet4 = 4;
    private const int TextAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  The complete AppleSoft image, all labels and the extracted span retain their legacy values.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedVariableLookup(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        LookupFeatures features = Settings(Apple, model == Apple2Model.IIeEnhanced ? 0xC4 : 0);
        AssemblyResult standalone = AssembleRegion(legacy, features);

        native.Sections[0].Bytes.ToArray().Should().Equal(legacy.Sections[0].Bytes.ToArray());
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        AssertEmittedSpan(legacy, standalone);
        byte[] vectors =
        [
            0x4C, (byte)legacy.Symbol("INIT"), (byte)(legacy.Symbol("INIT") >> 8),
            0x4C, (byte)legacy.Symbol("MAIN"), (byte)(legacy.Symbol("MAIN") >> 8),
            (byte)features.VectorByte
        ];

        native.Sections[0].Bytes.Slice(0xE000, vectors.Length).ToArray().Should().Equal(vectors);
        native.Symbol("PTRGT4").Should().Be(0xE007);
        native.Definition("PTRGET").Location?.Path
            .Should().EndWith("MsBasic.VariableLookup.asm");
    }

    /// <summary>
    ///  Every PET revision matches the entire promoted span and all of its legacy labels.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedVariableLookupMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        int variant = model == PetModel.Pet2001 ? Pet1 : model == PetModel.Pet2001Basic2 ? Pet2 : Pet4;
        AssemblyResult native = AssembleRegion(legacy, Settings(variant));
        CompareRegion(legacy, native);
        AssertEmittedSpan(legacy, native);
        AssemblyResult withWorkspace = AssembleRegion(legacy, Settings(variant), nativePet: variant);
        CompareRegion(legacy, withWorkspace);
        AssertEmittedSpan(legacy, withWorkspace);
        withWorkspace.Definition("VARNAM").Location?.Path
            .Should().EndWith("Commodore.Equates.asm");

        if (variant == Pet1)
        {
            native.Symbol("ZERO").Should().Be(native.Symbol("LDZR") + 5);
        }
        else
        {
            native.Symbol("ZERO").Should().Be(legacy.Symbol("FHALF") + 2);
        }

        SourceMapModule module = new(native, area: null);
        if (variant == Pet1)
        {
            DocumentationTopic topic = module.Documentation.FindTopic("ZERO")
                ?? throw new AssertFailedException("BASIC 1's inline zero is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Table);
        }

        if (variant == Pet4)
        {
            DocumentationTopic topic = module.Documentation.FindTopic("ARYVA2")
                ?? throw new AssertFailedException("The linked-array fixup is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.VariableLookup.asm");
        }

        DocumentationResolver resolver = new(
            module.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) == "MsBasic.VariableLookup.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    /// <summary>
    ///  The shared routines have editor-clean documentation and debugger locations in their original caller.
    /// </summary>
    [TestMethod]
    public void SharedEntriesRetainDocumentationAndEditorSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);

        int start = Address(native, "PTRGET");
        int end = Address(native, "ISARY");
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["PTRGET", "NOTFNS", "LDZR", "VAROK", "FINPTR", "FMAPTR", "FMAPT1", "QINTG1"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.VariableLookup.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.VariableLookup.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.Arrays.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            string macroEntry = name == "PTRGET" ? "PTRGET" : name == "QINTG1" ? "QINTG1" : "NOTFNS";
            module.Entries(position.Chain[1].Path, position.Chain[1].Line)
                .Should().Contain(checked((ushort)native.Symbol(macroEntry)));
        }

        SourceAnalysis analysis = SourceAnalysis.Assemble(Path.Join(Inputs, "AppleSoft", "AppleSoft.asm"), _ => null);
        DocumentationResolver resolver = new(
            analysis.Documentation,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> problems = [.. resolver.Check().Where(problem =>
            Path.GetFileName(problem.Path) is "MsBasic.VariableLookup.asm" or "AppleSoft.Arrays.asm")];

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    /// <summary>
    ///  PET compares only the caller's low return-address byte; AppleSoft also checks the high byte.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void MissingScalarCallerCheckPreservesEachVariantsBehavior(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        LookupFeatures features = Settings(variant, variant == Apple ? 0xC4 : 0);
        AssemblyResult native = AssembleRegion(legacy, features);
        foreach (bool useShared in (bool[])[false, true])
        {
            foreach (bool samePage in (bool[])[false, true])
            {
                CheckCaller(legacy, native, useShared, samePage, features.CheckCallerHigh);
            }
        }
    }

    /// <summary>
    ///  The caller check, zero placement and zero label can be selected independently.
    /// </summary>
    /// <param name="checkHigh">Whether the high return-address byte is checked.</param>
    /// <param name="inlineZero">Whether the zero bytes follow LDZR.</param>
    /// <param name="useSimzer">Whether the zero is named SIMZER rather than ZERO.</param>
    [TestMethod]
    [DataRow(false, false, false)]
    [DataRow(false, true, true)]
    [DataRow(true, false, true)]
    [DataRow(true, true, false)]
    public void CallerCheckAndZeroStorageAreIndependent(bool checkHigh, bool inlineZero, bool useSimzer)
    {
        AssemblyResult legacy = Legacy(Apple);
        LookupFeatures features = Settings(Apple, 0xC4);
        features.CheckCallerHigh = checkHigh;
        features.InlineZero = inlineZero;
        features.UseSimzer = useSimzer;
        AssemblyResult native = AssembleRegion(legacy, features, externalZero: 0x6000, omitConversion: true);
        CheckCaller(legacy, native, useShared: true, samePage: false, checkHigh);
    }

    /// <summary>
    ///  The clock, channel status and disk status names have different reserved-name rules.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    [TestMethod]
    [DataRow(Apple)]
    [DataRow(Pet1)]
    [DataRow(Pet2)]
    [DataRow(Pet4)]
    public void ReservedNamesFollowTheVariant(int variant)
    {
        AssemblyResult legacy = Legacy(variant);
        LookupFeatures features = Settings(variant, variant == Apple ? 0xC4 : 0);
        AssemblyResult native = AssembleRegion(legacy, features);
        CheckNames(legacy, native, features, includeLegacy: true);
    }

    /// <summary>
    ///  Clock, channel status and disk status protection can be enabled separately.
    /// </summary>
    /// <param name="clock">Whether TI and TI$ are special.</param>
    /// <param name="status">Whether ST is protected.</param>
    /// <param name="disk">Whether DS and DS$ are protected.</param>
    [TestMethod]
    [DataRow(true, false, false)]
    [DataRow(false, true, false)]
    [DataRow(false, false, true)]
    public void ReservedNameOptionsAreIndependent(bool clock, bool status, bool disk)
    {
        AssemblyResult legacy = Legacy(Apple);
        LookupFeatures features = Settings(Apple, 0xC4);
        features.ClockNames = clock;
        features.StatusName = status;
        features.DiskNames = disk;
        features.LongFound = true;
        AssemblyResult native = AssembleRegion(legacy, features);
        CheckNames(legacy, native, features, includeLegacy: false);
    }

    /// <summary>
    ///  AppleSoft permits integer names with bit 6 set and enters its existing-array path; PET rejects them.
    /// </summary>
    /// <param name="variant">The AppleSoft or PET BASIC variant.</param>
    /// <param name="flag">The initial subscript flag.</param>
    [TestMethod]
    [DataRow(Apple, 0x01)]
    [DataRow(Apple, 0x40)]
    [DataRow(Apple, 0x80)]
    [DataRow(Pet1, 0x40)]
    [DataRow(Pet2, 0x40)]
    [DataRow(Pet4, 0x40)]
    public void IntegerNamesRespectSubscriptModes(int variant, int flag)
    {
        AssemblyResult legacy = Legacy(variant);
        LookupFeatures features = Settings(variant, variant == Apple ? 0xC4 : 0);
        AssemblyResult native = AssembleRegion(legacy, features);
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            PrepareText(bus, legacy, "A%");
            bus.Memory[Address(legacy, "SUBFLG")] = (byte)flag;
            if (variant == Apple && flag == 0x40)
            {
                ((byte[])[0xC1, 0x80, 7, 0, 1, 0, 1]).CopyTo(bus.Memory, 0x5000);
                WriteWord(bus.Memory, Address(legacy, "STREND"), 0x5007);
            }

            ushort returned = ReturnFor(legacy);
            Processor<RecordingBus> cpu = Start(bus, Address(legacy, "PTRGET"), returned - 1);
            ushort syntax = checked((ushort)legacy.Symbol("SNERR"));
            StepUntil(cpu, 5000, returned, syntax);
            bool rejected = variant != Apple || flag == 0x80;
            cpu.Registers.ProgramCounter.Should().Be(rejected ? syntax : returned);
            if (!rejected)
            {
                bus.Memory[Address(legacy, "INTFLG")].Should().Be(0x80);
                bus.Memory[Address(legacy, "VARNAM")].Should().Be(0xC1);
                bus.Memory[Address(legacy, "VARNAM") + 1].Should().Be(0x80);
                if (flag == 0x40)
                {
                    cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
                    ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(0x5000);
                }
                else
                {
                    ReadWord(bus.Memory, Address(legacy, "VARPNT")).Should().Be(0x5002);
                    bus.Memory[Address(legacy, "SUBFLG")].Should().Be(0);
                }
            }
        }
    }

    /// <summary>
    ///  Integer-name rejection and the Apple-style existing-array path are separate choices.
    /// </summary>
    /// <param name="rejectAnyFlag">Whether any nonzero subscript flag rejects integer names.</param>
    /// <param name="existingArrays">Whether bit 6 requests an existing-array lookup.</param>
    [TestMethod]
    [DataRow(false, false)]
    [DataRow(false, true)]
    [DataRow(true, false)]
    [DataRow(true, true)]
    public void IntegerRestrictionAndExistingArrayModeAreIndependent(bool rejectAnyFlag, bool existingArrays)
    {
        AssemblyResult legacy = Legacy(Apple);
        LookupFeatures features = Settings(Apple, 0xC4);
        features.RejectAnyFlag = rejectAnyFlag;
        features.ExistingArrays = existingArrays;
        AssemblyResult native = AssembleRegion(legacy, features, omitConversion: true);
        foreach (bool integerName in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared: true);
            PrepareText(bus, legacy, integerName ? "A%" : "A");
            bus.Memory[Address(legacy, "SUBFLG")] = 0x40;
            byte first = integerName ? (byte)0xC1 : (byte)'A';
            byte second = integerName ? (byte)0x80 : (byte)0;
            ((byte[])[first, second, 7, 0, 1, 0, 1]).CopyTo(bus.Memory, 0x5000);
            WriteWord(bus.Memory, Address(legacy, "STREND"), 0x5007);
            ushort returned = ReturnFor(legacy);
            ushort syntax = checked((ushort)legacy.Symbol("SNERR"));
            Processor<RecordingBus> cpu = Start(bus, Address(native, "PTRGET"), returned - 1);
            StepUntil(cpu, 5000, returned, syntax);
            bool rejected = integerName && rejectAnyFlag;
            cpu.Registers.ProgramCounter.Should().Be(rejected ? syntax : returned);
            if (rejected) { continue; }
            if (existingArrays)
            {
                cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
                ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(0x5000);
            }
            else
            {
                ReadWord(bus.Memory, Address(legacy, "VARPNT")).Should().Be(0x5002);
                ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(0x5007);
            }
        }
    }

    /// <summary>
    ///  AppleSoft's existing-array mode returns carry set or reports OUT OF DATA without making an array.
    /// </summary>
    /// <param name="exists">Whether the named array exists.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void AppleExistingArrayModeFindsOrRejectsAnArray(bool exists)
    {
        AssemblyResult legacy = Legacy(Apple);
        AssemblyResult native = AssembleRegion(legacy, Settings(Apple, 0xC4));
        foreach (bool useShared in (bool[])[false, true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            PrepareText(bus, legacy, "A%");
            bus.Memory[Address(legacy, "SUBFLG")] = 0x40;
            if (exists)
            {
                ((byte[])[0xC1, 0x80, 7, 0, 1, 0, 1]).CopyTo(bus.Memory, 0x5000);
                WriteWord(bus.Memory, Address(legacy, "STREND"), 0x5007);
            }

            ushort returned = ReturnFor(legacy);
            ushort error = checked((ushort)legacy.Symbol("ERROR"));
            Processor<RecordingBus> cpu = Start(bus, Address(legacy, "PTRGET"), returned - 1);
            StepUntil(cpu, 5000, returned, error);
            cpu.Registers.ProgramCounter.Should().Be(exists ? returned : error);
            if (exists)
            {
                cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
            }
            else
            {
                cpu.Registers.X.Should().Be((byte)legacy.Symbol("ERROD"));
            }

            ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(0x5000);
            ReadWord(bus.Memory, Address(legacy, "STREND")).Should().Be(exists ? 0x5007 : 0x5000);
        }
    }

    /// <summary>
    ///  BASIC 4 fixes live string-array back-links after a scalar insertion; BASIC 2 does not use them.
    /// </summary>
    /// <param name="variant">The PET BASIC variant.</param>
    /// <param name="original">Whether to use BASIC 4's original chip.</param>
    [TestMethod]
    [DataRow(Pet2, false)]
    [DataRow(Pet4, false)]
    [DataRow(Pet4, true)]
    public void InsertingScalarAdjustsOnlyLinkedStringArrays(int variant, bool original)
    {
        AssemblyResult legacy = Legacy(variant, original);
        AssemblyResult native = AssembleRegion(legacy, Settings(variant));
        CheckArrayMoves(legacy, native, linked: variant == Pet4, includeLegacy: true);
    }

    /// <summary>
    ///  Disk-status protection and linked-string array relocation can be selected independently.
    /// </summary>
    /// <param name="disk">Whether DS and DS$ are protected.</param>
    /// <param name="linked">Whether moved string arrays have back-links.</param>
    [TestMethod]
    [DataRow(false, true)]
    [DataRow(true, false)]
    public void DiskNamesAndStringRelocationAreIndependent(bool disk, bool linked)
    {
        AssemblyResult legacy = Legacy(Pet2);
        LookupFeatures features = Settings(Pet2);
        features.DiskNames = disk;
        features.LinkedArrays = linked;
        features.LongFound = true;
        AssemblyResult native = AssembleRegion(legacy, features, omitConversion: true);
        CheckNames(legacy, native, features, includeLegacy: false);
        CheckArrayMoves(legacy, native, linked, includeLegacy: false);
    }

    private static void CheckArrayMoves(
        AssemblyResult legacy, AssemblyResult native, bool linked, bool includeLegacy)
    {
        foreach (bool useShared in includeLegacy ? (bool[])[false, true] : [true])
        {
            RecordingBus bus = CreateBus(legacy, native, useShared);
            PrepareText(bus, legacy, "V");
            byte[] arrays =
            [
                (byte)'A', (byte)('B' | 0x80), 19, 0, 1, 0, 4,
                5, 0xFA, 0x60, 2, 0x00, 0x50, 0, 0x00, 0x62, 2, 0xFE, 0x5F,
                (byte)'N', (byte)'N', 12, 0, 1, 0, 1, 0, 0, 0, 0, 0,
                (byte)('I' | 0x80), (byte)('X' | 0x80), 9, 0, 1, 0, 1, 0, 0
            ];

            arrays.CopyTo(bus.Memory, 0x40F8);
            WriteWord(bus.Memory, Address(legacy, "VARTAB"), 0x40F8);
            WriteWord(bus.Memory, Address(legacy, "ARYTAB"), 0x40F8);
            WriteWord(bus.Memory, Address(legacy, "STREND"), 0x40F8 + arrays.Length);
            WriteWord(bus.Memory, Address(legacy, "FRETOP"), 0x6000);
            WriteWord(bus.Memory, 0x60FF, 0x40FF);
            WriteWord(bus.Memory, 0x5002, 0x5AA5);
            WriteWord(bus.Memory, 0x6200, 0x3412);
            WriteWord(bus.Memory, 0x6000, 0x4108);

            ushort returned = ReturnFor(legacy);
            Processor<RecordingBus> cpu = Start(bus, Address(legacy, "PTRGET"), returned - 1);
            StepUntil(cpu, 10000, returned, checked((ushort)legacy.Symbol("ERROR")));
            cpu.Registers.ProgramCounter.Should().Be(returned);
            ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(0x40FF);
            ReadWord(bus.Memory, Address(legacy, "STREND")).Should().Be(0x40FF + arrays.Length);
            ReadWord(bus.Memory, Address(legacy, "VARPNT")).Should().Be(0x40FA);
            bus.Memory.AsSpan(0x40FF, arrays.Length).ToArray().Should().Equal(arrays);
            ReadWord(bus.Memory, 0x60FF).Should().Be(linked ? 0x4106 : 0x40FF);
            ReadWord(bus.Memory, 0x5002).Should().Be(0x5AA5);
            ReadWord(bus.Memory, 0x6200).Should().Be(0x3412);
            ReadWord(bus.Memory, 0x6000).Should().Be(linked ? 0x410F : 0x4108);
        }
    }

    private static void CheckNames(AssemblyResult legacy, AssemblyResult native, LookupFeatures features, bool includeLegacy)
    {
        string[] names =
        [
            "TI", "TIMER", "TI$", "TIWORD$", "TI%", "ST", "STATUS", "ST$", "DS", "DSK",
            "DS$", "DSK$", "DS%", "D1"
        ];

        foreach (bool useShared in includeLegacy ? (bool[])[false, true] : [true])
        {
            AssemblyResult source = useShared ? native : legacy;
            foreach (string name in names)
            {
                RecordingBus bus = CreateBus(legacy, native, useShared);
                PrepareText(bus, legacy, name);
                ushort returned = ReturnFor(legacy);
                ushort syntax = checked((ushort)legacy.Symbol("SNERR"));
                Processor<RecordingBus> cpu = Start(bus, Address(source, "PTRGET"), returned - 1);
                StepUntil(cpu, 5000, returned, syntax);
                string significant = name[..2];
                bool stringType = name.EndsWith('$');
                bool integerType = name.EndsWith('%');
                bool zero = features.ClockNames && significant == "TI" && stringType;
                bool rejected = (features.ClockNames && significant == "TI" && !stringType && !integerType)
                    || (features.StatusName && significant == "ST" && !stringType && !integerType)
                    || (features.DiskNames && significant == "DS" && !integerType);

                cpu.Registers.ProgramCounter.Should().Be(rejected ? syntax : returned, name);
                ReadWord(bus.Memory, Address(legacy, "TXTPTR")).Should().Be(TextAddress + name.Length, name);
                bus.Memory[Address(legacy, "VARNAM")].Should().Be(
                    (byte)(name[0] | (integerType ? 0x80 : 0)), name);

                bus.Memory[Address(legacy, "VARNAM") + 1].Should().Be(
                    (byte)(name[1] | (integerType || stringType ? 0x80 : 0)), name);

                if (rejected) { continue; }

                int expected = zero ? Address(source, features.UseSimzer ? "SIMZER" : "ZERO") : 0x5002;
                (cpu.Registers.Accumulator | (cpu.Registers.Y << 8)).Should().Be(expected, name);
                ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(zero ? 0x5000 : 0x5007, name);
                ReadWord(bus.Memory, Address(legacy, "VARPNT")).Should().Be(zero ? 0x3333 : 0x5002, name);
            }
        }
    }

    private static void CheckCaller(
        AssemblyResult legacy, AssemblyResult native, bool useShared, bool samePage, bool checkHigh)
    {
        AssemblyResult source = useShared ? native : legacy;
        RecordingBus bus = CreateBus(legacy, native, useShared);
        int name = Address(legacy, "VARNAM");
        bus.Memory[name] = (byte)'X';
        bus.Memory[name + 1] = 0;
        int stackedReturn = Address(legacy, "ISVRET") - 1;
        if (!samePage) { stackedReturn ^= 0x0100; }
        ushort returned = (ushort)((stackedReturn + 1) & 0xFFFF);
        Processor<RecordingBus> cpu = Start(bus, Address(source, "NOTFNS"), stackedReturn);
        StepUntil(cpu, 5000, returned, checked((ushort)legacy.Symbol("SNERR")));
        cpu.Registers.ProgramCounter.Should().Be(returned);
        bool zero = samePage || !checkHigh;
        string zeroName = source.HasSymbol("SIMZER") ? "SIMZER" : "ZERO";
        int expected = zero ? Address(source, zeroName) : 0x5002;
        (cpu.Registers.Accumulator | (cpu.Registers.Y << 8)).Should().Be(expected);
        ReadWord(bus.Memory, Address(legacy, "ARYTAB")).Should().Be(zero ? 0x5000 : 0x5007);
        ReadWord(bus.Memory, Address(legacy, "VARPNT")).Should().Be(zero ? 0x3333 : 0x5002);
        if (zero)
        {
            bus.Memory[expected].Should().Be(0);
            bus.Memory[expected + 1].Should().Be(0);
        }
    }

    private static AssemblyResult Legacy(int variant, bool original = false) => variant switch
    {
        Apple => SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10), Apple2Model.IIeEnhanced),
        Pet1 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001, original),
        Pet2 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2),
        Pet4 => PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet4032, original),
        _ => throw new ArgumentOutOfRangeException(nameof(variant))
    };

    private static LookupFeatures Settings(int variant, int vectorByte = 0) => (
        FixedVectors: variant == Apple,
        VectorByte: vectorByte,
        RejectAnyFlag: variant != Apple,
        ExistingArrays: variant == Apple,
        ClearWithY: variant == Pet4,
        LongFound: variant == Pet4,
        CheckCallerHigh: variant == Apple,
        InlineZero: variant is Apple or Pet1,
        UseSimzer: variant == Apple,
        ClockNames: variant != Apple,
        StatusName: variant != Apple,
        DiskNames: variant == Pet4,
        LinkedArrays: variant == Pet4,
        ArrayEntryAlias: variant == Apple,
        NumericEvaluator: variant is Apple or Pet1,
        CheckType: variant is Pet2 or Pet4);

    private static AssemblyResult AssembleRegion(
        AssemblyResult legacy,
        LookupFeatures features,
        int? externalZero = null,
        bool omitConversion = false,
        int? nativePet = null)
    {
        string conversion = omitConversion ? "" : $"""
                INTEGER_CONVERSION_BOUNDARY
                INTEGER_CONVERSION {(features.NumericEvaluator ? "FRMNUM" : "FRMEVL")}, {Flag(features.CheckType)}
            """;

        string platform = nativePet is null ? "" : ".include \"Commodore.Equates.asm\"";
        string source = $"""
            .cpu Mos6502
            {platform}
            .include "MsBasic.VariableLookup.asm"
            .include "MsBasic.CharacterReader.asm"
            .include "MsBasic.IntegerConversion.asm"
            .org ${legacy.Symbol("PTRGET"):X4}
                VARIABLE_NAME {Flag(features.FixedVectors)}, ${features.VectorByte:X2}, {Flag(features.RejectAnyFlag)}, {Flag(features.ExistingArrays)}, {Flag(features.ClearWithY)}, {Flag(features.LongFound)}
                LETTER_TEST
                SIMPLE_VARIABLE_LOOKUP {Flag(features.CheckCallerHigh)}, {Flag(features.InlineZero)}, {Flag(features.UseSimzer)}, {Flag(features.ClockNames)}, {Flag(features.StatusName)}, {Flag(features.DiskNames)}, {Flag(features.LinkedArrays)}, {Flag(features.ArrayEntryAlias)}
            {conversion}
                {(features.ExistingArrays ? "EXISTING_ARRAY_ENTRY" : "")}
            LOOKUP_END:
            """;

        string[] dependencies =
        [
            "CHRGET", "CHRGOT", "TXTPTR", "SNERR", "DIMFLG", "VALTYP", "INTFLG", "SUBFLG", "VARNAM",
            "VARTAB", "ARYTAB", "STREND", "LOWTR", "HIGHDS", "HIGHTR", "VARPNT", "COUNT",
            "ARYPNT", "ISVRET", "ISARY", "BLTU", "INIT", "MAIN", "FRETOP", "INDEX1", "STRSIZ", "FHALF",
            "FRMNUM", "FRMEVL", "CHKNUM", "FACSGN", "FACEXP", "FCOMP", "FCERR", "QINT"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (nativePet is { } variant)
        {
            string[] workspace =
            [
                "CHRGET", "CHRGOT", "TXTPTR", "DIMFLG", "VALTYP", "INTFLG", "SUBFLG", "VARNAM",
                "VARTAB", "ARYTAB", "STREND", "LOWTR", "HIGHDS", "HIGHTR", "VARPNT", "COUNT",
                "ARYPNT", "FRETOP", "INDEX1", "STRSIZ", "FACSGN", "FACEXP"
            ];

            foreach (string name in workspace) { symbols.Remove(name); }
            bool early = variant == Pet1;
            bool disk = variant == Pet4;
            symbols.Add("BUFPAG", early ? 0 : 2);
            symbols.Add("BUFLEN", early ? 80 : 81);
            symbols.Add("NULCMD", Flag(early));
            symbols.Add("TERMINAL_FIRST", Flag(early));
            symbols.Add("FULL_STACK_TOP", Flag(early));
            symbols.Add("STACK_RESERVE_19", Flag(early));
            symbols.Add("LOCAL_TRMPOS", Flag(early));
            symbols.Add("LINE_WIDTH_STORAGE", Flag(!disk));
            symbols.Add("DISK_STATUS_STRING", Flag(disk));
            symbols.Add("VARTXT_IN_LINNUM", Flag(early));
            symbols.Add("CLOCK_IN_PAGE2", Flag(early));
            symbols.Add("STATUS_IN_PAGE2", Flag(early));
            symbols.Add("RND_TIMER_9044", Flag(early));
            symbols.Add("ERROR_PADDING5", Flag(early));
            symbols.Add("EXTENDED_DISK_VECTORS", Flag(disk));
        }

        if (features.ExistingArrays) { symbols.Add("INDLO1", legacy.Symbol("INDLO1")); }
        if (!features.InlineZero)
        {
            string name = features.UseSimzer ? "SIMZER" : "ZERO";
            symbols.Add(name, externalZero ?? legacy.Symbol(name));
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(SharedInputs, "VariableLookupTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                IncludePaths = [Path.Join(Inputs, "Pet", "Basic")],
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "PTRGET");
        int end = Address(legacy, "ISARY");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            native.Definition(label.Name).Location?.Path
                .Should().NotBe("<predefined>", $"{label.Name} must be defined by the assembled span");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }

    private static void AssertEmittedSpan(AssemblyResult legacy, AssemblyResult native)
    {
        int start = Address(legacy, "PTRGET");
        int end = Address(legacy, "ISARY");
        native.Symbol("LOOKUP_END").Should().Be(end);
        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG" && entry.Address >= start && entry.Address < end)
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the native region must not have a gap or overlap");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end);
    }

    private static RecordingBus CreateBus(AssemblyResult legacy, AssemblyResult native, bool useShared)
    {
        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        if (useShared)
        {
            int start = Address(native, "PTRGET");
            int end = Address(native, "LOOKUP_END");
            native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        }

        WriteWord(bus.Memory, Address(legacy, "VARTAB"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "ARYTAB"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "STREND"), 0x5000);
        WriteWord(bus.Memory, Address(legacy, "FRETOP"), 0x7000);
        WriteWord(bus.Memory, Address(legacy, "VARPNT"), 0x3333);
        return bus;
    }

    private static void PrepareText(RecordingBus bus, AssemblyResult legacy, string name)
    {
        bus.Memory.AsSpan(Address(legacy, "INITAT"), 24).CopyTo(bus.Memory.AsSpan(Address(legacy, "CHRGET")));
        byte[] text = Encoding.ASCII.GetBytes(name + ":\0");
        text.CopyTo(bus.Memory, TextAddress);
        WriteWord(bus.Memory, Address(legacy, "TXTPTR"), TextAddress);
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, int entry, int stackedReturn)
    {
        WriteWord(bus.Memory, 0x01FE, stackedReturn);
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)entry),
                StackPointer = 0xFD,
                X = 0x5A,
                Y = 0,
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

    private static ushort ReturnFor(AssemblyResult legacy) =>
        (byte)(Address(legacy, "ISVRET") - 1) == 0xFF ? (ushort)0x2001 : (ushort)0x2000;

    private static int Flag(bool value) => value ? 1 : 0;
    private static int Address(AssemblyResult source, string name) => checked((int)source.Symbol(name));
    private static int ReadWord(byte[] memory, int address) => memory[address] | (memory[address + 1] << 8);

    private static void WriteWord(byte[] memory, int address, int value)
    {
        memory[address] = (byte)value;
        memory[address + 1] = (byte)(value >> 8);
    }

}
