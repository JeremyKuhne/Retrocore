// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the shared PRINT dispatch's variant-specific behavior.
/// </summary>
[TestClass]
public sealed class BasicSharedPrintTests
{
    private const ushort ReturnAddress = 0x3000;

    /// <summary>
    ///  BASIC 1 enters the SPC handler with carry set; the later versions clear it.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="carry">The carry at the handler.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    public void SpcDispatchRetainsTheVariantsCarry(PetModel model, bool carry)
    {
        string inputs = BasicNames.Inputs;
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(inputs, "Pet"), model);
        string folder = Path.Join(inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Print.asm"
            .org ${legacy.Symbol("STRDON"):X4}
                PrintItems TABER, {(carry ? 0 : 1)}, 0, 1
            """;

        string[] dependencies =
        [
            "STRPRT", "CHRGOT", "CRDO", "PRTRTS", "TABTK", "SPCTK", "TABER", "COMPRT",
            "NOTABR", "FRMEVL", "VALTYP", "FOUT", "STRLIT", "OUTSPC"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "PrintTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("PRINTC")),
                Accumulator = checked((byte)native.Symbol("SPCTK")),
                Status = StatusRegister.Unused
            }
        };

        ushort handler = checked((ushort)native.Symbol("TABER"));
        for (int instruction = 0; instruction < 10 && cpu.Registers.ProgramCounter != handler; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(handler);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(carry);
    }

    /// <summary>
    ///  The variants retain their different line-feed and NULL-padding behavior.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="channel">The selected logical channel.</param>
    /// <param name="output">The expected output bytes, in hexadecimal.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0x00, "0D0A0000")]
    [DataRow(PetModel.Pet2001, 0x01, "0D0A")]
    [DataRow(PetModel.Pet2001Basic2, 0x00, "0D0A")]
    [DataRow(PetModel.Pet4032, 0x00, "0D")]
    [DataRow(PetModel.Pet4032, 0x80, "0D0A")]
    public void NewlineUsesTheVariantsChannelRules(PetModel model, int channel, string output)
    {
        string inputs = BasicNames.Inputs;
        string folder = Path.Join(inputs, "Pet", "Basic");
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(inputs, "Pet"), model);
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        string source = $"""
            .cpu Mos6502
            .include "Commodore.ChannelPrint.asm"
            .org ${legacy.Symbol("FININL"):X4}
                COMMODORE_LINE_END {(early ? 0 : 2)}, {(early ? 1 : 0)}, {(disk ? 1 : 0)}, {(early ? 1 : 0)}
            """;

        List<string> dependencies = ["BUF", "CHANNL", "TRMPOS", "OUTDO"];
        if (early) { dependencies.Add("NULCNT"); }
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "ChannelPrintTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbol("CHANNL"))] = (byte)channel;
        if (early) { bus.Memory[checked((int)native.Symbol("NULCNT"))] = 2; }
        ushort outdo = checked((ushort)native.Symbol("OUTDO"));
        bus.Memory[outdo] = 0x60;
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("CRDO")),
                StackPointer = 0xFD,
                X = 0x55,
                Status = StatusRegister.Unused
            }
        };

        List<byte> actual = [];
        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != ReturnAddress; instruction++)
        {
            if (cpu.Registers.ProgramCounter == outdo) { actual.Add(cpu.Registers.Accumulator); }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        cpu.Registers.X.Should().Be(0x55);
        actual.Should().Equal(Convert.FromHexString(output));
    }

    /// <summary>
    ///  The early SPC loop wraps a zero count to 256; later versions emit nothing.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="count">The number of space outputs.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 256)]
    [DataRow(PetModel.Pet2001Basic2, 0)]
    [DataRow(PetModel.Pet4032, 0)]
    public void SpcZeroRetainsTheEarlyLoopBehavior(PetModel model, int count)
    {
        string inputs = BasicNames.Inputs;
        string folder = Path.Join(inputs, "Pet", "Basic");
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(inputs, "Pet"), model);
        bool early = model == PetModel.Pet2001;
        string source = $"""
            .cpu Mos6502
            .include "Commodore.ChannelPrint.asm"
            .org ${legacy.Symbol("COMPRT"):X4}
                COMMODORE_PRINT_SPACING {(early ? 1 : 0)}
            """;

        string[] dependencies =
        [
            "TRMPOS", "CLMWID", "GTBYTC", "SNERR4", "TABTK", "SPCTK", "OUTSPC", "CHRGET", "PRINTC"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "PrintSpacingTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int getByte = checked((int)native.Symbol("GTBYTC"));
        byte[] byteStub = [0xA2, 0x00, 0xA9, (byte)')', 0x60];
        byteStub.CopyTo(bus.Memory, getByte);
        int outSpace = checked((int)native.Symbol("OUTSPC"));
        byte[] spaceStub = [0xA9, 0x1D, 0x60];
        spaceStub.CopyTo(bus.Memory, outSpace);
        bus.Memory[checked((int)native.Symbol("CHRGET"))] = 0x60;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("TABER")),
                Accumulator = checked((byte)native.Symbol("SPCTK")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        ushort continuation = checked((ushort)native.Symbol("PRINTC"));
        int spaces = 0;
        for (int instruction = 0; instruction < 2_000 && cpu.Registers.ProgramCounter != continuation; instruction++)
        {
            if (cpu.Registers.ProgramCounter == outSpace) { spaces++; }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(continuation);
        spaces.Should().Be(count);
    }

    /// <summary>
    ///  Space output selects the proper channel character and honors the earlier BASICs' suppression flag.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="channel">The selected logical channel.</param>
    /// <param name="setFlagSlot">Whether bit 7 is set in the suppression flag's former storage slot.</param>
    /// <param name="output">The expected output bytes, in hexadecimal.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 1, false, "1D")]
    [DataRow(PetModel.Pet2001Basic2, 0, false, "1D")]
    [DataRow(PetModel.Pet2001Basic2, 1, false, "20")]
    [DataRow(PetModel.Pet2001Basic2, 1, true, "")]
    [DataRow(PetModel.Pet4032, 1, true, "20")]
    public void SpaceOutputUsesTheVariantsChannelAndSuppressionRules(
        PetModel model,
        int channel,
        bool setFlagSlot,
        string output)
    {
        string inputs = BasicNames.Inputs;
        string folder = Path.Join(inputs, "Pet", "Basic");
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(inputs, "Pet"), model);
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        string flagSlot = disk ? "DSDESC" : "CNTWFL";
        string source = $"""
            .cpu Mos6502
            .include "Commodore.ChannelPrint.asm"
            .org ${legacy.Symbol("OUTSPC"):X4}
                COMMODORE_CHARACTER_OUTPUT {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 0 : 1)}, {(disk ? 0 : 1)}
            """;

        List<string> dependencies = ["CHANNL", flagSlot, "TRMPOS", "OUTCH"];
        if (early) { dependencies.Add("INCTRM"); }
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "CharacterOutputTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbol("CHANNL"))] = (byte)channel;
        bus.Memory[checked((int)native.Symbol(flagSlot))] = setFlagSlot ? (byte)0x80 : (byte)0;
        if (early) { bus.Memory[checked((int)native.Symbol("INCTRM"))] = 0x60; }
        ushort outch = checked((ushort)native.Symbol("OUTCH"));
        bus.Memory[outch] = 0x60;
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("OUTSPC")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        List<byte> actual = [];
        for (int instruction = 0; instruction < 50 && cpu.Registers.ProgramCounter != ReturnAddress; instruction++)
        {
            if (cpu.Registers.ProgramCounter == outch) { actual.Add(cpu.Registers.Accumulator); }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        actual.Should().Equal(Convert.FromHexString(output));
    }
}
