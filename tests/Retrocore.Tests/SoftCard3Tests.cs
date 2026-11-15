// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Microsoft's SoftCard /// on the Apple III: its mapping PROM's source, its switch and registers, and CP/M from its
///  master disk.
/// </summary>
/// <remarks>
///  <para>
///   The CP/M test needs the disk in <c>RETROCORE_SOFTCARD3</c> or <c>%USERPROFILE%\Retrocore\softcard3</c>, and
///   the Apple III's ROM; it is inconclusive without them. The PROM's test needs MAME's <c>softcard3.rom</c> in the
///   same folder's <c>extract</c>.
///  </para>
/// </remarks>
[TestClass]
public sealed class SoftCard3Tests
{
    private const string Master = "Apple Softcard III CPM Master Diskette (076-0002) Apple 1982.dsk";

    private static string Fixtures => Environment.GetEnvironmentVariable("RETROCORE_SOFTCARD3")
        ?? Path.Join(ExternalTestData.Root, "softcard3");

    /// <summary>
    ///  The PROM's source assembles to the PROM.
    /// </summary>
    [TestMethod]
    public void PromSourceIsByteIdentical()
    {
        string dump = Path.Join(Fixtures, "extract", "softcard3.rom");
        if (!File.Exists(dump)) { Assert.Inconclusive($"No PROM dump at {dump}."); }
        Prom().Should().Equal(File.ReadAllBytes(dump));
    }

    /// <summary>
    ///  The PROM puts Z80 page 0 at Apple $2000, the I/O page at Z80 $A000 and zero page at Z80 $F000.
    /// </summary>
    [TestMethod]
    public void PromMapsTheZ80()
    {
        SoftCard3 card = Machine().Bus.InstallSoftCard(slot: 4, Prom());
        card.Translate(0x0000).Should().Be(0x2000);
        card.Translate(0xA010).Should().Be(0xC010);
        card.Translate(0xE4FC).Should().Be(0xFFFC);
        card.Translate(0xF0FF).Should().Be(0x00FF);
    }

    /// <summary>
    ///  The card's I/O reads $50; after $01 and $10 are written there, a read of $FFFC starts the Z80 from zero, which
    ///  runs until <c>OUT ($00),A</c> gives the bus back, and the 6502 goes on after its read.
    /// </summary>
    [TestMethod]
    public void SwitchesToTheZ80AndBack()
    {
        Apple3Machine machine = Machine();
        SoftCard3 card = machine.Bus.InstallSoftCard(slot: 4, Prom());

        // The Z80 stores $5A at Z80 $0100 (Apple $2100) and gives the bus back: LD A,$5A; LD ($0100),A; OUT ($00),A.
        ReadOnlySpan<byte> z80 = [0x3E, 0x5A, 0x32, 0x00, 0x01, 0xD3, 0x00, 0x76];
        // The 6502, from $A000, at 1 MHz with I/O on: arm the card in slot 4 ($C0C0), switch, then loop.
        ReadOnlySpan<byte> host =
        [
            0xA9, 0x01, 0x8D, 0xC0, 0xC0,       // LDA #$01; STA $C0C0
            0xA9, 0x10, 0x8D, 0xC0, 0xC0,       // LDA #$10; STA $C0C0
            0xAD, 0xC0, 0xC0, 0x85, 0x10,       // LDA $C0C0; STA $10
            0xAD, 0xFC, 0xFF,                   // LDA $FFFC
            0xAD, 0xFD, 0xFF,                   // LDA $FFFD
            0x4C, 0x15, 0xA0                    // JMP *
        ];

        Start(machine, host);
        for (int i = 0; i < z80.Length; i++) { machine.Bus.DmaWrite((ushort)(0x2000 + i), z80[i]); }

        machine.Run(2_000);
        card.OwnsBus.Should().BeFalse();
        card.TimerRunning.Should().BeFalse();
        machine.Bus.Peek(0x0010).Should().Be(0x50);
        machine.Bus.Peek(0x2100).Should().Be(0x5A);
        machine.Processor.Registers.ProgramCounter.Should().BeInRange(0xA015, 0xA017);
        card.Processor.Registers.PC.Should().Be(0x0007);
    }

