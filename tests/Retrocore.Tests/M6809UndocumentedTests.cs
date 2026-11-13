// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6809;
using Retrocore.Perf;

namespace Retrocore.Tests;

/// <summary>
///  The MC6809's undocumented opcodes, prefixes, postbytes and flags, as David Banks's
///  <see href="https://github.com/hoglet67/6809Decoder/wiki/Undocumented-6809-Behaviours">Undocumented 6809
///  Behaviours</see> and David Flamand's Comprehensive Document of 6809 Undocumented and Undefined Behavior
///  describe them from real chips.
/// </summary>
[TestClass]
public class M6809UndocumentedTests
{
    private const byte Carry = 0x01;
    private const byte Overflow = 0x02;
    private const byte Zero = 0x04;
    private const byte Negative = 0x08;
    private const byte Entire = 0x80;

    /// <summary>
    ///  An opcode that ignores bit 0, or a prefix that falls back to page 0, matches its documented twin's every
    ///  bus cycle and result, the prefix adding its one fetch.
    /// </summary>
    /// <param name="undocumented">The undocumented encoding.</param>
    /// <param name="documented">The documented encoding it matches.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x01, 0x40 }, new byte[] { 0x00, 0x40 })]             // NEG direct
    [DataRow(new byte[] { 0x41 }, new byte[] { 0x40 })]                         // NEGA
    [DataRow(new byte[] { 0x51 }, new byte[] { 0x50 })]                         // NEGB
    [DataRow(new byte[] { 0x61, 0x84 }, new byte[] { 0x60, 0x84 })]             // NEG ,X
    [DataRow(new byte[] { 0x71, 0x00, 0x40 }, new byte[] { 0x70, 0x00, 0x40 })] // NEG extended
    [DataRow(new byte[] { 0x05, 0x40 }, new byte[] { 0x04, 0x40 })]             // LSR direct
    [DataRow(new byte[] { 0x45 }, new byte[] { 0x44 })]                         // LSRA
    [DataRow(new byte[] { 0x55 }, new byte[] { 0x54 })]                         // LSRB
    [DataRow(new byte[] { 0x65, 0x84 }, new byte[] { 0x64, 0x84 })]             // LSR ,X
    [DataRow(new byte[] { 0x75, 0x00, 0x40 }, new byte[] { 0x74, 0x00, 0x40 })] // LSR extended
    [DataRow(new byte[] { 0x1B }, new byte[] { 0x12 })]                         // NOP
    public void AliasesMatchTheirDocumentedTwins(byte[] undocumented, byte[] documented)
    {
        (List<ProcessorCycle> expectedCycles, M6809Registers expected, byte expectedMemory) = Run(documented);
        (List<ProcessorCycle> actualCycles, M6809Registers actual, byte actualMemory) = Run(undocumented);

        // Every cycle matches but the opcode fetch's value, which is the opcode itself.
        static (BusOperation, ushort, byte) Bus(ProcessorCycle cycle, int index) =>
            (cycle.Operation, cycle.Address, index == 0 ? (byte)0 : cycle.Value);

        actualCycles.Select(Bus).Should().Equal(expectedCycles.Select(Bus));
        actual.Should().Be(expected);
        actualMemory.Should().Be(expectedMemory);
    }

    /// <summary>
    ///  An undefined opcode after <c>$10</c> or <c>$11</c> runs as page 0, one cycle longer; real CoCos run
    ///  <c>$10 $4F</c> as <c>CLRA</c> (MAME bug 06797).
    /// </summary>
    /// <param name="prefix">The prefix.</param>
    [TestMethod]
    [DataRow((byte)0x10)]
    [DataRow((byte)0x11)]
    public void UndefinedPrefixedOpcodesRunAsPageZero(byte prefix)
    {
        M6809Processor<RamBus> cpu = Create(prefix, 0x4F);
        cpu.Registers = new() { D = 0xFFFF };
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(3);
        cycles[1].Operation.Should().Be(BusOperation.Read);
        cycles[1].Address.Should().Be(1);
        cpu.Registers.A.Should().Be(0x00);
        cpu.Registers.B.Should().Be(0xFF);
        cpu.Registers.PC.Should().Be(2);
    }

