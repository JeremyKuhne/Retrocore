// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Machines.Altair;
using Retrocore.Machines.Chips;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Altair 8800: 8080 programs on the 88-2SIO's terminal, its interrupts, the sense switches, RAM and the front
///  panel, and the terminal's ADM-3A controls.
/// </summary>
[TestClass]
public class AltairMachineTests
{
    // Resets the first ACIA, then sets it to divide by 16 with 8 data bits and one stop bit, as Altair software does.
    private const string Setup = """
        .cpu I8080
                .org 0
                lxi sp,$1000
                mvi a,3
                out $10
                mvi a,$15
                out $10
        """;

    // Prints the zero-terminated string at HL.
    private const string Print = """
        Print:  in $10
                ani 2
                jz Print
                mov a,m
                ora a
                rz
                out $11
                inx h
                jmp Print
        """;

    /// <summary>
    ///  A program prints through the 88-2SIO, waiting for TDRE before each character.
    /// </summary>
    [TestMethod]
    public void ProgramPrintsOnTheTerminal()
    {
        AltairMachine machine = Run($"""
            {Setup}
                    lxi h,Text
                    call Print
                    hlt
            {Print}
            Text:   .byte "HELLO, ALTAIR", 13, 10, "8080", 0
            """);

        machine.Terminal.Line(0).TrimEnd().Should().Be("HELLO, ALTAIR");
        machine.Terminal.Line(1).TrimEnd().Should().Be("8080");
        machine.Terminal.CursorRow.Should().Be(1);
        machine.Terminal.CursorColumn.Should().Be(4);
    }

    /// <summary>
    ///  Characters go out one character time apart at the baud rate: 17 at 9600 baud take at least 16 character times.
    /// </summary>
    [TestMethod]
    public void CharactersTakeTheirTimeOnTheLine()
    {
        AltairMachine machine = Run($"""
            {Setup}
                    lxi h,Text
                    call Print
                    hlt
            {Print}
            Text:   .byte "SEVENTEEN LETTERS", 0
            """);

        int character = AltairTiming.CyclesPerCharacter(9600);
        character.Should().Be(2083);
        ((long)machine.Processor.CycleCount).Should().BeGreaterThan(16L * character);
        machine.Terminal.Line(0).TrimEnd().Should().Be("SEVENTEEN LETTERS");
    }

    /// <summary>
    ///  An echo loop reads typed keys when RDRF is set and sends them back.
    /// </summary>
    [TestMethod]
    public void EchoReadsTypedKeys()
    {
        AltairMachine machine = Build($"""
            {Setup}
            Loop:   in $10
                    rrc
                    jnc Loop
                    in $11
                    mov b,a
            Wait:   in $10
                    ani 2
                    jz Wait
                    mov a,b
                    out $11
                    cpi '.'
                    jnz Loop
                    hlt
            """);

        foreach (char key in "Echo me.") { machine.Terminal.Type((byte)key); }
        RunToHalt(machine);
        machine.Terminal.Line(0).TrimEnd().Should().Be("Echo me.");
        machine.Terminal.PendingKeys.Should().Be(0);
    }

    /// <summary>
    ///  With the receive interrupt enabled, a key interrupts the 8080, and the floating bus's $FF acknowledge runs
    ///  RST 7.
    /// </summary>
    [TestMethod]
    public void ReceiveInterruptRunsRestartSeven()
    {
        AltairMachine machine = Build($"""
            .cpu I8080
                    .org 0
                    lxi sp,$1000
                    mvi a,3
                    out $10
                    mvi a,$95           ; divide by 16, 8N1, receive interrupt enabled
                    out $10
                    ei
            Idle:   jmp Idle
                    .org $38
                    in $11              ; RST 7: read the key, which clears the request
                    sta $2000
                    hlt
            """);

        machine.Run(2000);
        machine.Processor.IsHalted.Should().BeFalse();
        machine.Terminal.Type((byte)'K');
        RunToHalt(machine);
        machine.Bus.Peek(0x2000).Should().Be((byte)'K');
        machine.Bus.Interrupt.Should().BeFalse();
    }