    /// <summary>
    ///  Without $10 written, a read of $FFFC reads the ROM and does not switch. With it written, a peek there sees
    ///  the card's $FF without switching.
    /// </summary>
    [TestMethod]
    public void FffcSwitchesOnlyWhenEnabled()
    {
        Apple3Machine machine = Machine();
        SoftCard3 card = machine.Bus.InstallSoftCard(slot: 4, Prom());
        Start(machine, [0xAD, 0xFC, 0xFF, 0x85, 0x10, 0x4C, 0x05, 0xA0]);
        machine.Run(100);
        card.Running.Should().BeFalse();
        machine.Bus.Peek(0x0010).Should().Be(machine.Bus.Rom[0xFFC]);

        machine.Bus.Write(0xC0C0, 0x10);
        machine.Bus.Peek(0xFFFC).Should().Be(0xFF);
        card.Running.Should().BeFalse();
    }

    /// <summary>
    ///  A Z80 that never gives the bus back loses it when the supervision timer runs out.
    /// </summary>
    [TestMethod]
    public void TimerGivesTheBusBack()
    {
        Apple3Machine machine = Machine();
        SoftCard3 card = machine.Bus.InstallSoftCard(slot: 4, Prom());
        Start(machine, [0xA9, 0x10, 0x8D, 0xC0, 0xC0, 0xAD, 0xFC, 0xFF, 0x4C, 0x08, 0xA0]);
        machine.Bus.DmaWrite(0x2000, 0x18);     // JR *
        machine.Bus.DmaWrite(0x2001, 0xFE);
        machine.Run(1_000);
        card.OwnsBus.Should().BeTrue();
        machine.LastCycle.IsStalled.Should().BeTrue("the 6502 is held");
        machine.StepInstruction(maximumCycles: 8).Cycles.Should().Be(8, "the machine's cycles go on");
        machine.Run(TimeSpan.FromMilliseconds(250));
        card.OwnsBus.Should().BeFalse();
        machine.Processor.Registers.ProgramCounter.Should().BeInRange(0xA008, 0xA00A, "the 6502 loops on its JMP");
    }

    /// <summary>
    ///  CP/M boots from its master disk with the card in slot 4, to <c>A&gt;</c>, and DIR lists the disk.
    /// </summary>
    [TestMethod]
    public void CpmBootsAndListsTheDisk()
    {
        string path = Path.Join(Fixtures, Master);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_SOFTCARD3 to a folder with {Master}."); }

        Apple3Machine machine = Machine();
        machine.Bus.InstallSoftCard(slot: 4, Prom());
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), Master, "DSK");

        RunUntil(machine, "A>", seconds: 60);
        Screen(machine).Should().Contain("Apple SoftCard /// CP/M").And.Contain("56K Version 2.20");
        foreach (char key in "DIR\r") { machine.Bus.QueueKey((byte)key); }
        RunUntil(machine, "DDT      COM", seconds: 10);
    }

    /// <summary>
    ///  Assembles the mapping PROM from the SDK's source.
    /// </summary>
    /// <returns>The PROM's 256 bytes.</returns>
    internal static byte[] Prom()
    {
        string path = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "Inputs", "Apple3", "SoftCard3Prom.asm"));
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions("Z80", 0, 0x100) { SourceResolver = new FileAssemblySourceResolver() });

        result.Success.Should().BeTrue(string.Join(", ", result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        return result.Sections[0].Bytes.ToArray();
    }

    private static Apple3Machine Machine() => Apple3MachineTests.Machine();

    // Runs a 6502 program from $A000 in the system bank. At power-on the environment register reads all ones: 1 MHz,
    // with I/O and the ROM on.
    private static void Start(Apple3Machine machine, ReadOnlySpan<byte> program)
    {
        for (int i = 0; i < program.Length; i++) { machine.Bus.Write((ushort)(0xA000 + i), program[i]); }
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        machine.Processor.Registers = machine.Processor.Registers with { ProgramCounter = 0xA000 };
    }

    private static string Screen(Apple3Machine machine) => string.Join('\n', machine.ReadTextScreen());

    private static void RunUntil(Apple3Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        Assert.Fail($"No \"{text}\" after {seconds} seconds. The screen:\n{Screen(machine)}");
    }
}