    /// <summary>
    ///  Only the first prefix counts: each further one is fetched for a cycle and ignored, and no interrupt is
    ///  taken between them.
    /// </summary>
    [TestMethod]
    public void RepeatedPrefixesCostACycleEachAndHoldOffInterrupts()
    {
        // $10 $11 $10 $8E $12 $34: LDY #$1234, the first prefix's page.
        M6809Processor<RamBus> cpu = Create(0x10, 0x11, 0x10, 0x8E, 0x12, 0x34);
        cpu.Registers = new() { S = 0x1000 };
        cpu.StepCycle();
        cpu.Signals = M6809Signals.InterruptRequest;

        List<ProcessorCycle> rest = Cycles(cpu);
        (rest.Count + 1).Should().Be(6);
        cpu.Registers.Y.Should().Be(0x1234);
        cpu.Registers.PC.Should().Be(6);

        // The IRQ is taken only at the next boundary.
        cpu.StepCycle();
        cpu.LastCycle.IsOpcodeFetch.Should().BeFalse();
    }

    /// <summary>
    ///  <c>XNC</c> (<c>$x2</c>) is <c>NEG</c> when C is clear and <c>COM</c> when C is set, in every mode.
    /// </summary>
    /// <param name="carry">Whether C is set before.</param>
    /// <param name="expected">The result for an operand of <c>$05</c>.</param>
    [TestMethod]
    [DataRow(false, (byte)0xFB)]
    [DataRow(true, (byte)0xFA)]
    public void NegateOrComplementFollowsCarry(bool carry, byte expected)
    {
        byte cc = carry ? Carry : (byte)0;

        M6809Processor<RamBus> accumulator = Create(0x42);
        accumulator.Registers = new() { A = 0x05, CC = cc };
        Cycles(accumulator).Should().HaveCount(2);
        accumulator.Registers.A.Should().Be(expected);

        M6809Processor<RamBus> memory = Create(0x02, 0x40);
        memory.Registers = new() { CC = cc };
        memory.Bus.Memory[0x40] = 0x05;
        Cycles(memory).Should().HaveCount(6);
        memory.Bus.Memory[0x40].Should().Be(expected);
    }

    /// <summary>
    ///  <c>XDEC</c> (<c>$xB</c>) is <c>DEC</c> that clears C when the operand is zero and sets it otherwise.
    /// </summary>
    [TestMethod]
    public void UndocumentedDecrementSetsCarryFromTheOperand()
    {
        M6809Processor<RamBus> zero = Create(0x4B);
        zero.Registers = new() { A = 0x00, CC = Carry };
        Cycles(zero).Should().HaveCount(2);
        zero.Registers.A.Should().Be(0xFF);
        zero.Registers.CC.Should().Be(Negative);

        M6809Processor<RamBus> overflow = Create(0x0B, 0x40);
        overflow.Registers = new();
        overflow.Bus.Memory[0x40] = 0x80;
        Cycles(overflow).Should().HaveCount(6);
        overflow.Bus.Memory[0x40].Should().Be(0x7F);
        overflow.Registers.CC.Should().Be((byte)(Overflow | Carry));
    }

    /// <summary>
    ///  <c>XCLRA</c> and <c>XCLRB</c> (<c>$4E</c>, <c>$5E</c>) clear as <c>CLRA</c> and <c>CLRB</c> but keep C.
    /// </summary>
    [TestMethod]
    public void UndocumentedClearKeepsCarry()
    {
        M6809Processor<RamBus> cpu = Create(0x4E, 0x5E);
        cpu.Registers = new() { D = 0x1234, CC = Carry | Negative | Overflow };
        Cycles(cpu).Should().HaveCount(2);
        Cycles(cpu).Should().HaveCount(2);
        cpu.Registers.D.Should().Be(0);
        cpu.Registers.CC.Should().Be((byte)(Zero | Carry));
    }

