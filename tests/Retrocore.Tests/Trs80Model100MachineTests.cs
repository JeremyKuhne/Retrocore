// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Machines;
using Retrocore.Machines.Trs80Model100;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100's hardware, driven by small 8085 programs in place of its ROM: the clock's 256 Hz RST 7.5, the
///  keyboard matrix, the option ROM's switch, the LCD's ports, RAM sizes, and the power-off bit.
/// </summary>
[TestClass]
public sealed class Trs80Model100MachineTests
{
    // Makes the 81C55's ports A and B outputs, as the ROM does.
    private const string Setup = """
        .cpu I8085
                .org 0
                lxi sp,$0000
                mvi a,$03
                out $B8
        """;

    /// <summary>
    ///  Commanding the clock's TP to 256 Hz through port A and STB, and unmasking RST 7.5, gives 256 interrupts a
    ///  second.
    /// </summary>
    [TestMethod]
    public void ClockDrivesRestartSevenFive()
    {
        Trs80Model100Machine machine = Build($"""
            {Setup}
                    jmp Start
                    .org $003C
                    push h
                    lhld $F000
                    inx h
                    shld $F000
                    pop h
                    ei
                    ret
            Start:  mvi a,$05
                    out $B9
                    mvi a,$04
                    out $E0
                    xra a
                    out $E0
                    mvi a,$1B
                    sim
                    ei
            Loop:   jmp Loop
            """);

        machine.RunSeconds(0.01);
        machine.Bus.Clock.TimingPulseHertz.Should().Be(256);
        int start = Word(machine, 0xF000);
        machine.RunSeconds(1);
        (Word(machine, 0xF000) - start).Should().BeInRange(255, 257);
    }

    /// <summary>
    ///  A key pulls its row low in port $E8's read (the ROM's port of $E0-$EF) while its column is strobed low,
    ///  column 8 from port B bit 0. Port B keeps bit 4 low, which would turn the power off.
    /// </summary>
    [TestMethod]
    public void KeyboardReadsTheStrobedColumns()
    {
        Trs80Model100Machine machine = Build($"""
            {Setup}
                    mvi a,$FE
                    out $B9
                    mvi a,$EF
                    out $BA
                    in $E8
                    sta $F000
                    mvi a,$FF
                    out $B9
                    mvi a,$EE
                    out $BA
                    in $E8
                    sta $F001
                    mvi a,$FD
                    out $B9
                    mvi a,$EF
                    out $BA
                    in $E8
                    sta $F002
                    hlt
            """);

        machine.Keyboard.Set(Trs80Model100Key.Z, pressed: true);
        machine.Keyboard.Set(Trs80Model100Key.M, pressed: true);
        machine.Keyboard.Set(Trs80Model100Key.Shift, pressed: true);
        machine.Keyboard.Set(Trs80Model100Key.Break, pressed: true);
        RunToHalt(machine);
        machine.Bus.Peek(0xF000).Should().Be(0xBE, "Z is row 0 and M row 6 of column 0");
        machine.Bus.Peek(0xF001).Should().Be(0x7E, "SHIFT is row 0 and BREAK row 7 of column 8");
        machine.Bus.Peek(0xF002).Should().Be(0xFF, "nothing is down in column 1");
    }

