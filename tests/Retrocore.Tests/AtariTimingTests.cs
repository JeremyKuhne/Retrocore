// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;

namespace Retrocore.Tests;

/// <summary>
///  ANTIC's cycle timing against the Altirra Hardware Reference Manual and Atari's Hardware Manual: <c>WSYNC</c>, the
///  NMI's arrival, <c>VCOUNT</c> and the DMA a Graphics 0 frame takes.
/// </summary>
/// <remarks>
///  <para>
///   Each test but the Graphics 0 frame's takes the CPU from the OS just after reset, with interrupts masked and
///   ANTIC's DMA off, and runs a program from <c>$2000</c>; that one counts the DMA of the OS's own screen.
///  </para>
/// </remarks>
[TestClass]
public class AtariTimingTests
{
    // A machine with the program at $2000 and the CPU about to run it.
    private static AtariMachine Run(params byte[] code)
    {
        AtariMachine machine = AtariMachineTests.Machine();
        for (int i = 0; i < 7; i++) { machine.StepCycle(); }
        for (int i = 0; i < code.Length; i++) { machine.Bus.Poke((ushort)(0x2000 + i), code[i]); }
        ProcessorRegisters registers = machine.Processor.Registers;
        registers.ProgramCounter = 0x2000;
        registers.Status |= StatusRegister.IRQBDisable;
        machine.Processor.Registers = registers;
        return machine;
    }

    // The cycle within the line of the CPU cycle just run.
    private static int Cycle(AtariMachine machine) => (machine.Antic.Cycle + AtariTiming.CyclesPerLine - 1) % AtariTiming.CyclesPerLine;

    /// <summary>
    ///  After <c>STA WSYNC</c> the CPU runs one more cycle, the next opcode fetch, then waits; it reads the operand on
    ///  cycle 105, so the instruction after that starts on cycle 106 (Altirra 4.9).
    /// </summary>
    [TestMethod]
    public void WsyncReleasesOnCycle105()
    {
        // STA WSYNC; LDA #0; STA $80
        AtariMachine machine = Run(0x8D, 0x0A, 0xD4, 0xA9, 0x00, 0x85, 0x80);
        int held = 0;
        int operand = -1;
        int next = -1;
        for (int i = 0; i < 300 && next < 0; i++)
        {
            machine.StepCycle();
            ProcessorCycle cycle = machine.LastCycle;
            if (cycle.IsStalled) { held++; }
            if (cycle.Address == 0x2004 && !cycle.IsStalled) { operand = Cycle(machine); }
            if (cycle.Address == 0x2005 && cycle.IsOpcodeFetch) { next = Cycle(machine); }
        }

        held.Should().BeGreaterThan(0, "the CPU waited");
        operand.Should().Be(105);
        next.Should().Be(106);
    }

    /// <summary>
    ///  A write to <c>WSYNC</c> up to cycle 103 waits for this line's cycle 105; one on cycle 104 or later waits for
    ///  the next line's (Altirra 4.9).
    /// </summary>
    /// <param name="start">The cycle the program is timed from, which sets when the write falls.</param>
    [TestMethod]
    [DataRow(98)]
    [DataRow(99)]
    [DataRow(100)]
    public void LateWsyncWaitsForTheNextLine(int start)
    {
        // A sled of NOPs reaches STA WSYNC late in the line; time it from the write.
        byte[] code = new byte[64];
        Array.Fill(code, (byte)0xEA);
        AtariMachine machine = Run(code);
        while (Cycle(machine) != start) { machine.StepCycle(); }

        // Put STA WSYNC (4 cycles, the write last) at the next instruction boundary.
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        ushort pc = machine.Processor.Registers.ProgramCounter;
        machine.Bus.Poke(pc, 0x8D);
        machine.Bus.Poke((ushort)(pc + 1), 0x0A);
        machine.Bus.Poke((ushort)(pc + 2), 0xD4);
        int line = machine.Antic.Line;
        int write = -1;
        for (int i = 0; i < 300; i++)
        {
            machine.StepCycle();
            ProcessorCycle cycle = machine.LastCycle;
            if (cycle.Operation == BusOperation.Write && cycle.Address == 0xD40A) { write = Cycle(machine); }
            if (write >= 0 && cycle.Address == pc + 4 && !cycle.IsStalled) { break; }
        }

        write.Should().BeGreaterThanOrEqualTo(102);
        int waitedLines = machine.Antic.Line - line;
        Cycle(machine).Should().Be(105);
        waitedLines.Should().Be(write >= 104 ? 1 : 0, $"the write was on cycle {write}");
    }