    /// <summary>
    ///  The ACIA holds its transmitter until a control write releases master reset, and a second character arriving
    ///  before the first is read sets the overrun flag and is lost.
    /// </summary>
    [TestMethod]
    public void AciaHoldsUntilConfiguredAndReportsOverrun()
    {
        Acia6850 acia = new() { CyclesPerCharacter = 3 };
        List<byte> sent = [];
        acia.Transmitted = sent.Add;
        acia.Status.Should().Be(0, "power-on holds the ACIA in master reset");
        acia.Write(1, 0x41);
        acia.Tick();
        sent.Should().BeEmpty();

        acia.Write(0, 0x15);
        acia.Status.Should().Be(Acia6850.TransmitEmpty);
        acia.Write(1, 0x41);
        acia.Write(1, 0x42);
        for (int cycle = 0; cycle < 10; cycle++) { acia.Tick(); }
        byte[] expected = [0x42];
        sent.Should().Equal(expected, "the second write replaced the first before the shift register took it");

        acia.Receive(0x31);
        acia.Receive(0x32);
        acia.Status.Should().Be(Acia6850.TransmitEmpty | Acia6850.ReceiveFull | Acia6850.Overrun);
        acia.Read(1).Should().Be(0x31);
        acia.Status.Should().Be(Acia6850.TransmitEmpty);
    }

    /// <summary>
    ///  IN $FF reads the sense switches, the front panel's high 8 switches; other ports float to $FF.
    /// </summary>
    [TestMethod]
    public void SenseSwitchesAndFloatingPorts()
    {
        AltairMachine machine = Build("""
            .cpu I8080
                    in $FF
                    sta $2000
                    in $42
                    sta $2001
                    hlt
            """, new AltairConfiguration { Switches = 0xA500 });

        RunToHalt(machine);
        machine.Bus.Peek(0x2000).Should().Be(0xA5);
        machine.Bus.Peek(0x2001).Should().Be(0xFF);
    }