    /// <summary>
    ///  <c>$18</c> reads the next byte without advancing and shifts each flag up through it: E from F and bit 6,
    ///  down to Z from V and bit 1; V from (C and bit 0) or (Z and bit 2); C cleared. Three cycles.
    /// </summary>
    /// <param name="cc">CC before.</param>
    /// <param name="mask">The next byte.</param>
    /// <param name="expected">CC after.</param>
    [TestMethod]
    [DataRow((byte)0xFF, (byte)0xFF, (byte)0xFE)]
    [DataRow((byte)0x04, (byte)0x04, (byte)0x0A)]
    [DataRow((byte)0x04, (byte)0x00, (byte)0x00)]
    [DataRow((byte)0x41, (byte)0x41, (byte)0x82)]
    [DataRow((byte)0x7F, (byte)0x3F, (byte)0x7E)]
    public void ShiftConditionCodesMasksWithTheNextByte(byte cc, byte mask, byte expected)
    {
        M6809Processor<RamBus> cpu = Create(0x18, mask);
        cpu.Registers = new() { CC = cc };
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(3);
        cycles[1].Operation.Should().Be(BusOperation.Read);
        cycles[1].Address.Should().Be(1);
        cpu.Registers.PC.Should().Be(1);
        cpu.Registers.CC.Should().Be(expected);
    }

    /// <summary>
    ///  <c>XANDCC</c> (<c>$38</c>) is <c>ANDCC</c> with one more cycle.
    /// </summary>
    [TestMethod]
    public void UndocumentedAndConditionCodesTakesFourCycles()
    {
        M6809Processor<RamBus> cpu = Create(0x38, 0xAF);
        cpu.Registers = new() { CC = 0xFF };
        Cycles(cpu).Should().HaveCount(4);
        cpu.Registers.CC.Should().Be(0xAF);
        cpu.Registers.PC.Should().Be(2);
    }

    /// <summary>
    ///  <c>XRES</c>, <c>XSWI2</c> and <c>XFIRQ</c> (<c>$3E</c>, <c>$10 $3E</c>, <c>$11 $3E</c>) stack the whole state
    ///  as <c>SWI</c> does, but leave E as it was in the stacked CC and leave I and F alone.
    /// </summary>
    /// <param name="program">The instruction.</param>
    /// <param name="vector">The vector it reads.</param>
    /// <param name="length">Its cycles.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x3E }, 0xFFFE, 19)]
    [DataRow(new byte[] { 0x10, 0x3E }, 0xFFF4, 20)]
    [DataRow(new byte[] { 0x11, 0x3E }, 0xFFF6, 20)]
    public void UndocumentedSoftwareInterruptsStackWithoutEntire(byte[] program, int vector, int length)
    {
        M6809Processor<RamBus> cpu = Create(program);
        cpu.Registers = new() { S = 0x1000, CC = Carry };
        cpu.Bus.Memory[vector] = 0x30;
        cpu.Bus.Memory[vector + 1] = 0x00;
        List<ProcessorCycle> cycles = Cycles(cpu);

        int pushes = length - 16;
        cycles.Should().HaveCount(length);
        cycles[pushes].Operation.Should().Be(BusOperation.Write);
        cycles[pushes].Address.Should().Be(0x0FFF);
        cycles[pushes + 11].Operation.Should().Be(BusOperation.Write);
        cycles[pushes + 11].Address.Should().Be(0x0FF4);
        cycles[pushes + 11].Value.Should().Be(Carry);
        cycles[pushes + 12].Operation.Should().Be(BusOperation.None);
        cycles[pushes + 13].Address.Should().Be((ushort)vector);
        cycles[pushes + 14].Address.Should().Be((ushort)(vector + 1));
        cycles[pushes + 15].Operation.Should().Be(BusOperation.None);
        cpu.Registers.PC.Should().Be(0x3000);
        cpu.Registers.CC.Should().Be(Carry);
        cpu.Registers.S.Should().Be(0x0FF4);
    }

    /// <summary>
    ///  <c>$10 $20</c> is <c>LBRA</c> one cycle longer than <c>$16</c>.
    /// </summary>
    [TestMethod]
    public void PrefixedLongBranchAlwaysTakesSixCycles()
    {
        M6809Processor<RamBus> cpu = Create(0x10, 0x20, 0x01, 0x00);
        Cycles(cpu).Should().HaveCount(6);
        cpu.Registers.PC.Should().Be(0x0104);
    }