    /// <summary>
    ///  The Model 100's own keys type from the debugger's codes: 28-31 the arrows, 128 F1, 139 PAUSE and 140 BREAK,
    ///  which is PAUSE/BREAK with SHIFT; 8 is DEL and 1 CTRL with A.
    /// </summary>
    [TestMethod]
    public void TypedCodesPressTheirKeys()
    {
        Trs80Model100Machine machine = Build($"{Setup}\n        hlt");
        (byte Code, Trs80Model100Key Key, Trs80Model100Key? Modifier)[] cases =
        [
            (28, Trs80Model100Key.Right, null),
            (29, Trs80Model100Key.Left, null),
            (30, Trs80Model100Key.Up, null),
            (31, Trs80Model100Key.Down, null),
            (128, Trs80Model100Key.F1, null),
            (139, Trs80Model100Key.Break, null),
            (140, Trs80Model100Key.Break, Trs80Model100Key.Shift),
            (8, Trs80Model100Key.Delete, null),
            (1, Trs80Model100Key.A, Trs80Model100Key.Control)
        ];

        foreach ((byte code, Trs80Model100Key key, Trs80Model100Key? modifier) in cases)
        {
            machine.Keyboard.Type(code).Should().BeTrue();
            machine.Run(1000);
            machine.Keyboard.IsPressed(key).Should().BeTrue($"code {code} presses {key}");
            machine.Keyboard.IsPressed(Trs80Model100Key.Shift).Should().Be(modifier == Trs80Model100Key.Shift);
            machine.Keyboard.IsPressed(Trs80Model100Key.Control).Should().Be(modifier == Trs80Model100Key.Control);
            while (machine.Keyboard.IsTyping) { machine.Run(10_000); }

            // The release before the next key.
            machine.RunSeconds(0.06);
        }

        machine.Keyboard.Type(141).Should().BeFalse();
    }

    /// <summary>
    ///  Port $E0 bit 0 puts the option ROM over $0000-$7FFF, for code running in RAM; with the socket empty the
    ///  addresses read $FF.
    /// </summary>
    [TestMethod]
    public void PortE0SwitchesTheOptionRom()
    {
        const string Program = $"""
            {Setup}
                    jmp $F100
                    .org $0100
                    .byte $55
            """;

        byte[] stub =
        [
            0x3E, 0x01, 0xD3, 0xE0,     // MVI A,1 ; OUT $E0
            0x3A, 0x00, 0x01,           // LDA $0100
            0x32, 0x00, 0xF0,           // STA $F000
            0xAF, 0xD3, 0xE0,           // XRA A ; OUT $E0
            0x3A, 0x00, 0x01,           // LDA $0100
            0x32, 0x01, 0xF0,           // STA $F001
            0x76                        // HLT
        ];

        byte[] option = new byte[0x2000];
        option[0x100] = 0xAA;
        foreach (byte[]? optionRom in new[] { option, null })
        {
            Trs80Model100Machine machine = Build(Program, optionRom);
            for (int index = 0; index < stub.Length; index++)
            {
                machine.Bus.Write((ushort)(0xF100 + index), stub[index]);
            }

            RunToHalt(machine);
            machine.Bus.Peek(0xF000).Should().Be(optionRom is null ? (byte)0xFF : (byte)0xAA);
            machine.Bus.Peek(0xF001).Should().Be(0x55);
            machine.Bus.OptionRomSelected.Should().BeFalse();
        }
    }

    /// <summary>
    ///  The LCD drivers whose selects are high take instructions at $FE and data at $FF; reading them back takes a
    ///  dummy read first, and selected drivers' reads are ORed.
    /// </summary>
    [TestMethod]
    public void LcdThroughItsPorts()
    {
        Trs80Model100Machine machine = Build($"""
            {Setup}
                    mvi a,$08
                    out $B9
                    mvi a,$02
                    out $BA
                    mvi a,$39
                    out $FE
                    mvi a,$05
                    out $FE
                    mvi a,$81
                    out $FF
                    mvi a,$05
                    out $FE
                    in $FF
                    in $FF
                    sta $F000
                    in $FE
                    sta $F001
                    hlt
            """);

        RunToHalt(machine);
        machine.Lcd[3][0, 5].Should().Be(0x81);
        machine.Lcd[9][0, 5].Should().Be(0x81);
        machine.Lcd[2][0, 5].Should().Be(0);
        machine.Bus.Peek(0xF000).Should().Be(0x81);
        machine.Bus.Peek(0xF001).Should().Be(0x40, "both drivers are on and counting up");
        machine.Lcd.Dot(3 * 50 + 5, 0).Should().BeTrue();
        machine.Lcd.Dot(4 * 50 + 5, 39).Should().BeTrue("driver 9 is the bottom row's rightmost");
    }

