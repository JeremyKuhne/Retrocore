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
///  Checks shared assignment against the AppleSoft and PET ROM sources.
/// </summary>
[TestClass]
public sealed class BasicSharedAssignmentTests
{
    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  Both shared blocks retain AppleSoft's bytes and labels for every model.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedAssignment(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, standardStrings: true, longLengthError: null);
        CompareRegion(legacy, native, "LET", "INPCOM");
        CompareRegion(legacy, native, "GETSPT", "STRDON");
        CompareRegion(legacy, standalone, "LET", "INPCOM");
        CompareRegion(legacy, standalone, "GETSPT", "STRDON");
        standalone.Symbol("ASSIGNMENT_START_END").Should().Be(legacy.Symbol("INPCOM"));
        standalone.Symbol("ASSIGNMENT_STRING_END").Should().Be(legacy.Symbol("STRDON"));
    }

    /// <summary>
    ///  PET BASIC shares LET, time assignment and string selection, with BASIC 4's collector hooks.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedAssignmentMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        bool linkedStrings = model == PetModel.Pet4032;
        AssemblyResult native = AssembleShared(legacy, !linkedStrings, model == PetModel.Pet2001, !original);
        CompareRegion(legacy, native, "LET", "INPCOM");
        CompareRegion(legacy, native, "INPCOM", "GETSPT");
        CompareRegion(legacy, native, "GETSPT", "PRINTN");
        native.Symbol("ASSIGNMENT_START_END").Should().Be(legacy.Symbol("INPCOM"));
        native.Symbol("ASSIGNMENT_TIME_END").Should().Be(legacy.Symbol("GETSPT"));
        native.Symbol("ASSIGNMENT_STRING_END").Should().Be(legacy.Symbol("PRINTN"));
    }

    /// <summary>
    ///  A six-digit TI$ assignment converts hours, minutes and seconds to clock ticks.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="text">The supplied six-digit clock string.</param>
    /// <param name="ticks">The expected number of 60 Hz ticks.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "000000", 0)]
    [DataRow(PetModel.Pet2001Basic2, "010203", 223380)]
    [DataRow(PetModel.Pet4032, "235959", 5183940)]
    public void ClockAssignmentConvertsTimeToTicks(PetModel model, string text, int ticks)
    {
        (RecordingBus bus, Processor<RecordingBus> cpu, AssemblyResult native) = ClockAssignment(model, text);
        ushort complete = 0x4000;
        bus.Memory[0x01FE] = (byte)((complete - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((complete - 1) >> 8);

        for (int instruction = 0; instruction < 20000 && cpu.Registers.ProgramCounter != complete; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(complete);
        int clock = checked((int)native.Symbol("CQTIMR"));
        int actual = (bus.Memory[clock] << 16) | (bus.Memory[clock + 1] << 8) | bus.Memory[clock + 2];
        actual.Should().Be(ticks);
    }

    /// <summary>
    ///  TI$ rejects a wrong length or non-digit, including BASIC 1's direct error jump.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="text">An invalid clock string.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "12345")]
    [DataRow(PetModel.Pet2001Basic2, "12345")]
    [DataRow(PetModel.Pet4032, "12A456")]
    public void ClockAssignmentRejectsInvalidText(PetModel model, string text)
    {
        (_, Processor<RecordingBus> cpu, AssemblyResult native) = ClockAssignment(model, text);
        ushort error = checked((ushort)native.Symbol("FCERR"));
        for (int instruction = 0; instruction < 20000 && cpu.Registers.ProgramCounter != error; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(error);
    }

    /// <summary>
    ///  An ordinary string variable falls through to string assignment without touching the clock.
    /// </summary>
    /// <param name="model">The PET model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void ClockAssignmentPassesOrdinaryStringsThrough(PetModel model)
    {
        (RecordingBus bus, Processor<RecordingBus> cpu, AssemblyResult native) = ClockAssignment(model, "123456");
        int destination = checked((int)native.Symbol("FORPNT"));
        int clock = checked((int)native.Symbol("CQTIMR"));
        bus.Memory[destination + 1] ^= 0x01;
        bus.Memory[clock] = 0x12;
        bus.Memory[clock + 1] = 0x34;
        bus.Memory[clock + 2] = 0x56;
        ushort stringAssignment = checked((ushort)native.Symbol("GETSPT"));
        for (int instruction = 0; instruction < 4 && cpu.Registers.ProgramCounter != stringAssignment; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(stringAssignment);
        bus.Memory.AsSpan(clock, 3).ToArray().Should().Equal(0x12, 0x34, 0x56);
    }

    /// <summary>
    ///  The linked collector recognizes live strings and preserves each revision's disk-status check.
    /// </summary>
    /// <param name="original">Whether BASIC 4 uses the original chip.</param>
    /// <param name="address">The descriptor's character address.</param>
    /// <param name="length">The descriptor's length.</param>
    /// <param name="statusAddress">Whether this is the disk-status address.</param>
    /// <param name="statusExists">Whether the disk-status descriptor is nonempty.</param>
    /// <param name="linked">Whether the helper should return a link.</param>
    [TestMethod]
    [DataRow(false, 0x60FD, 5, false, false, true)]
    [DataRow(false, 0x5FFF, 5, false, false, false)]
    [DataRow(false, 0x60FD, 0, false, false, false)]
    [DataRow(false, 0x60FD, 5, true, true, false)]
    [DataRow(false, 0x60FD, 5, true, false, true)]
    [DataRow(true, 0x60FD, 5, true, false, false)]
    public void LinkedStringAdjustmentChecksBoundsAndDiskStatus(
        bool original,
        int address,
        int length,
        bool statusAddress,
        bool statusExists,
        bool linked)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet4032, original);
        AssemblyResult native = AssembleShared(
            legacy, standardStrings: false, longLengthError: false, patchedStatus: !original);

        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int start = checked((int)native.Symbol("GETSPT"));
        int end = checked((int)legacy.Symbol("PRINTN"));
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));

        int index = checked((int)native.Symbol("INDEX"));
        int free = checked((int)native.Symbol("FRETOP"));
        int disk = checked((int)native.Symbol("DSDESC"));
        bus.Memory[index] = 0x00;
        bus.Memory[index + 1] = 0x05;
        bus.Memory[0x0500] = (byte)length;
        bus.Memory[0x0501] = (byte)address;
        bus.Memory[0x0502] = (byte)(address >> 8);
        bus.Memory[free] = 0x00;
        bus.Memory[free + 1] = 0x60;
        bus.Memory[disk] = statusExists ? (byte)1 : (byte)0;
        int status = statusAddress ? address : 0x6200;
        bus.Memory[disk + 1] = (byte)status;
        bus.Memory[disk + 2] = (byte)(status >> 8);
        const ushort complete = 0x4000;
        bus.Memory[0x01FE] = (byte)((complete - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((complete - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("STRADJ")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != complete; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(complete);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(linked);
        int result = bus.Memory[index] | (bus.Memory[index + 1] << 8);
        result.Should().Be(linked ? address + length : 0x0500);
        if (linked)
        {
            cpu.Registers.X.Should().Be((byte)length);
            cpu.Registers.Accumulator.Should().Be((byte)(address + length));
        }
    }

    /// <summary>
    ///  Assignment copies a live disk-status string but does not treat an empty status as a match.
    /// </summary>
    /// <param name="original">Whether BASIC 4 uses the original chip.</param>
    /// <param name="statusExists">Whether the disk-status descriptor is nonempty.</param>
    /// <param name="sameAddress">Whether the source points to the status buffer.</param>
    [TestMethod]
    [DataRow(false, true, true)]
    [DataRow(true, true, true)]
    [DataRow(false, false, true)]
    [DataRow(false, true, false)]
    public void DiskStatusAssignmentCopiesOnlyAnActiveMatchingStatus(
        bool original,
        bool statusExists,
        bool sameAddress)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet4032, original);
        AssemblyResult native = AssembleShared(
            legacy, standardStrings: false, longLengthError: false, patchedStatus: !original);

        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int fac = checked((int)native.Symbol("FACMO"));
        int free = checked((int)native.Symbol("FRETOP"));
        int disk = checked((int)native.Symbol("DSDESC"));
        bus.Memory[fac] = 0x00;
        bus.Memory[fac + 1] = 0x05;
        bus.Memory[0x0500] = 5;
        bus.Memory[0x0501] = 0x00;
        bus.Memory[0x0502] = 0x60;
        bus.Memory[free] = 0x00;
        bus.Memory[free + 1] = 0x70;
        bus.Memory[disk] = statusExists ? (byte)1 : (byte)0;
        bus.Memory[disk + 1] = sameAddress ? (byte)0x00 : (byte)0x01;
        bus.Memory[disk + 2] = 0x60;
        ushort copy = checked((ushort)native.Symbol("COPY"));
        ushort direct = checked((ushort)native.Symbol("DNTCPY"));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("GETSPT")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 30
            && cpu.Registers.ProgramCounter != copy
            && cpu.Registers.ProgramCounter != direct; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(statusExists && sameAddress ? copy : direct);
    }

    /// <summary>
    ///  Assignment definitions retain documentation and breakpoint-capable shared source positions.
    /// </summary>
    [TestMethod]
    public void AssignmentKeepsDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        SourceMapModule module = new(native, area: null);
        DebugTestMemory memory = new();
        int start = checked((int)native.Symbol("LET"));
        int end = checked((int)native.Symbol("STRDON"));
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());

        foreach (string name in (string[])["LET", "QINTGR", "INPCOM", "GETSPT"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.Assignment.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain[0].Path.Should().EndWith("MsBasic.Assignment.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static (RecordingBus Bus, Processor<RecordingBus> Cpu, AssemblyResult Native) ClockAssignment(
        PetModel model,
        string text)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        AssemblyResult native = AssembleShared(
            legacy, model != PetModel.Pet4032, model == PetModel.Pet2001, patchedStatus: true);

        RecordingBus bus = new();
        legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int start = checked((int)native.Symbol("INPCOM"));
        int end = checked((int)legacy.Symbol("GETSPT"));
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));
        int index = checked((int)native.Symbol("INDEX"));
        int free = checked((int)native.Symbol("FREFAC"));

        // Supply a descriptor's text and length while using the ROM's actual math and digit routines.
        byte[] fetch =
        [
            0xA9, 0x00, 0x85, (byte)index,
            0xA9, 0x04, 0x85, (byte)(index + 1),
            0xA9, (byte)text.Length, 0x60
        ];

        fetch.CopyTo(bus.Memory, free);
        for (int offset = 0; offset < text.Length; offset++)
        {
            bus.Memory[0x0400 + offset] = (byte)text[offset];
        }

        int destination = checked((int)native.Symbol("FORPNT"));
        bus.Memory[destination + 1] = (byte)(native.Symbol("ZERO") >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = (ushort)start,
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        return (bus, cpu, native);
    }

    private static AssemblyResult AssembleShared(
        AssemblyResult legacy,
        bool standardStrings,
        bool? longLengthError,
        bool patchedStatus = false)
    {
        string clockBlock = longLengthError is { } longError
            ? $"""
                .include "Commodore.TimeAssignment.asm"
                    TimeStringAssignment {(longError ? 1 : 0)}
                ASSIGNMENT_TIME_END:
                """
            : "";

        string stringBlock = standardStrings
            ? $"""
                .org ${legacy.Symbol("GETSPT"):X4}
                    StringAssignment 0, 0
                ASSIGNMENT_STRING_END:
                """
            : $"""
                .include "Commodore.StringAssignment.asm"
                .org ${legacy.Symbol("GETSPT"):X4}
                    StringAssignment 1, 1
                    StringLinkAdjust {(patchedStatus ? 1 : 0)}
                ASSIGNMENT_STRING_END:
                """;

        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Layouts.asm"
            .include "MsBasic.Assignment.asm"
            .org ${legacy.Symbol("LET"):X4}
                AssignmentStart
            ASSIGNMENT_START_END:
            {clockBlock}
            {stringBlock}
            """;

        string[] dependencies =
        [
            "PTRGET", "FORPNT", "EQULTK", "SYNCHR", "INTFLG", "VALTYP", "FRMEVL", "CHKVAL",
            "ROUND", "AYINT", "FACMO", "FACLO", "MOVVF", "FRETOP", "VARTAB", "STRINI",
            "DSCPNT", "STRNG1", "MOVINS", "DSCTMP", "FRETMS"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (longLengthError is not null)
        {
            string[] clockDependencies =
            [
                "ZERO", "FREFAC", "FACEXP", "FACSGN", "FBUFPT", "MUL10", "MOVAF", "FINML6",
                "QINT", "FACMOH", "CQTIMR", "INDEX", "QNUM", "FCERR", "FINLOG"
            ];

            foreach (string name in clockDependencies) { symbols.Add(name, legacy.Symbol(name)); }
        }

        if (!standardStrings)
        {
            symbols.Add("DSDESC", legacy.Symbol("DSDESC"));
            symbols.Add("ROMLOC", legacy.Symbol("ROMLOC"));
            if (patchedStatus) { symbols.Add("ADJDS", legacy.Symbol("ADJDS")); }
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(SharedInputs, "SharedAssignmentTest.asm")),
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

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, string first, string after)
    {
        int start = checked((int)legacy.Symbol(first));
        int end = checked((int)legacy.Symbol(after));
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            // A vendor's alias reaches its name only in a build that includes the vendor's historical names: a
            // standalone build of the module skips it, and a whole build must have it.
            if (BasicNames.IsVendorName(label.Name) && !BasicNames.IncludesHistoricalNames(native))
            {
                continue;
            }

            // A label only the SDK's own overlays give has no historical name; its definition keeps its address.
            if (BasicNames.OverlayOnlyLabels.TryGetValue(label.Name, out string? current))
            {
                native.Symbol(current).Should().Be(label.Value, $"{label.Name}'s definition must retain its ROM address");
                continue;
            }

            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }
}
