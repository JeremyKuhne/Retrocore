// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the original and revised BASIC 4 patch paths against the assembled overlays.
/// </summary>
[TestClass]
public sealed class PetBasic4RevisionTests
{
    private const ushort ReturnAddress = 0x5000;
    private static string PetInputs => Path.Join(BasicNames.Inputs, "Pet");
    private static string BasicInputs => Path.Join(PetInputs, "Basic");

    /// <summary>
    ///  The standalone status adjustment and patch area match the corresponding legacy spans and labels.
    /// </summary>
    /// <param name="original">Whether to assemble the original $B000 chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void RevisionPatchAndStringAdjustmentMatchLegacy(bool original)
    {
        AssemblyResult legacy = Legacy(original);
        AssemblyResult native = AssembleAdjustment(legacy, original);
        CompareRegion(legacy, native, checked((int)legacy.Symbol("STRADJ")), checked((int)legacy.Symbol("PRINTN")));
        CompareRegion(legacy, native, checked((int)legacy.Symbol("ISVAR") - 1), checked((int)legacy.Symbol("ISVAR1")));
        native.Symbol("ADJUSTMENT_END").Should().Be(legacy.Symbol("PRINTN"));
        native.Symbol("PATCH_END").Should().Be(legacy.Symbol("ISVAR1"));
        native.HasSymbol("ADJDS").Should().Be(!original);
        native.HasSymbol("GONEGT").Should().Be(!original);
        native.HasSymbol("INPNUL").Should().Be(!original);
    }

    /// <summary>
    ///  The revised ROM ignores a stale DS$ pointer when the status descriptor is empty.
    /// </summary>
    /// <param name="original">Whether to use the original chip.</param>
    /// <param name="statusLength">The cached disk-status length.</param>
    /// <param name="statusLow">The low byte of the cached status pointer.</param>
    /// <param name="statusHigh">The high byte of the cached status pointer.</param>
    /// <param name="expectedCarry">Whether the string's link is eligible for adjustment.</param>
    [TestMethod]
    [DataRow(true, 0, 0x00, 0x40, false)]
    [DataRow(false, 0, 0x00, 0x40, true)]
    [DataRow(true, 40, 0x00, 0x40, false)]
    [DataRow(false, 40, 0x00, 0x40, false)]
    [DataRow(true, 40, 0x01, 0x40, true)]
    [DataRow(false, 40, 0x01, 0x40, true)]
    [DataRow(true, 40, 0x00, 0x41, true)]
    [DataRow(false, 40, 0x00, 0x41, true)]
    public void StringAdjustmentDistinguishesAStaleStatusPointer(
        bool original,
        int statusLength,
        int statusLow,
        int statusHigh,
        bool expectedCarry)
    {
        AssemblyResult legacy = Legacy(original);
        AssemblyResult native = AssembleAdjustment(legacy, original);
        foreach (bool useNative in new[] { false, true })
        {
            RecordingBus bus = new();
            legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
            if (useNative)
            {
                CopyRegion(native, bus, "STRADJ", "ADJUSTMENT_END");
                CopyRegion(native, bus, checked((int)legacy.Symbol("ISVAR") - 1), checked((int)legacy.Symbol("ISVAR1")));
            }

            int index = checked((int)native.Symbol("INDEX"));
            int freeTop = checked((int)native.Symbol("FRETOP"));
            int status = checked((int)native.Symbol("DSDESC"));
            bus.Memory[index] = 0x00;
            bus.Memory[index + 1] = 0x06;
            bus.Memory[0x0600] = 4;
            bus.Memory[0x0601] = 0x00;
            bus.Memory[0x0602] = 0x40;
            bus.Memory[freeTop] = 0x00;
            bus.Memory[freeTop + 1] = 0x30;
            bus.Memory[status] = (byte)statusLength;
            bus.Memory[status + 1] = (byte)statusLow;
            bus.Memory[status + 2] = (byte)statusHigh;
            Processor<RecordingBus> cpu = Start(bus, native, "STRADJ");
            RunUntil(cpu, ReturnAddress, 100);
            cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(expectedCarry,
                useNative ? "native" : "legacy");

            int result = bus.Memory[index] | (bus.Memory[index + 1] << 8);
            result.Should().Be(expectedCarry ? 0x4004 : 0x0600);
            if (expectedCarry) { cpu.Registers.X.Should().Be(4); }
        }
    }