    /// <summary>
    ///  The vertical blank NMI: NMIST changes on cycle 7 of line 248, and the 6502 starts its seven-cycle interrupt
    ///  sequence on cycle 10 at the earliest, or 11 when it is in the middle of an instruction (Altirra 4.8). The
    ///  sequence's first push is its third cycle.
    /// </summary>
    /// <param name="offset">NOPs (2 cycles) or a 3-cycle instruction first, to try both phases.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    public void VerticalBlankInterruptStartsOnCycle10(int offset)
    {
        byte[] code = new byte[0x1000];
        Array.Fill(code, (byte)0xEA);

        // LDA #$40; STA NMIEN; then, for the other phase, a 3-cycle BIT $80.
        code[0] = 0xA9;
        code[1] = 0x40;
        code[2] = 0x8D;
        code[3] = 0x0E;
        code[4] = 0xD4;
        if (offset == 1)
        {
            code[5] = 0x24;
            code[6] = 0x80;
        }

        code[0xFFD] = 0x4C;
        code[0xFFE] = 0x07;
        code[0xFFF] = 0x20;
        AtariMachine machine = Run(code);
        int push = -1;
        for (int i = 0; i < 40_000 && push < 0; i++)
        {
            machine.StepCycle();
            ProcessorCycle cycle = machine.LastCycle;
            if (cycle.Operation == BusOperation.Write && cycle.Address >> 8 == 1) { push = Cycle(machine); }
        }

        machine.Antic.Line.Should().Be(AtariTiming.VerticalBlankLine);
        push.Should().BeOneOf(12, 13);
        (machine.Antic.NmiStatus & 0x40).Should().Be(0x40);
    }

    /// <summary>
    ///  <c>NMIEN</c> must be written by cycle 7 to enable the vertical blank interrupt and by cycle 8 to disable it,
    ///  and one enabled on cycle 7 itself starts a cycle late, on cycle 11 (Altirra 4.8). The sequence's first push is
    ///  its third cycle, so 12 or 13 on time, 13 or 14 late.
    /// </summary>
    /// <param name="before">NMIEN before the write.</param>
    /// <param name="after">The value written.</param>
    /// <param name="cycle">The cycle of line 248 the write is on.</param>
    /// <param name="fires">Whether the interrupt comes.</param>
    [TestMethod]
    [DataRow(0x00, 0x40, 7, true)]
    [DataRow(0x00, 0x40, 8, false)]
    [DataRow(0x40, 0x00, 8, false)]
    [DataRow(0x40, 0x00, 9, true)]
    public void NmiEnableWindow(int before, int after, int cycle, bool fires)
    {
        byte[] code = new byte[0x1000];
        Array.Fill(code, (byte)0xEA);
        code[0xFFD] = 0x4C;
        code[0xFFE] = 0x00;
        code[0xFFF] = 0x20;
        AtariMachine machine = Run(code);
        machine.Bus.Write(0xD40E, (byte)before);
        while (!(machine.Antic.Line == AtariTiming.VerticalBlankLine && machine.Antic.Cycle == cycle + 1))
        {
            machine.Run(1);
        }

        machine.Bus.Write(0xD40E, (byte)after);
        int push = -1;
        for (int i = 0; i < 30 && push < 0; i++)
        {
            machine.StepCycle();
            ProcessorCycle step = machine.LastCycle;
            if (step.Operation == BusOperation.Write && step.Address >> 8 == 1) { push = Cycle(machine); }
        }

        (push >= 0).Should().Be(fires, $"NMIEN went from ${before:X2} to ${after:X2} on cycle {cycle}");
        if (fires)
        {
            int[] expected = before == 0 && cycle == 7 ? [13, 14] : [12, 13];
            push.Should().BeOneOf(expected, "the interrupt sequence starts on cycle 10, or 11 after a cycle-7 enable");
        }
    }