    /// <summary>
    ///  <c>XADDD</c> (<c>$10 $C3</c>) sets N, Z, V and C as <c>ADDD</c> does without writing D; <c>XADDU</c>
    ///  (<c>$11 $C3</c>) adds to U with its high byte forced to <c>$FF</c>.
    /// </summary>
    [TestMethod]
    public void UndocumentedAddsSetFlagsWithoutStoring()
    {
        M6809Processor<RamBus> addD = Create(0x10, 0xC3, 0x00, 0x01);
        addD.Registers = new() { D = 0xFFFF };
        Cycles(addD).Should().HaveCount(5);
        addD.Registers.D.Should().Be(0xFFFF);
        addD.Registers.CC.Should().Be((byte)(Zero | Carry));

        M6809Processor<RamBus> addU = Create(0x11, 0xD3, 0x40);
        addU.Registers = new() { U = 0x0010 };
        addU.Bus.Memory[0x40] = 0x00;
        addU.Bus.Memory[0x41] = 0xF0;
        Cycles(addU).Should().HaveCount(7);
        addU.Registers.U.Should().Be(0x0010);
        addU.Registers.CC.Should().Be((byte)(Zero | Carry));
    }

    /// <summary>
    ///  The 8-bit store immediate reads its operand and writes nothing; the 16-bit one writes the register's
    ///  low byte over the operand's low byte on its last cycle. After a prefix, N is set and Z and V cleared.
    /// </summary>
    [TestMethod]
    public void StoreImmediatePlacesItsBusCycles()
    {
        M6809Processor<RamBus> eight = Create(0x10, 0x87, 0x55);
        eight.Registers = new() { A = 0x00, CC = Zero | Overflow };
        List<ProcessorCycle> eightCycles = Cycles(eight);
        eightCycles.Should().HaveCount(3);
        eightCycles.Should().NotContain(cycle => cycle.Operation == BusOperation.Write);
        eightCycles[2].Address.Should().Be(2);
        eight.Bus.Memory[2].Should().Be(0x55);
        eight.Registers.CC.Should().Be(Negative);

        M6809Processor<RamBus> sixteen = Create(0x8F, 0x55, 0x66);
        sixteen.Registers = new() { X = 0x1234 };
        List<ProcessorCycle> sixteenCycles = Cycles(sixteen);
        sixteenCycles.Should().HaveCount(3);
        sixteenCycles[1].Operation.Should().Be(BusOperation.Read);
        sixteenCycles[1].Address.Should().Be(1);
        sixteenCycles[2].Operation.Should().Be(BusOperation.Write);
        sixteenCycles[2].Address.Should().Be(2);
        sixteenCycles[2].Value.Should().Be(0x34);
        sixteen.Bus.Memory[1].Should().Be(0x55);
        sixteen.Registers.PC.Should().Be(3);

        // $10 $CF stores S, $11 $8F stores X.
        M6809Processor<RamBus> stackPointer = Create(0x10, 0xCF, 0x00, 0x00);
        stackPointer.Registers = new() { S = 0xABCD };
        Cycles(stackPointer).Should().HaveCount(4);
        stackPointer.Bus.Memory[3].Should().Be(0xCD);

        M6809Processor<RamBus> page3 = Create(0x11, 0x8F, 0x00, 0x00);
        page3.Registers = new() { X = 0x00EF, Y = 0x0011 };
        Cycles(page3).Should().HaveCount(4);
        page3.Bus.Memory[3].Should().Be(0xEF);
    }

    /// <summary>
    ///  An unprefixed store immediate takes N, Z and V from what the previous instruction left, by the groups in
    ///  Banks's wiki.
    /// </summary>
    /// <param name="before">The instruction before <c>$87</c>.</param>
    /// <param name="d">D before.</param>
    /// <param name="expected">N, Z and V after.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x81, 0x00 }, 0x8000, (byte)Zero)]                       // CMPA: Z set
    [DataRow(new byte[] { 0x86, 0x00 }, 0x1200, (byte)Zero)]                       // LDA #0: from A
    [DataRow(new byte[] { 0x86, 0x80 }, 0x1200, (byte)Negative)]                   // LDA #$80: from A
    [DataRow(new byte[] { 0x8B, 0x00 }, 0xFF00, (byte)Zero)]                       // ADDA: Z when A is $FF
    [DataRow(new byte[] { 0x8B, 0x00 }, 0x1000, (byte)Negative)]                   // ADDA: N when A is positive
    [DataRow(new byte[] { 0x4D }, 0x0100, (byte)Zero)]                             // TSTA: as A - 1
    [DataRow(new byte[] { 0x4D }, 0x8000, (byte)Overflow)]                         // TSTA: V when A is $80
    [DataRow(new byte[] { 0x4F }, 0x0100, (byte)Negative)]                         // CLRA: the default group
    [DataRow(new byte[] { 0x1D }, 0x0001, (byte)Zero)]                             // SEX: as B - 1
    [DataRow(new byte[] { 0x8C, 0x00, 0x00 }, 0x0000, (byte)Negative)]             // CMPX: result high - 1
    [DataRow(new byte[] { 0x30, 0x01 }, 0x0000, (byte)Zero)]                       // LEAX 1,X: $00 | $01 = 1
    [DataRow(new byte[] { 0x12 }, 0x0000, (byte)Negative)]                         // NOP: the default group
    public void UnprefixedStoreImmediateFlagsFollowThePreviousInstruction(byte[] before, int d, byte expected)
    {
        M6809Processor<RamBus> cpu = Create([.. before, 0x87, 0x00]);
        cpu.Registers = new() { D = (ushort)d };
        cpu.StepInstruction();
        cpu.Registers = cpu.Registers with { CC = (byte)(cpu.Registers.CC & ~(Negative | Zero | Overflow)) };

        Cycles(cpu).Should().HaveCount(2);
        (cpu.Registers.CC & (Negative | Zero | Overflow)).Should().Be(expected);
    }

