// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Z80 SoftCard with small programs that need no disk: the switch both ways, address translation,
///  the clock, reset, and the IIe's memory switches.
/// </summary>
[TestClass]
public sealed class Apple2SoftCardTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // At $0300: switch to the Z80, then copy what it left at $80 to $81 and spin.
    private static readonly byte[] s_switcher =
    [
        0x8D, 0x00, 0xC4,       // sta $C400
        0xA5, 0x80,             // lda $80
        0x85, 0x81,             // sta $81
        0x4C, 0x07, 0x03        // jmp $0307
    ];

    /// <summary>
    ///  The card's table: Z80 $0000-$AFFF is $1000-$BFFF, $B000-$DFFF the high 12K, $E000 the I/O page and
    ///  $F000 the zero page. With translation off, addresses pass through.
    /// </summary>
    [TestMethod]
    public void TranslatesAddresses()
    {
        SoftCard card = Machine(Apple2Model.IIPlus).Bus.InstallSoftCard(slot: 4);
        card.Translate(0x0000).Should().Be(0x1000);
        card.Translate(0xAFFF).Should().Be(0xBFFF);
        card.Translate(0xB123).Should().Be(0xD123);
        card.Translate(0xC000).Should().Be(0xE000);
        card.Translate(0xDFFF).Should().Be(0xFFFF);
        card.Translate(0xE400).Should().Be(0xC400);
        card.Translate(0xF080).Should().Be(0x0080);
        card.Translates = false;
        card.Translate(0xE400).Should().Be(0xE400);
    }

    /// <summary>
    ///  A 6502 write to $C400 starts the Z80 at zero; its write to $E400 gives the bus back, and the 6502 goes on
    ///  after its store. The next switch resumes the Z80 where it stopped.
    /// </summary>
    [TestMethod]
    public void SwitchesBothWays()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        byte[] program =
        [
            0x3E, 0x42,             // ld a,$42
            0x32, 0x80, 0xF0,       // ld [$F080],a
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x3E, 0x43,             // ld a,$43
            0x32, 0x82, 0xF0,       // ld [$F082],a
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x76                    // halt
        ];

        Load(machine, 0x1000, program);

        Start(machine);
        machine.Run(200);
        card.OwnsBus.Should().BeFalse("the Z80 gave the bus back");
        card.Running.Should().BeFalse("WAIT holds its next fetch");
        card.Processor.Registers.PC.Should().Be(0x0008);
        machine.Bus.Peek(0x81).Should().Be(0x42, "the 6502 went on after its store");

        machine.Bus.Write(0xC4FF, 0);
        machine.Run(50);
        machine.Bus.Peek(0x82).Should().Be(0x43, "the Z80 resumed at its next instruction");
        card.OwnsBus.Should().BeFalse();

        machine.Bus.Read(0xC400);
        card.OwnsBus.Should().BeFalse("reads do nothing");
    }

    /// <summary>
    ///  A debugger's <see cref="Z80Card.TakeBus"/> starts the Z80 where it is pointed and spends the reset the card
    ///  had waiting, so the next switch resumes the program rather than starting the Z80 from zero.
    /// </summary>
    [TestMethod]
    public void TakeBusSpendsTheWaitingReset()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        byte[] program =
        [
            0x3E, 0x42,             // ld a,$42
            0x32, 0x80, 0xF0,       // ld [$F080],a
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x3E, 0x43,             // ld a,$43
            0x32, 0x82, 0xF0,       // ld [$F082],a
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x76                    // halt
        ];

        Load(machine, 0x1100, program);
        int resets = card.Resets;
        card.TakeBus();
        card.Processor.Registers = card.Processor.Registers with { PC = 0x0100 };
        machine.Run(200);
        card.OwnsBus.Should().BeFalse("the Z80 gave the bus back");
        machine.Bus.Peek(0x80).Should().Be(0x42);

        machine.Bus.Write(0xC400, 0);
        machine.Run(50);
        machine.Bus.Peek(0x82).Should().Be(0x43, "the Z80 resumed its program");
        card.Resets.Should().Be(resets, "nothing reset the Z80");
    }

    /// <summary>
    ///  While the Z80 has the bus, the machine's cycles go on: its last cycle shows the 6502 stalled, and an
    ///  instruction step that runs out of budget counts the machine's cycles, though the 6502 ran none.
    /// </summary>
    [TestMethod]
    public void HeldCyclesAreStalledAndCounted()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        Load(machine, 0x1000, [0x18, 0xFE]);  // jr *
        Start(machine);
        machine.Run(20);
        card.OwnsBus.Should().BeTrue();
        machine.LastCycle.IsStalled.Should().BeTrue();

        ProcessorExecutionResult result = machine.StepInstruction(maximumCycles: 8);
        result.Status.Should().Be(ProcessorExecutionStatus.CycleBudgetExhausted);
        result.Cycles.Should().Be(8);
    }

    /// <summary>
    ///  The Z80 runs two T-states to each Apple cycle while the 6502 waits.
    /// </summary>
    [TestMethod]
    public void RunsTwoTStatesToEachAppleCycle()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        Load(machine, 0x1000, [0x18, 0xFE]);    // jr $
        Start(machine);
        machine.Run(10);
        ulong z80 = card.Processor.CycleCount;
        ulong cpu = machine.Processor.CycleCount;
        machine.Run(1000);
        (card.Processor.CycleCount - z80).Should().Be(2000);
        machine.Processor.CycleCount.Should().Be(cpu, "the 6502 is held");
    }

    /// <summary>
    ///  The waiting 6502 reads once in each opcode fetch's refresh, at its next opcode's address; with that
    ///  turned off, it makes no reads.
    /// </summary>
    [TestMethod]
    public void RefreshesTheWaiting6502()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);

        // A held 6502 whose next opcode is at $C030, the speaker: each refresh read toggles it.
        Load(machine, 0x1000, [0x00, 0x18, 0xFD]);  // nop; jr $-1: two fetches in 16 T-states
        machine.Bus.Write(0xC400, 0);
        bool speaker = machine.Bus.Speaker;
        int toggles = 0;
        for (int cycle = 0; cycle < 80; cycle++)
        {
            card.StepAppleCycle(heldAddress: 0xC030);
            if (machine.Bus.Speaker != speaker)
            {
                toggles++;
                speaker = machine.Bus.Speaker;
            }
        }

        toggles.Should().Be(20, "80 cycles are 160 T-states: twenty fetches");
        card.RefreshesHost = false;
        for (int cycle = 0; cycle < 80; cycle++) { card.StepAppleCycle(heldAddress: 0xC030); }
        machine.Bus.Speaker.Should().Be(speaker);
    }

    /// <summary>
    ///  The waiting 6502's read comes in the fetch's refresh T-state, the one after the opcode's read, as the card
    ///  times it, not with the opcode's read.
    /// </summary>
    [TestMethod]
    public void RefreshReadComesInTheRefreshTState()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        Load(machine, 0x1000, [0x00, 0x18, 0xFD]);  // nop; jr $-1
        machine.Bus.Write(0xC400, 0);
        bool speaker = machine.Bus.Speaker;
        int toggles = 0;
        for (int tState = 0; tState < 32; tState++)
        {
            card.StepTState(heldAddress: 0xC030);
            if (machine.Bus.Speaker == speaker) { continue; }
            speaker = machine.Bus.Speaker;
            toggles++;
            card.Processor.IsRefreshing.Should().BeTrue($"T-state {tState} toggled the speaker");
            card.Processor.FetchedOpcode.Should().BeFalse();
        }

        toggles.Should().Be(4, "32 T-states are four fetches");
    }

    /// <summary>
    ///  The Z80 reads the keyboard at $E000 and clears its strobe at $E010, as the 6502 does at $C000 and $C010.
    /// </summary>
    [TestMethod]
    public void ReadsTheKeyboardThroughTheIoPage()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        machine.Bus.InstallSoftCard(slot: 4);
        byte[] program =
        [
            0x3A, 0x00, 0xE0,       // ld a,[$E000]
            0x32, 0x80, 0xF0,       // ld [$F080],a
            0x3A, 0x10, 0xE0,       // ld a,[$E010]
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x76                    // halt
        ];

        Load(machine, 0x1000, program);

        machine.Bus.QueueKey((byte)'A');
        Start(machine);
        machine.Run(100);
        machine.Bus.Peek(0x81).Should().Be((byte)('A' | 0x80));
        machine.Bus.Peek(0xC000).Should().BeLessThan(0x80, "the Z80 cleared the strobe");
    }

    /// <summary>
    ///  RESET turns the card off, and the Z80 starts from zero at the next switch.
    /// </summary>
    [TestMethod]
    public void ResetTurnsTheCardOff()
    {
        Apple2Machine machine = Machine(Apple2Model.IIPlus);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        Load(machine, 0x1000, [0x00, 0x18, 0xFD]);  // nop; jr $-1
        Start(machine);
        machine.Run(100);
        card.OwnsBus.Should().BeTrue();

        machine.Reset();
        card.OwnsBus.Should().BeFalse();
        card.Running.Should().BeFalse();
        machine.Run(100_000);

        Load(machine, 0x1000, [0x32, 0x00, 0xE4, 0x76]);    // ld [$E400],a; halt
        Start(machine);
        machine.Run(50);
        card.OwnsBus.Should().BeFalse("the Z80 started at zero and gave the bus back");
        card.Processor.Registers.PC.Should().Be(0x0003);
    }

    /// <summary>
    ///  On the IIe the Z80's accesses go through the memory switches: with RAMWRT set from the Z80, its write lands in
    ///  auxiliary RAM. With INTCXROM set, the card's page is the firmware's and a write there does not switch.
    /// </summary>
    [TestMethod]
    public void UsesTheIIesMemorySwitches()
    {
        Apple2Machine machine = Machine(Apple2Model.IIeEnhanced);
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        byte[] program =
        [
            0x32, 0x05, 0xE0,       // ld [$E005],a: RAMWRT on
            0x3E, 0x5A,             // ld a,$5A
            0x32, 0x00, 0x30,       // ld [$3000],a: Apple $4000
            0x32, 0x04, 0xE0,       // ld [$E004],a: RAMWRT off
            0x32, 0x00, 0xE4,       // ld [$E400],a
            0x76                    // halt
        ];

        Load(machine, 0x1000, program);

        machine.Bus.SetRam(auxiliary: false, 0x4000, 0);
        Start(machine);
        machine.Bus.Write(0xC006, 0);   // INTCXROM off, wherever the firmware left it
        machine.Run(100);
        card.Processor.Registers.PC.Should().Be(0x000E);
        machine.Bus.AuxiliaryMemory[0x4000].Should().Be(0x5A);
        machine.Bus.MainMemory[0x4000].Should().Be(0);
        card.OwnsBus.Should().BeFalse();

        machine.Bus.Write(0xC007, 0);   // INTCXROM on
        machine.Bus.Write(0xC400, 0);
        card.OwnsBus.Should().BeFalse("the firmware answers at $C400");
    }

    /// <summary>
    ///  The card takes a free slot and leaves it free again when it comes out; there is only one.
    /// </summary>
    [TestMethod]
    public void TakesAFreeSlot()
    {
        Apple2Bus bus = Machine(Apple2Model.IIPlus).Bus;
        SoftCard card = bus.InstallSoftCard(slot: 5);
        bus.IsSlotFree(5).Should().BeFalse();
        card.Slot.Should().Be(5);
        bus.Peek(0xC500).Should().Be(0xFF, "the card has no ROM");
        ((Action)(() => bus.InstallSoftCard(slot: 4))).Should().Throw<InvalidOperationException>();

        bus.RemoveSoftCard();
        bus.SoftCard.Should().BeNull();
        bus.IsSlotFree(5).Should().BeTrue();
        bus.InstallMockingboard();
        ((Action)(() => bus.InstallSoftCard(slot: 4))).Should().Throw<InvalidOperationException>();
    }

    private static Apple2Machine Machine(Apple2Model model)
    {
        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs));
        machine.Run(1_000_000);
        return machine;
    }

    private static void Load(Apple2Machine machine, ushort address, byte[] bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)(address + index), bytes[index]);
        }
    }

    // Points the 6502 at the switcher at $0300.
    private static void Start(Apple2Machine machine)
    {
        Load(machine, 0x0300, s_switcher);
        machine.Bus.SetRam(auxiliary: false, 0x80, 0);
        machine.Bus.SetRam(auxiliary: false, 0x81, 0);
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        machine.Processor.Registers = machine.Processor.Registers with { ProgramCounter = 0x0300 };
    }
}