    /// <summary>
    ///  The revised ROM accepts an empty file INPUT at EOF; the original retries it.
    /// </summary>
    /// <param name="original">Whether to use the original chip.</param>
    /// <param name="channel">The selected logical channel.</param>
    /// <param name="status">The kernal status byte.</param>
    /// <param name="destination">The entry reached for the blank input line.</param>
    [TestMethod]
    [DataRow(true, 0, 0x40, "INPSTP")]
    [DataRow(false, 0, 0x40, "INPSTP")]
    [DataRow(true, 1, 0x00, "GETAGN")]
    [DataRow(false, 1, 0x00, "GETAGN")]
    [DataRow(true, 1, 0x40, "GETAGN")]
    [DataRow(false, 1, 0x40, "INPCON")]
    public void BlankInputRetainsTheRevisionSpecificEofBehavior(bool original, int channel, int status, string destination)
    {
        AssemblyResult legacy = Legacy(original);
        AssemblyResult native = AssembleInput(legacy, original);
        CompareRegion(legacy, native, checked((int)legacy.Symbol("INPUT")), checked((int)legacy.Symbol("READ")));
        foreach (bool useNative in new[] { false, true })
        {
            RecordingBus bus = new();
            legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
            if (useNative)
            {
                CopyRegion(native, bus, "INPUT", "INPUT_END");
                CopyRegion(native, bus, checked((int)legacy.Symbol("ISVAR") - 1), checked((int)legacy.Symbol("ISVAR1")));
            }

            bus.Memory[checked((int)native.Symbol("BUF"))] = 0;
            bus.Memory[checked((int)native.Symbol("CHANNL"))] = (byte)channel;
            bus.Memory[checked((int)native.Symbol("CQSTAT"))] = (byte)status;
            Processor<RecordingBus> cpu = Start(bus, native, "BUFFUL");
            RunUntil(cpu, checked((ushort)native.Symbol(destination)), 30);
        }
    }

    private static AssemblyResult Legacy(bool original) =>
        PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032, original);

    private static AssemblyResult AssembleAdjustment(AssemblyResult legacy, bool original)
    {
        string source = $"""
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.StringAssignment.asm"
            .include "Commodore.Basic4Patches.asm"
            .org ${legacy.Symbol("STRADJ"):X4}
                STRING_LINK_ADJUST {(original ? 0 : 1)}
            ADJUSTMENT_END:
            .org ${legacy.Symbol("ISVAR") - 1:X4}
                COMMODORE_BASIC4_OPERAND_SPLIT {(original ? 0 : 1)}
            PATCH_END:
            """;

        return Assemble(legacy, source, ["ROMLOC", "ISVAR1", "SNERR", "INPSTP", "GETAGN", "INPCON"]);
    }

    private static AssemblyResult AssembleInput(AssemblyResult legacy, bool original)
    {
        string source = $"""
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.ChannelInput.asm"
            .include "Commodore.Basic4Patches.asm"
            .org ${legacy.Symbol("INPUT"):X4}
                COMMODORE_INPUT_STATEMENT 0, 3, {(original ? 0 : 1)}, 0, 1
            INPUT_END:
            .org ${legacy.Symbol("ISVAR") - 1:X4}
                COMMODORE_BASIC4_OPERAND_SPLIT {(original ? 0 : 1)}
            PATCH_END:
            """;

        return Assemble(legacy, source,
        [
            "ERRDIR", "STRTXT", "SYNCHR", "STRPRT", "IODONE", "DATA", "INPCON", "OUTQST",
            "OUTSPC", "INLIN", "STPEND", "ISVAR1", "ADJDS1", "ADJ02", "SNERR"
        ]);
    }

    private static AssemblyResult Assemble(AssemblyResult legacy, string source, string[] dependencies)
    {
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        symbols.Add("DISK_STATUS_STRING", 1);
        symbols.Add("LINE_WIDTH_STORAGE", 0);
        symbols.Add("EXTENDED_DISK_VECTORS", 1);
        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "Basic4RevisionTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, int start, int end)
    {
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int firstDifference = actual.CommonPrefixLength(expected);
        firstDifference.Should().Be(expected.Length, $"the first different byte is at ${start + firstDifference:X4}");

        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG" && entry.Address >= start && entry.Address < end)
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the native region must not have gaps or overlaps");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end);
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            AssemblySymbol nativeLabel = native.FindDefinition(label.Name)
                ?? throw new AssertFailedException($"The native module does not define {label.Name}.");

            nativeLabel.Value.Should().Be(label.Value);
            AssemblyLocation location = nativeLabel.Location
                ?? throw new AssertFailedException($"{label.Name} needs a physical definition.");

            location.Path.Should().NotBe("<predefined>");
        }
    }

    private static void CopyRegion(AssemblyResult native, RecordingBus bus, string start, string end) =>
        CopyRegion(native, bus, checked((int)native.Symbol(start)), checked((int)native.Symbol(end)));

    private static void CopyRegion(AssemblyResult native, RecordingBus bus, int start, int end) =>
        native.Sections[0].Bytes.Span.Slice(start, end - start).CopyTo(bus.Memory.AsSpan(start));

    private static Processor<RecordingBus> Start(RecordingBus bus, AssemblyResult native, string entry)
    {
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        return new Processor<RecordingBus>(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol(entry)),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused | StatusRegister.Carry
            }
        };
    }

    private static void RunUntil(Processor<RecordingBus> cpu, ushort destination, int limit)
    {
        for (int instruction = 0; instruction < limit && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
    }
}