    /// <summary>
    ///  The unprefixed 16-bit store immediate clears Z when the stored low byte is nonzero, and clears V.
    /// </summary>
    [TestMethod]
    public void UnprefixedWideStoreImmediateClearsZeroForANonzeroLowByte()
    {
        // CMPA #0 sets the Z group; X's low byte decides.
        M6809Processor<RamBus> zeroLow = Create(0x81, 0x00, 0x8F, 0x00, 0x00);
        zeroLow.Registers = new() { X = 0x1200 };
        zeroLow.StepInstruction();
        zeroLow.StepInstruction();
        (zeroLow.Registers.CC & (Negative | Zero | Overflow)).Should().Be(Zero);

        M6809Processor<RamBus> nonzeroLow = Create(0x81, 0x00, 0x8F, 0x00, 0x00);
        nonzeroLow.Registers = new() { X = 0x1201 };
        nonzeroLow.StepInstruction();
        nonzeroLow.StepInstruction();
        (nonzeroLow.Registers.CC & (Negative | Zero | Overflow)).Should().Be(0);
    }

    /// <summary>
    ///  Halt and catch fire (<c>$14</c>, <c>$15</c>, <c>$CD</c>, and after a prefix) reads up through memory a byte
    ///  a cycle, takes no interrupt, and leaves only on RESET.
    /// </summary>
    /// <param name="program">The instruction.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x14 })]
    [DataRow(new byte[] { 0x15 })]
    [DataRow(new byte[] { 0xCD })]
    [DataRow(new byte[] { 0x10, 0x14 })]
    public void HaltAndCatchFireCountsTheAddressBusUntilReset(byte[] program)
    {
        M6809Processor<RamBus> cpu = Create(program);
        cpu.Registers = new() { S = 0x8000 };
        cpu.Bus.Memory[0xFFFE] = 0x40;
        cpu.Bus.Memory[0xFFFF] = 0x00;
        for (int index = 0; index < program.Length; index++)
        {
            cpu.StepCycle();
        }

        cpu.Signals = M6809Signals.NonMaskableInterrupt | M6809Signals.InterruptRequest | M6809Signals.FastInterruptRequest;
        for (int index = 0; index < 300; index++)
        {
            cpu.StepCycle();
            cpu.LastCycle.Operation.Should().Be(BusOperation.Read);
            cpu.LastCycle.Address.Should().Be((ushort)(program.Length + index));
        }

        cpu.StepInstruction(maximumCycles: 100).Status.Should().Be(ProcessorExecutionStatus.CycleBudgetExhausted);

        cpu.Signals = M6809Signals.Reset;
        cpu.StepCycle();
        cpu.Signals = M6809Signals.None;
        cpu.StepInstruction(maximumCycles: 20);
        cpu.Registers.PC.Should().Be(0x4000);
    }

