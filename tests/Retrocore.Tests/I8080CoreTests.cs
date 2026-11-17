// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using static Retrocore.Cpu.I8080.I8080Flags;

namespace Retrocore.Tests;

/// <summary>
///  The 8080 and 8085 cores: states per instruction against the instruction-set description, bus traces,
///  interrupts, and the 8085's RIM, SIM and undocumented instructions and flags.
/// </summary>
[TestClass]
public class I8080CoreTests
{
    private const ushort Origin = 0x1000;

    /// <summary>
    ///  Every opcode takes the states the description lists, with its condition true and false.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080)]
    [DataRow(I8080Variant.I8085)]
    public void EveryOpcodeTakesItsListedStates(I8080Variant variant)
    {
        InstructionSet set = I8080Isa.Get(variant);
        for (int opcode = 0; opcode < 256; opcode++)
        {
            set.TryDecode([(byte)opcode, 0x34, 0x12], out int id).Should().BeTrue();
            IsaEncoding encoding = set.GetEncoding(id);
            foreach (bool taken in (bool[])[true, false])
            {
                (I8080Processor<Z80TestBus> cpu, _) = Create(variant, (byte)opcode, 0x34, 0x12);
                cpu.Registers = cpu.Registers with { F = FlagsFor((byte)opcode, variant, taken), SP = 0x8000 };
                ProcessorExecutionResult result = cpu.StepInstruction();
                result.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete, $"${opcode:X2}");
                int expected = taken ? encoding.CyclesTaken : encoding.Cycles;
                ((int)result.Cycles).Should().Be(expected, $"${opcode:X2} {set.MnemonicName(encoding.Mnemonic)} taken={taken}");
            }
        }
    }

    /// <summary>
    ///  Each machine cycle drives its address on T1 and moves its byte on T3; M1 decodes on T4.
    /// </summary>
    [TestMethod]
    public void BusCyclesTransferOnTheThirdState()
    {
        // MOV M,A with HL = $2000: M1 at $1000 (4 states), then a write of A to $2000 (3 states).
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8080, 0x77);
        cpu.Registers = cpu.Registers with { A = 0x5A, HL = 0x2000 };
        List<ProcessorCycle> trace = Trace(cpu, 7);
        trace.Select(cycle => cycle.Operation).Should().Equal(
            BusOperation.None, BusOperation.None, BusOperation.Read, BusOperation.None,
            BusOperation.None, BusOperation.None, BusOperation.Write);

        trace[2].Should().BeEquivalentTo(new { Address = Origin, Value = (byte)0x77, IsOpcodeFetch = true });
        trace[6].Should().BeEquivalentTo(new { Address = (ushort)0x2000, Value = (byte)0x5A, IsOpcodeFetch = false });
        bus.Memory[0x2000].Should().Be(0x5A);
        cpu.IsInstructionBoundary.Should().BeTrue();
    }

    /// <summary>
    ///  READY low holds T2, adding wait states before the transfer.
    /// </summary>
    [TestMethod]
    public void WaitStretchesTheAccess()
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, 0x00);
        cpu.StepCycle();
        cpu.Signals = I8080Signals.Wait;
        cpu.StepCycle();
        cpu.LastCycle.IsStalled.Should().BeTrue();
        cpu.StepCycle();
        cpu.LastCycle.IsStalled.Should().BeTrue();
        cpu.Signals = I8080Signals.None;
        cpu.StepCycle();
        cpu.StepCycle();
        cpu.LastCycle.IsOpcodeFetch.Should().BeTrue();
        cpu.StepCycle();
        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.CycleCount.Should().Be(6, "NOP's 4 states and 2 wait states");
    }

    /// <summary>
    ///  IN and OUT put the port number on both halves of the address bus.
    /// </summary>
    [TestMethod]
    public void PortsAreOnBothAddressHalves()
    {
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8080, 0xD3, 0x42, 0xDB, 0x17);
        bus.Inputs.Enqueue(0x99);
        cpu.Registers = cpu.Registers with { A = 0x5A };
        cpu.StepInstruction();
        cpu.StepInstruction();
        bus.Outputs.Should().Equal((0x4242, 0x5A));
        bus.InputPorts.Should().Equal(0x1717);
        cpu.Registers.A.Should().Be(0x99);
    }

    /// <summary>
    ///  An acknowledged INT runs the device's RST, pushing the address of the next instruction, and disables
    ///  interrupts; EI holds off an interrupt for one instruction.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <param name="states">The states of the acknowledged RST.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080, 11)]
    [DataRow(I8080Variant.I8085, 12)]
    public void InterruptRunsTheDevicesRestart(I8080Variant variant, int states)
    {
        // EI / NOP / NOP
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(variant, 0xFB, 0x00, 0x00);
        cpu.Registers = cpu.Registers with { SP = 0x8000 };
        cpu.InterruptData = 0xEF;
        cpu.Signals = I8080Signals.InterruptRequest;
        cpu.StepInstruction();
        cpu.Registers.InterruptEnable.Should().BeTrue();
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(Origin + 2, "the instruction after EI runs first");

        ProcessorExecutionResult result = cpu.StepInstruction();
        ((int)result.Cycles).Should().Be(states);
        cpu.Registers.PC.Should().Be(0x0028);
        cpu.Registers.InterruptEnable.Should().BeFalse();
        cpu.Registers.SP.Should().Be(0x7FFE);
        (bus.Memory[0x7FFE] | (bus.Memory[0x7FFF] << 8)).Should().Be(Origin + 2);
    }

    /// <summary>
    ///  HLT waits until an interrupt, which returns to the instruction after it.
    /// </summary>
    [TestMethod]
    public void InterruptEndsHalt()
    {
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8080, 0x76);
        cpu.Registers = cpu.Registers with { SP = 0x8000, InterruptEnable = true };
        ((int)cpu.StepInstruction().Cycles).Should().Be(7);
        cpu.IsHalted.Should().BeTrue();
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.Run(10);
        cpu.Status.Should().Be(ProcessorExecutionStatus.Waiting);

        cpu.InterruptData = 0xC7;
        cpu.Signals = I8080Signals.InterruptRequest;
        cpu.StepInstruction();
        cpu.IsHalted.Should().BeFalse();
        cpu.Registers.PC.Should().Be(0x0000);
        (bus.Memory[0x7FFE] | (bus.Memory[0x7FFF] << 8)).Should().Be(Origin + 1);
    }

    /// <summary>
    ///  A TRAP edge while halted wakes the CPU through <see cref="I8080Processor{TBus}.StepInstruction"/> alone, and
    ///  a RESET edge resets it.
    /// </summary>
    [TestMethod]
    public void HaltedStepInstructionSamplesEdges()
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, 0x76);
        cpu.Registers = cpu.Registers with { SP = 0x8000 };
        cpu.StepInstruction();
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.Signals = I8080Signals.Trap;
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        cpu.Registers.PC.Should().Be(0x0024);

        cpu.Registers = cpu.Registers with { PC = Origin };
        cpu.StepInstruction();
        cpu.IsHalted.Should().BeTrue();
        cpu.Signals = I8080Signals.Reset;
        cpu.StepInstruction();
        cpu.IsHalted.Should().BeFalse();
        cpu.Registers.PC.Should().Be(1, "reset cleared PC and the NOP at 0 ran");
    }

    /// <summary>
    ///  Registers set from outside keep only the flag bits the CPU has, so <c>PUSH PSW</c> pushes the fixed bits.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <param name="pushed">The flags PUSH PSW writes after F is set to 0 and then to $FF.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080, new byte[] { 0x02, 0xD7 })]
    [DataRow(I8080Variant.I8085, new byte[] { 0x00, 0xF7 })]
    public void RegistersKeepTheFixedFlagBits(I8080Variant variant, byte[] pushed)
    {
        // PUSH PSW / PUSH PSW
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(variant, 0xF5, 0xF5);
        cpu.Registers = cpu.Registers with { SP = 0x8000, F = 0 };
        cpu.StepInstruction();
        bus.Memory[0x7FFE].Should().Be(pushed[0]);
        cpu.Registers = cpu.Registers with { F = 0xFF };
        cpu.StepInstruction();
        bus.Memory[0x7FFC].Should().Be(pushed[1]);
    }

    /// <summary>
    ///  The 8085's TRAP is non-maskable and taken first; RIM then reads IE as TRAP found it.
    /// </summary>
    [TestMethod]
    public void TrapIsTakenEvenWithInterruptsDisabled()
    {
        // RIM at the TRAP vector. TRAP comes before an unmasked RST 5.5.
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8085, 0x00);
        bus.Memory[0x0024] = 0x20;
        cpu.Registers = cpu.Registers with { SP = 0x8000, InterruptEnable = true, InterruptMask = 0 };
        cpu.Signals = I8080Signals.Trap | I8080Signals.Restart55;
        ProcessorExecutionResult result = cpu.StepInstruction();
        ((int)result.Cycles).Should().Be(12);
        cpu.Registers.PC.Should().Be(0x0024);
        cpu.Registers.InterruptEnable.Should().BeFalse();

        cpu.StepInstruction();
        (cpu.Registers.A & 0x08).Should().Be(0x08, "RIM reads IE as it was before the TRAP");
        (cpu.Registers.A & 0x10).Should().Be(0x10, "RST 5.5 is pending");
    }

    /// <summary>
    ///  The 8085's RST 7.5, 6.5 and 5.5 interrupts are taken by priority, unless masked; RST 7.5 latches an edge.
    /// </summary>
    [TestMethod]
    public void VectoredInterruptsFollowPriorityAndMasks()
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, 0x00, 0x00);
        cpu.Registers = cpu.Registers with { SP = 0x8000, InterruptEnable = true };
        cpu.Signals = I8080Signals.Restart75;
        cpu.StepInstruction();
        cpu.Signals = I8080Signals.Restart55 | I8080Signals.Restart65;
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(Origin + 2, "reset leaves all three masked");

        // Unmask: SIM with MSE and masks 0.
        cpu.Registers = cpu.Registers with { InterruptMask = 0, InterruptEnable = true };
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(0x003C, "RST 7.5's edge was latched, and it comes first");

        cpu.Registers = cpu.Registers with { InterruptEnable = true };
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(0x0034, "RST 6.5 before RST 5.5");

        cpu.Registers = cpu.Registers with { InterruptEnable = true, InterruptMask = 2 };
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(0x002C, "RST 6.5 masked");
    }

    /// <summary>
    ///  SIM sets the masks when bit 3 enables it, clears the RST 7.5 latch with bit 4 and sets SOD when bit 6
    ///  enables it; RIM reads them back with SID.
    /// </summary>
    [TestMethod]
    public void SimAndRimRoundTrip()
    {
        // MVI A,$DD / SIM / RIM
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, 0x3E, 0xDD, 0x30, 0x20);
        cpu.Signals = I8080Signals.Restart75;
        cpu.StepInstruction();
        cpu.Signals = I8080Signals.SerialInput;
        cpu.CaptureState().Should().Match<I8080Snapshot>(snapshot => snapshot.State.PendingRestart75, "the edge latched");
        cpu.StepInstruction();
        cpu.Registers.InterruptMask.Should().Be(5);
        cpu.Registers.SerialOutput.Should().BeTrue();
        cpu.StepInstruction();
        cpu.Registers.A.Should().Be(0x85, "SID, no RST 7.5 pending after the SIM cleared it, IE off, masks 5");
    }

    /// <summary>
    ///  Flags: the 8080's fixed bits, AC after ANA, and the 8085's V and K.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <param name="opcode">An ALU opcode with an immediate.</param>
    /// <param name="a">A before.</param>
    /// <param name="operand">The immediate.</param>
    /// <param name="result">A after.</param>
    /// <param name="flags">The flags after.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080, 0xC6, 0x7F, 0x01, 0x80, S | AC | V)]
    [DataRow(I8080Variant.I8085, 0xC6, 0x7F, 0x01, 0x80, S | AC | V)]
    [DataRow(I8080Variant.I8085, 0xC6, 0x01, 0x01, 0x02, 0)]
    [DataRow(I8080Variant.I8085, 0xD6, 0x80, 0x01, 0x7F, V | K)]
    [DataRow(I8080Variant.I8080, 0xD6, 0x00, 0x01, 0xFF, S | P | CY | V)]
    [DataRow(I8080Variant.I8085, 0xD6, 0x00, 0x01, 0xFF, S | P | CY | K)]
    [DataRow(I8080Variant.I8080, 0xE6, 0x08, 0x00, 0x00, Z | P | AC | V)]
    [DataRow(I8080Variant.I8080, 0xE6, 0x01, 0x01, 0x01, V)]
    [DataRow(I8080Variant.I8085, 0xE6, 0x01, 0x01, 0x01, AC)]
    [DataRow(I8080Variant.I8085, 0xF6, 0x80, 0x00, 0x80, S | K)]
    public void ArithmeticSetsFlags(I8080Variant variant, int opcode, int a, int operand, int result, int flags)
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(variant, (byte)opcode, (byte)operand);
        cpu.Registers = cpu.Registers with { A = (byte)a, F = 0 };
        cpu.StepInstruction();
        cpu.Registers.A.Should().Be((byte)result);
        cpu.Registers.F.Should().Be((byte)flags, $"flags ${cpu.Registers.F:X2}");
    }

    /// <summary>
    ///  The 8085's V is set exactly when 8-bit arithmetic overflows the signed range, and K is V exclusive-or S, for
    ///  every A, operand and carry. This is Shirriff's silicon analysis, and what V85 computes once its sign
    ///  extension of negative operands is fixed (see the backlog).
    /// </summary>
    [TestMethod]
    public void EightBitArithmeticSetsVAndKBySignedOverflow()
    {
        // ADD B, ADC B, SUB B, SBB B and CMP B, with B as the operand.
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8085, 0x00);
        foreach (byte opcode in (byte[])[0x80, 0x88, 0x90, 0x98, 0xB8])
        {
            bool subtract = opcode >= 0x90;
            bool withCarry = opcode is 0x88 or 0x98;
            bus.Memory[Origin] = opcode;
            for (int a = 0; a < 256; a++)
            {
                for (int b = 0; b < 256; b++)
                {
                    for (int carry = 0; carry < 2; carry++)
                    {
                        cpu.Registers = cpu.Registers with { PC = Origin, A = (byte)a, B = (byte)b, F = (byte)carry };
                        cpu.StepInstruction();
                        int c = withCarry ? carry : 0;
                        int signed = subtract ? (sbyte)a - (sbyte)b - c : (sbyte)a + (sbyte)b + c;
                        int result = subtract ? a - b - c : a + b + c;
                        bool overflow = signed is < sbyte.MinValue or > sbyte.MaxValue;
                        bool negative = (result & 0x80) != 0;
                        byte f = cpu.Registers.F;
                        if (((f & V) != 0) != overflow || ((f & K) != 0) != (overflow != negative))
                        {
                            Assert.Fail($"${opcode:X2} A=${a:X2} B=${b:X2} CY={carry}: F=${f:X2}");
                        }
                    }
                }
            }
        }
    }

    /// <summary>
    ///  The 8085's undocumented flags where the references differ, as this core decides them (see the backlog): DSUB's
    ///  Z covers the whole word, RDEL's V is set when bit 15 changes, and INX, DCX, DAD and the rotates leave V and K
    ///  alone but for INX and DCX's K.
    /// </summary>
    /// <param name="opcode">The instruction.</param>
    /// <param name="hl">HL before.</param>
    /// <param name="pair">BC before, or DE for RDEL.</param>
    /// <param name="flags">F before.</param>
    /// <param name="result">HL after, or the pair for INX, DCX and RDEL, or A for a rotate (A starts at $81).</param>
    /// <param name="expected">F after.</param>
    [TestMethod]
    [DataRow(0x08, 0x0100, 0x00FF, 0x00, 0x0001, P | AC)]
    [DataRow(0x08, 0x1234, 0x1234, 0x00, 0x0000, Z | P | AC)]
    [DataRow(0x18, 0x0000, 0x7FFF, CY, 0xFFFF, V)]
    [DataRow(0x18, 0x0000, 0xFFFF, CY, 0xFFFF, CY)]
    [DataRow(0x03, 0x0000, 0x7FFF, V, 0x8000, V)]
    [DataRow(0x0B, 0x0000, 0x8000, K, 0x7FFF, 0)]
    [DataRow(0x0B, 0x0000, 0x0000, V, 0xFFFF, V | K)]
    [DataRow(0x09, 0x7FFF, 0x0001, V | K, 0x8000, V | K)]
    [DataRow(0x07, 0x0000, 0x0000, V | K, 0x0003, V | K | CY)]
    [DataRow(0x17, 0x0000, 0x0000, V | K, 0x0002, V | K | CY)]
    [DataRow(0x0F, 0x0000, 0x0000, V | K, 0x00C0, V | K | CY)]
    [DataRow(0x1F, 0x0000, 0x0000, V | K, 0x0040, V | K | CY)]
    public void UndocumentedFlagsWhereReferencesDiffer(int opcode, int hl, int pair, int flags, int result, int expected)
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, (byte)opcode);
        bool rdel = opcode == 0x18;
        cpu.Registers = cpu.Registers with
        {
            A = 0x81,
            HL = (ushort)hl,
            BC = rdel ? (ushort)0 : (ushort)pair,
            DE = rdel ? (ushort)pair : (ushort)0,
            F = (byte)flags
        };

        cpu.StepInstruction();
        I8080Registers r = cpu.Registers;
        int actual = opcode switch
        {
            0x03 or 0x0B => r.BC,
            0x18 => r.DE,
            0x07 or 0x17 or 0x0F or 0x1F => r.A,
            _ => r.HL
        };

        actual.Should().Be(result, $"${opcode:X2}");
        r.F.Should().Be((byte)expected, $"${opcode:X2} flags ${r.F:X2}");
    }

    /// <summary>
    ///  POP PSW keeps only the flag bits the CPU has.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <param name="flags">F after popping $FF.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080, 0xD7)]
    [DataRow(I8080Variant.I8085, 0xF7)]
    public void PopPswMasksTheFlags(I8080Variant variant, int flags)
    {
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(variant, 0xF1);
        bus.Memory[0x8000] = 0xFF;
        bus.Memory[0x8001] = 0x12;
        cpu.Registers = cpu.Registers with { SP = 0x8000 };
        cpu.StepInstruction();
        cpu.Registers.A.Should().Be(0x12);
        cpu.Registers.F.Should().Be((byte)flags);
    }

    /// <summary>
    ///  The 8085's K reports INX's wrap to 0 and DCX's to $FFFF, and nothing else changes.
    /// </summary>
    [TestMethod]
    public void IncrementPairSetsKOnWrap()
    {
        // INX B / DCX D / INX H
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8085, 0x03, 0x1B, 0x23);
        cpu.Registers = cpu.Registers with { BC = 0xFFFF, DE = 0x0000, HL = 0x1234, F = Z };
        cpu.StepInstruction();
        cpu.Registers.BC.Should().Be(0);
        cpu.Registers.F.Should().Be(Z | K);
        cpu.StepInstruction();
        cpu.Registers.F.Should().Be(Z | K);
        cpu.StepInstruction();
        cpu.Registers.F.Should().Be(Z);
    }

    /// <summary>
    ///  The 8085's undocumented instructions.
    /// </summary>
    [TestMethod]
    public void UndocumentedInstructionsRun()
    {
        // DSUB / ARHL / RDEL / LDHI 2 / LDSI 3 / SHLX / LHLX
        (I8080Processor<Z80TestBus> cpu, Z80TestBus bus) = Create(I8080Variant.I8085, 0x08, 0x10, 0x18, 0x28, 0x02, 0x38, 0x03, 0xD9, 0xED);
        cpu.Registers = cpu.Registers with { HL = 0x9000, BC = 0x1001, DE = 0x4000, SP = 0x7000, F = 0 };
        cpu.StepInstruction();
        cpu.Registers.HL.Should().Be(0x7FFF);
        (cpu.Registers.F & CY).Should().Be(0);
        cpu.StepInstruction();
        cpu.Registers.HL.Should().Be(0x3FFF);
        (cpu.Registers.F & CY).Should().Be(CY);
        cpu.StepInstruction();
        cpu.Registers.DE.Should().Be(0x8001, "bit 15 moves to the carry, the carry into bit 0");
        (cpu.Registers.F & (CY | V)).Should().Be(V);
        cpu.StepInstruction();
        cpu.Registers.DE.Should().Be(0x4001);
        cpu.StepInstruction();
        cpu.Registers.DE.Should().Be(0x7003);

        cpu.Registers = cpu.Registers with { HL = 0xBEEF, DE = 0x2000 };
        cpu.StepInstruction();
        bus.Memory[0x2000].Should().Be(0xEF);
        bus.Memory[0x2001].Should().Be(0xBE);
        cpu.Registers = cpu.Registers with { HL = 0 };
        cpu.StepInstruction();
        cpu.Registers.HL.Should().Be(0xBEEF);
    }

    /// <summary>
    ///  A snapshot taken mid-instruction resumes on the same states.
    /// </summary>
    [TestMethod]
    public void SnapshotsRestoreMidInstruction()
    {
        // CALL $2000
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8080, 0xCD, 0x00, 0x20);
        cpu.Registers = cpu.Registers with { SP = 0x8000 };
        cpu.Run(9);
        I8080Snapshot snapshot = cpu.CaptureState();
        List<ProcessorCycle> first = Trace(cpu, 8);
        cpu.RestoreState(snapshot);
        Trace(cpu, 8).Should().BeEquivalentTo(first);
        cpu.Registers.PC.Should().Be(0x2000);

        I8080Processor<Z80TestBus> other = new(new Z80TestBus(), I8080Variant.I8085);
        other.Invoking(processor => processor.RestoreState(snapshot)).Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  The 8080 has only RESET, INT and READY.
    /// </summary>
    [TestMethod]
    public void The8080RejectsThe8085sLines()
    {
        (I8080Processor<Z80TestBus> cpu, _) = Create(I8080Variant.I8080, 0x00);
        cpu.Invoking(processor => processor.Signals = I8080Signals.Trap).Should().Throw<ArgumentOutOfRangeException>();
    }

    private static (I8080Processor<Z80TestBus> Cpu, Z80TestBus Bus) Create(I8080Variant variant, params byte[] code)
    {
        Z80TestBus bus = new();
        code.CopyTo(bus.Memory, Origin);
        I8080Processor<Z80TestBus> cpu = new(bus, variant);
        cpu.Registers = cpu.Registers with { PC = Origin };
        return (cpu, bus);
    }

    private static List<ProcessorCycle> Trace(I8080Processor<Z80TestBus> cpu, int states)
    {
        List<ProcessorCycle> trace = [];
        for (int index = 0; index < states; index++)
        {
            cpu.StepCycle();
            trace.Add(cpu.LastCycle);
        }

        return trace;
    }

    // Flags that make an opcode's condition true or false: Jcc, Ccc and Rcc number NZ Z NC C PO PE P M by bits 3-5;
    // the 8085's JNK, JK and RSTV test K and V.
    private static byte FlagsFor(byte opcode, I8080Variant variant, bool taken)
    {
        if (variant == I8080Variant.I8085)
        {
            switch (opcode)
            {
                case 0xDD:
                    return taken ? (byte)0 : K;
                case 0xFD:
                    return taken ? K : (byte)0;
                case 0xCB:
                    return taken ? V : (byte)0;
            }
        }

        if ((opcode & 0xC0) != 0xC0 || (opcode & 7) is not (0 or 2 or 4)) { return 0; }
        int y = (opcode >> 3) & 7;
        byte flag = (y >> 1) switch
        {
            0 => Z,
            1 => CY,
            2 => P,
            _ => S
        };

        bool whenSet = (y & 1) != 0;
        return taken == whenSet ? flag : (byte)0;
    }
}
