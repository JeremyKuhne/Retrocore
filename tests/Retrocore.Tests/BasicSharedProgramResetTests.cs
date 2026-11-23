// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the shared execution reset and the early PET stack sequence.
/// </summary>
[TestClass]
public sealed class BasicSharedProgramResetTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Every PET stack-reset sequence returns to its caller with the stack and interpreter state reset.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void StackResetKeepsItsReturnAddress(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), model, original);
        AssemblyResult native = AssembleReset(legacy, model, original);
        int start = Address(legacy, "STKINI");
        int end = Address(legacy, "LIST");
        native.Symbols["RESET_END"].Should().Be(end);
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());

        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[Address(native, "OLDTXT") + 1] = 0x7F;
        bus.Memory[Address(native, "SUBFLG")] = 0x80;
        Processor<RecordingBus> cpu = Start(bus, native, "STKINI");
        RunToReturn(cpu);

        byte expectedStack = model == PetModel.Pet2001 ? (byte)0xFE : (byte)0xFA;
        cpu.Registers.StackPointer.Should().Be(expectedStack);
        bus.Memory[Address(native, "TEMPPT")].Should().Be((byte)native.Symbols["TEMPST"]);
        bus.Memory[Address(native, "OLDTXT") + 1].Should().Be(0);
        bus.Memory[Address(native, "SUBFLG")].Should().Be(0);
    }

    /// <summary>
    ///  The original BASIC 1 stores its return address before moving the stack pointer, exposing it to interrupts.
    /// </summary>
    [TestMethod]
    public void OriginalStackResetStoresTheReturnBeforeMovingTheStack()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001, original: true);
        AssemblyResult native = AssembleReset(legacy, PetModel.Pet2001, original: true);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        Processor<RecordingBus> cpu = Start(bus, native, "STKINI");

        for (int instruction = 0; instruction < 6; instruction++) { cpu.StepInstruction(); }

        cpu.Registers.StackPointer.Should().Be(0xFF);
        bus.Memory[0x01FD].Should().Be(0xFF);
        bus.Memory[0x01FE].Should().Be(0x3F);
        RunToReturn(cpu);
    }

    /// <summary>
    ///  The text-pointer reset carries across a page boundary when the program begins at an even page.
    /// </summary>
    [TestMethod]
    public void TextPointerStartsOneByteBeforeTheProgram()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleReset(legacy, PetModel.Pet2001Basic2, original: false);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[Address(native, "TXTTAB")] = 0x00;
        bus.Memory[Address(native, "TXTTAB") + 1] = 0x20;
        Processor<RecordingBus> cpu = Start(bus, native, "STXTPT");
        RunToReturn(cpu);

        bus.Memory[Address(native, "TXTPTR")].Should().Be(0xFF);
        bus.Memory[Address(native, "TXTPTR") + 1].Should().Be(0x1F);
    }

    /// <summary>
    ///  BASIC 1's retained NULL entry rejects nine, but its increment wraps and accepts 255.
    /// </summary>
    /// <param name="value">The byte returned by the expression parser.</param>
    /// <param name="accepted">Whether the value is stored.</param>
    [TestMethod]
    [DataRow(8, true)]
    [DataRow(9, false)]
    [DataRow(255, true)]
    public void NullCountRetainsTheIncrementWrap(int value, bool accepted)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001);
        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.ProgramReset.asm"
            .org ${legacy.Symbols["NULL"]:X4}
                NULL_STATEMENT 10
            NULL_END:
            """;

        Dictionary<string, long> symbols = [];
        foreach (string name in (string[])["GETBYT", "CONTRT", "NULCNT", "FCERR"])
        {
            symbols.Add(name, legacy.Symbols[name]);
        }

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "NullStatementTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = symbols
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        native.Symbols["NULL_END"].Should().Be(legacy.Symbols["CLEAR"]);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[Address(native, "GETBYT")] = 0x60;
        bus.Memory[Address(native, "NULCNT")] = 42;
        Processor<RecordingBus> cpu = Start(bus, native, "NULL");
        ProcessorRegisters registers = cpu.Registers;
        registers.X = (byte)value;
        registers.Status = StatusRegister.Unused | StatusRegister.Zero;
        cpu.Registers = registers;
        int destination = accepted ? 0x4000 : Address(native, "FCERR");
        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be((ushort)destination);
        bus.Memory[Address(native, "NULCNT")].Should().Be(accepted ? (byte)value : (byte)42);
    }

    private static AssemblyResult AssembleReset(AssemblyResult legacy, PetModel model, bool original)
    {
        bool early = model == PetModel.Pet2001;
        string top = early ? (original ? "$FC" : "$FE") : "$FA";
        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.ProgramReset.asm"
            .org ${legacy.Symbols["STKINI"]:X4}
                EXECUTION_RESET {(early && original ? 1 : 0)}, {(early && !original ? 1 : 0)}, {top}
            RESET_END:
            """;

        string[] dependencies = ["TEMPST", "TEMPPT", "OLDTXT", "SUBFLG", "TXTPTR", "TXTTAB", "STKEND"];
        Dictionary<string, long> symbols = [];
        foreach (string name in dependencies) { symbols.Add(name, legacy.Symbols[name]); }
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "ProgramResetTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = symbols
            });

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        return result;
    }

    private static Processor<RecordingBus> Start(RecordingBus bus, AssemblyResult result, string entry)
    {
        // RTS adds one to the saved return address.
        bus.Memory[0x01FE] = 0xFF;
        bus.Memory[0x01FF] = 0x3F;
        return new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)result.Symbols[entry]),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };
    }

    private static void RunToReturn(Processor<RecordingBus> cpu)
    {
        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != 0x4000; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(0x4000);
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbols[name]);
}