    /// <summary>
    ///  Addresses past the RAM read $FF and lose writes.
    /// </summary>
    [TestMethod]
    public void RamEndsWhereConfigured()
    {
        AltairMachine machine = new(new AltairConfiguration { RamKilobytes = 4 });
        machine.Bus.Write(0x0FFF, 0x12);
        machine.Bus.Write(0x1000, 0x34);
        machine.Bus.Peek(0x0FFF).Should().Be(0x12);
        machine.Bus.Peek(0x1000).Should().Be(0xFF);
        machine.Bus.Area(0x1000).Should().Be(AltairMemoryArea.None);
        Action invalid = () => _ = new AltairMachine(new AltairConfiguration { RamKilobytes = 65 });
        invalid.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  The front panel examines and deposits through its switches, as an operator keyed in a program.
    /// </summary>
    [TestMethod]
    public void FrontPanelExaminesAndDeposits()
    {
        AltairMachine machine = new(new AltairConfiguration());
        AltairFrontPanel panel = machine.FrontPanel;
        panel.Switches = 0x0100;
        panel.Examine();
        panel.Address.Should().Be(0x0100);
        panel.Switches = 0x003E;
        panel.Deposit();
        panel.Switches = 0x0042;
        panel.DepositNext();
        panel.Switches = 0x0076;
        panel.DepositNext();
        machine.Bus.Peek(0x0100).Should().Be(0x3E);
        machine.Bus.Peek(0x0101).Should().Be(0x42);
        machine.Bus.Peek(0x0102).Should().Be(0x76);
        panel.Data.Should().Be(0x76);

        // RUN from $0100: MVI A,$42 / HLT.
        machine.Processor.Registers = machine.Processor.Registers with { PC = 0x0100 };
        RunToHalt(machine);
        machine.Processor.Registers.A.Should().Be(0x42);
    }

    /// <summary>
    ///  The terminal follows the ADM-3A's controls: cursor movement, ESC = addressing, ^Z, wrapping and scrolling.
    /// </summary>
    [TestMethod]
    public void TerminalFollowsTheAdm3A()
    {
        AltairMachine machine = new(new AltairConfiguration());
        AltairTerminal terminal = machine.Terminal;
        void Send(string text)
        {
            foreach (char character in text) { terminal.Print((byte)character); }
        }

        Send("ABC\bX\x1B=\x22\x25Z");
        terminal.Line(0).TrimEnd().Should().Be("ABX");
        terminal.Line(2).TrimEnd().Should().Be("     Z");
        Send("\x1E\x0C\x0CY\x0B\x0B\x0A!");
        terminal.Line(0).TrimEnd().Should().Be("ABY");
        terminal.Line(1).TrimEnd().Should().Be("   !");

        Send("\x1A" + new string('w', 81));
        terminal.Line(0).Should().Be(new string('w', 80));
        terminal.Line(1).TrimEnd().Should().Be("w");
        for (int line = 0; line < 23; line++) { Send("\r\n"); }
        terminal.Line(0).TrimEnd().Should().Be("w", "the first line scrolled away");
        terminal.CursorRow.Should().Be(23);

        Send("\x1A\t\x07\xC1");
        terminal.Line(0).TrimEnd().Should().Be("A", "^I and BEL do nothing, and bit 7 is ignored");
    }

    /// <summary>
    ///  The terminal renders 80 by 24 characters of 8 by 10 pixels, the cursor inverted while it blinks on.
    /// </summary>
    [TestMethod]
    public void TerminalRenders()
    {
        AltairMachine machine = new(new AltairConfiguration());
        AltairTerminal terminal = machine.Terminal;
        terminal.Width.Should().Be(640);
        terminal.Height.Should().Be(240);
        terminal.Print((byte)'I');
        byte[] pixels = new byte[terminal.Width * terminal.Height * 4];
        terminal.Render(pixels, scanned: false);

        // 'I' is $38 in its first row: pixels 2, 3 and 4 lit; the cursor's cell after it is inverted.
        pixels[2 * 4].Should().Be(0xFF);
        pixels[1 * 4].Should().Be(0x00);
        pixels[(8 + 1) * 4].Should().Be(0xFF, "the cursor's cell is inverted");
    }

    /// <summary>
    ///  RESET restarts the 8080 at 0 and master resets the ACIAs; RAM keeps its contents.
    /// </summary>
    [TestMethod]
    public void ResetKeepsRam()
    {
        AltairMachine machine = Run($"""
            {Setup}
                    mvi a,$55
                    sta $2000
                    hlt
            """);

        machine.Bus.SerialA.Status.Should().Be(Acia6850.TransmitEmpty);
        machine.Reset();
        machine.Processor.Registers.PC.Should().Be(0);
        machine.Bus.SerialA.Status.Should().Be(0);
        machine.Bus.Peek(0x2000).Should().Be(0x55);
    }

    private static AltairMachine Run(string source, AltairConfiguration? configuration = null)
    {
        AltairMachine machine = Build(source, configuration);
        RunToHalt(machine);
        return machine;
    }

    private static AltairMachine Build(string source, AltairConfiguration? configuration = null)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, "altair.asm"),
            new AssemblyOptions(I8080Isa.Name, 0, 0x1000));

        result.Diagnostics.Should().BeEmpty();
        AltairMachine machine = new(configuration ?? new AltairConfiguration());
        ReadOnlySpan<byte> image = result.Sections[0].Bytes.Span;
        for (int index = 0; index < image.Length; index++) { machine.Bus.Write((ushort)index, image[index]); }
        return machine;
    }

    // Runs to the program's HLT, then a little longer: the clock runs on in the halt state, and the last character
    // written is still in the ACIA's shift register for a character time.
    private static void RunToHalt(AltairMachine machine)
    {
        for (int cycle = 0; cycle < 2_000_000 && !machine.Processor.IsHalted; cycle++) { machine.StepCycle(); }
        machine.Processor.IsHalted.Should().BeTrue("the program reached its HLT");
        machine.Run((ulong)(2 * AltairTiming.CyclesPerCharacter(machine.Configuration.BaudRate)));
    }
}