    /// <summary>
    ///  RAM fills down from $FFFF; below it, addresses read $FF and lose writes.
    /// </summary>
    [TestMethod]
    public void RamFillsDownFromTheTop()
    {
        foreach (int kilobytes in new[] { 8, 16, 24, 32 })
        {
            Trs80Model100Machine machine = Build($"{Setup}\n        hlt", ramKilobytes: kilobytes);
            ushort start = (ushort)(0x10000 - kilobytes * 1024);
            machine.Bus.RamStart.Should().Be(start);
            machine.Bus.Write(start, 0x12);
            machine.Bus.Read(start).Should().Be(0x12);
            machine.Bus.Area(start).Should().Be(Trs80Model100MemoryArea.Ram);
            if (kilobytes < 32)
            {
                machine.Bus.Write((ushort)(start - 1), 0x12);
                machine.Bus.Read((ushort)(start - 1)).Should().Be(0xFF);
                machine.Bus.Area((ushort)(start - 1)).Should().Be(Trs80Model100MemoryArea.None);
            }
        }
    }

    /// <summary>
    ///  Port B bit 4 turns the power off: the CPU stops; the power switch restarts it at 0 with RAM kept.
    /// </summary>
    [TestMethod]
    public void PortBTurnsThePowerOff()
    {
        Trs80Model100Machine machine = Build($"""
            {Setup}
                    mvi a,$77
                    sta $F000
                    mvi a,$10
                    out $BA
            Spin:   jmp Spin
            """);

        for (int cycle = 0; cycle < 10_000 && !machine.IsPoweredOff; cycle++) { machine.StepCycle(); }
        machine.IsPoweredOff.Should().BeTrue();
        ulong cycles = machine.Processor.CycleCount;
        machine.Run(1000);
        machine.Processor.CycleCount.Should().Be(cycles, "the CPU has no power");
        ((IMachine)machine).StepInstruction(32).Status.Should().Be(Cpu.ProcessorExecutionStatus.Waiting);

        machine.PowerOn();
        machine.IsPoweredOff.Should().BeFalse();
        machine.Processor.Registers.PC.Should().Be(0);
        machine.Bus.Peek(0xF000).Should().Be(0x77);
    }

    /// <summary>
    ///  The UART's status shows its transmitter empty and the power good, and ports no device answers read $FF.
    /// </summary>
    [TestMethod]
    public void UnconnectedPorts()
    {
        Trs80Model100Machine machine = Build($"{Setup}\n        hlt");
        machine.Bus.PeekPort(0xD8).Should().Be(0x90);
        machine.Bus.PeekPort(0x80).Should().Be(0xFF);
        machine.Bus.PeekPort(0x00).Should().Be(0xFF);
        machine.Processor.Variant.Should().Be(I8080Variant.I8085);
        ((IMachine)machine).Id.Should().Be("trs80-model100");
    }

    private static Trs80Model100Machine Build(string source, byte[]? option = null, int ramKilobytes = 32)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, "model100.asm"),
            new AssemblyOptions(I8080Isa.Name8085, 0, 0x8000));

        result.Diagnostics.Should().BeEmpty();
        byte[] rom = new byte[Trs80Model100Roms.RomSize];
        foreach (AssemblySection section in result.Sections)
        {
            section.Bytes.Span.CopyTo(rom.AsSpan(section.Origin));
        }

        return new(
            new Trs80Model100Configuration { RamKilobytes = ramKilobytes, StartTime = new DateTime(2026, 11, 26) },
            new Trs80Model100Roms(rom, option));
    }

    private static void RunToHalt(Trs80Model100Machine machine)
    {
        for (int cycle = 0; cycle < 1_000_000 && !machine.Processor.IsHalted; cycle++) { machine.StepCycle(); }
        machine.Processor.IsHalted.Should().BeTrue("the program reached its HLT");
    }

    private static int Word(Trs80Model100Machine machine, ushort address) =>
        machine.Bus.Peek(address) | (machine.Bus.Peek((ushort)(address + 1)) << 8);
}