    /// <summary>
    ///  <c>VCOUNT</c> is half the scan line, and shows the next line's from cycle 111.
    /// </summary>
    [TestMethod]
    public void VerticalCountChangesOnCycle111()
    {
        AtariMachine machine = Run(0xEA, 0xEA, 0xEA, 0xEA, 0x4C, 0x00, 0x20);
        while (!(machine.Antic.Line == 101 && machine.Antic.Cycle == 110)) { machine.Run(1); }
        machine.Antic.VerticalCount.Should().Be(50);
        machine.Run(1);
        machine.Antic.VerticalCount.Should().Be(51, "line 102 shows from cycle 111 of line 101");
    }

    /// <summary>
    ///  Atari's Hardware Manual counts the DMA of the OS's 40 × 24 text screen at 10,838 cycles a frame: 32 for the
    ///  display list, 960 for the characters, 7,680 for their data and 2,166 for refresh, leaving 19,030 of 29,868
    ///  for the CPU.
    /// </summary>
    [TestMethod]
    public void GraphicsZeroFrameTakesTheManualsDma()
    {
        AtariMachine machine = AtariMachineTests.Machine();
        AtariMachineTests.RunUntil(machine, line => line.Contains("MEMO PAD", StringComparison.Ordinal), seconds: 20);
        machine.RunFrame();
        long start = machine.Bus.Cycles;
        ulong cpu = machine.Processor.CycleCount;
        machine.RunFrame();
        (machine.Bus.Cycles - start).Should().Be(29_868);
        ((long)(machine.Processor.CycleCount - cpu)).Should().Be(19_030);
    }

    /// <summary>
    ///  A display list whose last line, 247, is a plain jump runs the jump on that line and fetches nothing in
    ///  vertical blank, so each frame starts from the same display list.
    /// </summary>
    [TestMethod]
    public void JumpIsNotFetchedInVerticalBlank()
    {
        AtariMachine machine = Display(0x22, 0x42);

        // 239 blank lines (29 of 8 and one of 7) from line 8, then a plain jump to $3000 on line 247.
        ushort at = 0x3000;
        for (int i = 0; i < 29; i++) { machine.Bus.Poke(at++, 0x70); }
        machine.Bus.Poke(at++, 0x60);
        machine.Bus.Poke(at++, 0x01);
        machine.Bus.Poke(at++, 0x00);
        machine.Bus.Poke(at, 0x30);
        machine.RunFrame();
        machine.RunFrame();
        while (machine.Antic.Line != AtariTiming.VerticalBlankLine) { machine.Run(1); }
        machine.Antic.DisplayList.Should().Be(0x3000, "the jump on line 247 went to $3000");
        while (machine.Antic.Line != AtariTiming.FirstDisplayLine) { machine.Run(1); }
        machine.Antic.DisplayList.Should().Be(0x3000, "vertical blank fetches no display list");
    }

    // A machine idling in a loop, with a display list at $3000: 24 blank lines, then the given mode lines from $4000,
    // then a jump and wait for vertical blank. ANTIC runs it with a normal playfield and the OS's character set.
    private static AtariMachine Display(byte dmaControl, params byte[] modeLines)
    {
        AtariMachine machine = Run(0x4C, 0x00, 0x20);
        AtariBus bus = machine.Bus;

        // RAM powers on all ones; clear the screen and player/missile memory.
        for (int address = 0x4000; address < 0x4800; address++) { bus.Poke((ushort)address, 0); }
        ushort at = 0x3000;
        foreach (byte value in (byte[])[0x70, 0x70, 0x70]) { bus.Poke(at++, value); }
        for (int i = 0; i < modeLines.Length; i++)
        {
            bus.Poke(at++, modeLines[i]);
            if (i == 0)
            {
                bus.Poke(at++, 0x00);
                bus.Poke(at++, 0x40);
            }
        }

        bus.Poke(at++, 0x41);
        bus.Poke(at++, 0x00);
        bus.Poke(at, 0x30);
        bus.Write(0xD402, 0x00);
        bus.Write(0xD403, 0x30);
        bus.Write(0xD409, 0xE0);
        bus.Write(0xD016, 0x28);
        bus.Write(0xD017, 0x0E);
        bus.Write(0xD018, 0x94);
        bus.Write(0xD01A, 0x00);
        bus.Write(0xD400, dmaControl);
        return machine;
    }