    /// <summary>
    ///  <c>SEX</c> leaves V unchanged and <c>DAA</c> sets V to the new C XOR the new bit 7 of A, though the
    ///  datasheet says both clear it.
    /// </summary>
    [TestMethod]
    public void SignExtendAndDecimalAdjustSetOverflowAsTheChipDoes()
    {
        M6809Processor<RamBus> sex = Create(0x1D);
        sex.Registers = new() { B = 0x80, CC = Overflow };
        Cycles(sex).Should().HaveCount(2);
        sex.Registers.D.Should().Be(0xFF80);
        sex.Registers.CC.Should().Be((byte)(Negative | Overflow));

        // $9A + $00 corrects by $66 to $00 with a carry: C=1, bit 7=0, so V=1.
        M6809Processor<RamBus> daa = Create(0x19);
        daa.Registers = new() { A = 0x9A };
        Cycles(daa).Should().HaveCount(2);
        daa.Registers.A.Should().Be(0x00);
        daa.Registers.CC.Should().Be((byte)(Zero | Overflow | Carry));

        // $0F corrects by $06 to $15: C=0, bit 7=0, so V=0.
        M6809Processor<RamBus> noCarry = Create(0x19);
        noCarry.Registers = new() { A = 0x0F, CC = Overflow };
        Cycles(noCarry).Should().HaveCount(2);
        noCarry.Registers.A.Should().Be(0x15);
        noCarry.Registers.CC.Should().Be(0);
    }

    /// <summary>
    ///  <c>TFR</c> and <c>EXG</c> across sizes and undefined registers follow Flamand, page 8.
    /// </summary>
    /// <param name="program">The instruction.</param>
    /// <param name="x">X after.</param>
    /// <param name="a">A after.</param>
    /// <param name="dp">DP after.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x1F, 0x81 }, 0xFF12, 0x12, 0x56)] // TFR A,X: $FF:A
    [DataRow(new byte[] { 0x1F, 0xB1 }, 0x5656, 0x12, 0x56)] // TFR DP,X: DP:DP
    [DataRow(new byte[] { 0x1F, 0x18 }, 0xABCD, 0xCD, 0x56)] // TFR X,A: the low byte
    [DataRow(new byte[] { 0x1F, 0x61 }, 0xFFFF, 0x12, 0x56)] // TFR undefined,X: $FFFF
    [DataRow(new byte[] { 0x1F, 0xC8 }, 0xABCD, 0xFF, 0x56)] // TFR undefined,A: $FF
    [DataRow(new byte[] { 0x1F, 0x1C }, 0xABCD, 0x12, 0x56)] // TFR X,undefined: nothing
    [DataRow(new byte[] { 0x1E, 0x1B }, 0xFF56, 0x12, 0xCD)] // EXG X,DP: X gets $FF:DP through the temporary
    [DataRow(new byte[] { 0x1E, 0xB1 }, 0x5656, 0x12, 0xCD)] // EXG DP,X: X gets DP:DP
    [DataRow(new byte[] { 0x1E, 0x81 }, 0xFF12, 0xCD, 0x56)] // EXG A,X
    public void TransfersAcrossSizesAndUndefinedRegisters(byte[] program, int x, int a, int dp)
    {
        M6809Processor<RamBus> cpu = Create(program);
        cpu.Registers = new() { A = 0x12, X = 0xABCD, DP = 0x56 };
        cpu.StepInstruction();
        cpu.Registers.X.Should().Be((ushort)x);
        cpu.Registers.A.Should().Be((byte)a);
        cpu.Registers.DP.Should().Be((byte)dp);
    }

    /// <summary>
    ///  <c>PSHS</c> and <c>PULS</c>, even with no registers, and auto-increment or auto-decrement of S arm NMI;
    ///  <c>JSR</c> does not.
    /// </summary>
    /// <param name="program">The instruction.</param>
    /// <param name="arms">Whether it arms NMI.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x34, 0x00 }, true)] // PSHS with no registers
    [DataRow(new byte[] { 0x35, 0x00 }, true)] // PULS with no registers
    [DataRow(new byte[] { 0xA6, 0xE0 }, true)] // LDA ,S+
    [DataRow(new byte[] { 0xA6, 0xE3 }, true)] // LDA ,--S
    [DataRow(new byte[] { 0xA6, 0xC0 }, false)] // LDA ,U+
    [DataRow(new byte[] { 0x9D, 0x40 }, false)] // JSR <$40
    public void MoreStackUsesArmNonMaskableInterrupt(byte[] program, bool arms)
    {
        M6809Processor<RamBus> cpu = Create(program);
        cpu.StepInstruction();
        cpu.Registers.NmiArmed.Should().Be(arms);
    }

