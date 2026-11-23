// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Checks independently selectable BASIC 1 behaviors in the composed native root.
/// </summary>
[TestClass]
public sealed class Basic1IndependentSwitchTests
{
    private const ushort ReturnAddress = 0x3000;
    private static string Inputs => BasicNames.Inputs;
    private static string RootPath => Path.Join(Inputs, "Pet", "Basic", "Basic1.asm");
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  RETURN's search byte and the decimal-output threshold can be changed independently of each other and
    ///  of the selected chip revision.
    /// </summary>
    /// <param name="original">Whether to use the original chip revision.</param>
    /// <param name="searchLow">Whether RETURN changes the low FOR-pointer byte.</param>
    /// <param name="precise">Whether to use the earlier decimal-output threshold.</param>
    [TestMethod]
    [DataRow(false, 1, 1)]
    [DataRow(false, 0, 1)]
    [DataRow(false, 1, 0)]
    [DataRow(false, 0, 0)]
    [DataRow(true, 0, 0)]
    public void ReturnAndOutputThresholdAreIndependent(bool original, int searchLow, int precise)
    {
        AssemblyResult image = RequireSuccess(Assemble(new()
        {
            ["REVISD"] = original ? 0 : 1,
            ["RETURN_LOW_FOR_POINTER"] = searchLow,
            ["PRECISE_OUTPUT_LIMIT"] = precise
        }));

        RecordingBus bus = BusFor(image);
        int pointer = checked((int)image.Symbol("FORPNT"));
        bus.Memory[pointer] = 0x11;
        bus.Memory[pointer + 1] = 0x22;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)(image.Symbol("RETURN") + 2)),
                Status = StatusRegister.Unused
            }
        };

        cpu.StepInstruction();
        cpu.StepInstruction();
        bus.Memory[pointer].Should().Be(searchLow == 1 ? (byte)0xFF : (byte)0x11);
        bus.Memory[pointer + 1].Should().Be(searchLow == 1 ? (byte)0x22 : (byte)0xFF);
        int threshold = checked((int)image.Symbol("NZ9999"));
        bus.Memory[threshold + 4].Should().Be(precise == 1 ? (byte)0xFE : (byte)0xFD);
    }

    /// <summary>
    ///  Removing the ROM guard and replacing it with padding preserves the root's layout but changes PEEK behavior.
    /// </summary>
    /// <param name="guard">Whether to reject reads from protected ROM.</param>
    /// <param name="padding">Whether to replace the guard's bytes with padding.</param>
    /// <param name="value">The byte returned to the numeric conversion routine.</param>
    [TestMethod]
    [DataRow(1, 0, 0)]
    [DataRow(0, 1, 0x42)]
    public void PeekGuardAndPaddingAreIndependent(int guard, int padding, int value)
    {
        AssemblyResult image = RequireSuccess(Assemble(new()
        {
            ["PEEK_GUARD_ROM"] = guard,
            ["PEEK_PAD_GUARD"] = padding
        }));

        RecordingBus bus = BusFor(image);
        int poker = checked((int)image.Symbol("POKER"));
        byte[] addressStub = [0xA9, 0xC0, 0xA0, 0x00, 0x84, (byte)poker, 0x85, (byte)(poker + 1), 0x60];
        addressStub.CopyTo(bus.Memory, checked((int)image.Symbol("GETADR")));
        bus.Memory[0xC000] = 0x42;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = Address(image, "PEEK"),
                StackPointer = 0xFF,
                Status = StatusRegister.Unused
            }
        };

        ushort convert = Address(image, "SNGFLT");
        RunUntil(cpu, convert);
        cpu.Registers.ProgramCounter.Should().Be(convert);
        cpu.Registers.Y.Should().Be((byte)value);
    }

    /// <summary>
    ///  The workspace's stack-reserve choice also changes the running GETSTK check.
    /// </summary>
    /// <param name="reserve19">Whether to reserve 19 rather than 23 levels.</param>
    /// <param name="enoughSpace">Whether a stack pointer between the two thresholds is accepted.</param>
    [TestMethod]
    [DataRow(1, true)]
    [DataRow(0, false)]
    public void StackReserveControlsGetstk(int reserve19, bool enoughSpace)
    {
        AssemblyResult image = RequireSuccess(Assemble(new() { ["STACK_RESERVE_19"] = reserve19 }));
        RecordingBus bus = BusFor(image);
        bus.Memory[0x013B] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x013C] = (byte)((ReturnAddress - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = Address(image, "GETSTK"),
                StackPointer = 0x3A,
                Accumulator = 0,
                Status = StatusRegister.Unused
            }
        };

        ushort error = Address(image, "OMERR");
        RunUntil(cpu, ReturnAddress, error);
        cpu.Registers.ProgramCounter.Should().Be(enoughSpace ? ReturnAddress : error);
    }

    /// <summary>
    ///  The retained NULL statement uses the independently selected incremented limit, including byte wraparound.
    /// </summary>
    /// <param name="limit">The first rejected incremented value.</param>
    /// <param name="count">The requested NULL count.</param>
    /// <param name="accepted">Whether the count is accepted.</param>
    [TestMethod]
    [DataRow(10, 8, true)]
    [DataRow(4, 2, true)]
    [DataRow(4, 3, false)]
    [DataRow(4, 255, true)]
    public void NullCountUsesTheSelectedLimit(int limit, int count, bool accepted)
    {
        AssemblyResult image = RequireSuccess(Assemble(new() { ["NULL_INCREMENT_LIMIT"] = limit }));
        RecordingBus bus = BusFor(image);
        byte[] getByteStub = [0xA2, (byte)count, 0xA9, 0x00, 0x60];
        getByteStub.CopyTo(bus.Memory, checked((int)image.Symbol("GETBYT")));
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        int nullCount = checked((int)image.Symbol("NULCNT"));
        bus.Memory[nullCount] = 0x77;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = Address(image, "NULL"),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        ushort error = Address(image, "FCERR");
        RunUntil(cpu, ReturnAddress, error);
        cpu.Registers.ProgramCounter.Should().Be(accepted ? ReturnAddress : error);
        bus.Memory[nullCount].Should().Be(accepted ? (byte)count : (byte)0x77);
    }

    /// <summary>
    ///  A length-changing choice cannot silently claim to be the fixed-layout BASIC 1 ROM.
    /// </summary>
    [TestMethod]
    public void LengthChangingChoiceIsRejectedByTheRootLayout()
    {
        AssemblyResult image = Assemble(new() { ["SHORT_MULTIPLY_ZERO"] = 0 });
        image.Success.Should().BeFalse();
        image.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains("BASIC 1's main editor spill must end at $E1E0"));
    }

    /// <summary>
    ///  Choices used directly in root conditionals are restricted to their documented values.
    /// </summary>
    [TestMethod]
    public void InvalidEvaluatorChoiceIsRejected()
    {
        AssemblyResult image = Assemble(new() { ["INTIDX_USE_FRMNUM"] = 2 });
        image.Success.Should().BeFalse();
        image.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains("INTIDX_USE_FRMNUM"));
    }

    private static AssemblyResult Assemble(Dictionary<string, long> symbols) =>
        new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(RootPath), RootPath),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new OverlayBaseResolver(SharedInputs),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        return result;
    }

    private static RecordingBus BusFor(AssemblyResult image)
    {
        RecordingBus bus = new();
        image.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        return bus;
    }

    private static ushort Address(AssemblyResult image, string name) => checked((ushort)image.Symbol(name));

    private static void RunUntil(Processor<RecordingBus> cpu, ushort target, ushort? alternate = null)
    {
        for (int instruction = 0; instruction < 100
            && cpu.Registers.ProgramCounter != target
            && cpu.Registers.ProgramCounter != alternate; instruction++)
        {
            cpu.StepInstruction();
        }
    }
}