    // The RGBA at a colour clock of a scan line, its left half pixel.
    private static uint Pixel(AtariMachine machine, int line, int clock)
    {
        byte[] frame = machine.RenderBitmap();
        int offset = (((line - AtariTiming.FirstDisplayLine) * Gtia.FrameWidth) + ((clock - AtariTiming.FirstVisibleClock) * 2)) * 4;
        return BitConverter.ToUInt32(frame, offset);
    }

    /// <summary>
    ///  Horizontal scrolling fetches a wide playfield's bytes into a normal one, the first four off the left edge at
    ///  <c>HSCROL</c> 0; each colour clock of <c>HSCROL</c> moves the picture right by one (Altirra 4.7).
    /// </summary>
    /// <param name="scroll">The <c>HSCROL</c> value.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(3)]
    [DataRow(5)]
    [DataRow(8)]
    public void HorizontalScrollShiftsThePlayfield(int scroll)
    {
        // Mode 2 with LMS and horizontal scrolling; byte 4, at the left edge with HSCROL 0, holds an inverse space,
        // a solid block four colour clocks wide.
        AtariMachine machine = Display(0x22, 0x52);
        machine.Bus.Poke(0x4004, 0x80);
        machine.Bus.Write(0xD401, 0x02);
        machine.Bus.Write(0xD404, (byte)scroll);
        machine.RunFrame();
        machine.RunFrame();

        // The mode line is lines 32-39; every row of the block is PF1 luminance on PF2's hue.
        uint block = machine.Gtia.Rgba(0x9E);
        uint playfield = machine.Gtia.Rgba(0x94);
        int start = 0x30 + scroll;
        Pixel(machine, 33, start).Should().Be(block, $"HSCROL {scroll} moves the block right by {scroll}");
        Pixel(machine, 33, start + 3).Should().Be(block, "the block is four clocks wide");
        Pixel(machine, 33, start + 4).Should().Be(playfield, "the character after it is a space");
        if (scroll > 0) { Pixel(machine, 33, start - 1).Should().Be(playfield, "the character before it is a space"); }
    }

    /// <summary>
    ///  A display list interrupt sets NMIST bit 7 on cycle 7 of its mode line's last scan line (Altirra 4.8).
    /// </summary>
    [TestMethod]
    public void DisplayListInterruptOnLastLine()
    {
        // Mode 2 (8 lines) from line 32 with the DLI bit.
        AtariMachine machine = Display(0x22, 0xC2);
        machine.RunFrame();
        machine.Bus.Write(0xD40F, 0);
        int line = -1;
        int cycle = -1;
        while (line < 0)
        {
            machine.Run(1);
            if ((machine.Antic.NmiStatus & 0x80) != 0)
            {
                line = machine.Antic.Line;
                cycle = Cycle(machine);
            }
        }

        line.Should().Be(39);
        cycle.Should().Be(7);
    }

    /// <summary>
    ///  Player DMA loads GTIA's graphics register each line from <c>PMBASE</c>, two-line resolution putting player 0
    ///  at <c>PMBASE + $200 + line / 2</c>.
    /// </summary>
    [TestMethod]
    public void PlayerDmaDrawsThePlayer()
    {
        AtariMachine machine = Display(0x2E, 0x42);
        machine.Bus.Poke(0x4200 + 50, 0xFF);
        machine.Bus.Write(0xD407, 0x40);
        machine.Bus.Write(0xD01D, 0x03);
        machine.Bus.Write(0xD000, 0x80);
        machine.Bus.Write(0xD012, 0x46);
        machine.RunFrame();
        machine.RunFrame();
        uint player = machine.Gtia.Rgba(0x46);
        Pixel(machine, 100, 0x80).Should().Be(player);
        Pixel(machine, 101, 0x87).Should().Be(player);
        Pixel(machine, 102, 0x80).Should().NotBe(player);
        Pixel(machine, 100, 0x88).Should().NotBe(player);
    }
}