    /// <summary>
    ///  Indexed mode 7 is a second encoding of <c>A,R</c>, and mode 14 addresses <c>$FFFF</c> five cycles more
    ///  slowly than <c>,R</c>, eight when indirect.
    /// </summary>
    [TestMethod]
    public void UndefinedIndexedModesAddressAsTheChipDoes()
    {
        M6809Processor<RamBus> second = Create(0xE6, 0x87);
        second.Registers = new() { A = 0x10, X = 0x2000 };
        second.Bus.Memory[0x2010] = 0x5A;
        Cycles(second).Should().HaveCount(5);
        second.Registers.B.Should().Be(0x5A);

        M6809Processor<RamBus> fixedAddress = Create(0xE6, 0x8E);
        fixedAddress.Bus.Memory[0xFFFF] = 0xA5;
        List<ProcessorCycle> cycles = Cycles(fixedAddress);
        cycles.Should().HaveCount(9);
        cycles[^1].Address.Should().Be(0xFFFF);
        fixedAddress.Registers.B.Should().Be(0xA5);

        // The pointer's low byte wraps to $0000, the opcode itself.
        M6809Processor<RamBus> indirect = Create(0xE6, 0x9E);
        indirect.Bus.Memory[0xFFFF] = 0x30;
        indirect.Bus.Memory[0x30E6] = 0x77;
        Cycles(indirect).Should().HaveCount(12);
        indirect.Registers.B.Should().Be(0x77);
    }

    private static (List<ProcessorCycle> Cycles, M6809Registers Registers, byte Memory) Run(byte[] program)
    {
        M6809Processor<RamBus> cpu = Create(program);
        cpu.Registers = new() { D = 0x0381, X = 0x0040, CC = Carry };
        cpu.Bus.Memory[0x40] = 0x81;
        List<ProcessorCycle> cycles = Cycles(cpu);
        return (cycles, cpu.Registers, cpu.Bus.Memory[0x40]);
    }

    /// <summary>
    ///  HALT asserted before an instruction's last cycle lets it finish, then idles the bus until it is released.
    /// </summary>
    [TestMethod]
    public void HaltStopsAtTheInstructionBoundary()
    {
        // LDA #$12 ; LDB #$34
        M6809Processor<RamBus> cpu = Create(0x86, 0x12, 0xC6, 0x34);
        cpu.Registers = new() { PC = 0 };
        cpu.StepCycle();
        cpu.Signals = M6809Signals.Halt;
        while (!cpu.IsInstructionBoundary) { cpu.StepCycle(); }
        cpu.Registers.A.Should().Be(0x12);

        for (int cycle = 0; cycle < 10; cycle++)
        {
            cpu.StepCycle();
            cpu.LastCycle.Operation.Should().Be(BusOperation.None);
        }

        cpu.Registers.PC.Should().Be(2);
        cpu.Signals = M6809Signals.None;
        cpu.StepInstruction();
        cpu.Registers.B.Should().Be(0x34);
    }

    /// <summary>
    ///  HALT raised during an instruction's last cycle, as a disk controller's DRQ falling on that cycle's read
    ///  raises it, misses that boundary: the next instruction runs before the processor halts.
    /// </summary>
    [TestMethod]
    public void HaltRaisedInTheLastCycleStopsAnInstructionLater()
    {
        // LDA #$12 ; LDB #$34 ; NOP
        M6809Processor<RamBus> cpu = Create(0x86, 0x12, 0xC6, 0x34, 0x12);
        cpu.Registers = new() { PC = 0 };
        cpu.StepCycle();
        cpu.StepCycle();
        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.Signals = M6809Signals.Halt;
        cpu.StepInstruction();
        cpu.Registers.B.Should().Be(0x34);

        for (int cycle = 0; cycle < 10; cycle++) { cpu.StepCycle(); }
        cpu.Registers.PC.Should().Be(4);
    }

    private static M6809Processor<RamBus> Create(params byte[] program)
    {
        byte[] memory = new byte[0x10000];
        program.CopyTo(memory, 0);
        return new(new RamBus(memory));
    }

    private static List<ProcessorCycle> Cycles(M6809Processor<RamBus> cpu)
    {
        List<ProcessorCycle> cycles = [cpu.NextCycle()];
        while (!cpu.IsInstructionBoundary)
        {
            cycles.Add(cpu.NextCycle());
        }

        return cycles;
    }
}
