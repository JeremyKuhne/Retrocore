// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;
// An instruction's address with the registers before it; the B flag is left out, since MAME shows it set.
using Row = (ushort Pc, byte A, byte X, byte Y, byte P, byte S);

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20 against MAME: from power-on to <c>READY.</c> and on, the ROMs must run the same instructions with the
///  same registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\PetOracle.lua</c>,
///   which traces the VIC-20's 6502 (tag <c>ue10</c>); the serial bus's drive slot is left empty. The jiffy
///   interrupt is VIA 2's timer 1 on both, so the interrupts come at the same instructions; the comparison still
///   leaves them out, as the PET's does, since MAME logs the instruction it takes one at twice.
///  </para>
/// </remarks>
[TestClass]
public class Vic20OracleTests
{
    /// <summary>
    ///  From power-on through the RAM test, the banner and <c>READY.</c> to the wait for a key.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    /// <param name="expansion">The expansion RAM.</param>
    /// <param name="mameMachine">MAME's machine.</param>
    /// <param name="mameExpansion">MAME's expansion cartridge, or empty for none.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.None, "vic20", "")]
    [DataRow(VicVideoStandard.Pal, Vic20Expansion.None, "vic20p", "")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.Ram3K, "vic20", "3k")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.Ram8K, "vic20", "8k")]
    [DataRow(VicVideoStandard.Pal, Vic20Expansion.Ram16K, "vic20p", "16k")]
    public void BootMatchesMame(VicVideoStandard standard, Vic20Expansion expansion, string mameMachine, string mameExpansion)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Vic20MachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, mameMachine + ".zip")))
        {
            Assert.Inconclusive("MAME or the VIC-20 ROM sets are missing.");
        }

        Vic20Machine machine = Vic20MachineTests.Machine(standard, expansion);
        List<string> arguments = [mameMachine, "-iec8", ""];
        if (mameExpansion.Length != 0) { arguments.AddRange(["-exp", mameExpansion]); }
        Compare(mame, machine, arguments, roms);
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal));
    }

    /// <summary>
    ///  With a cartridge from MAME's <c>vic1001_cart</c> list, from power-on through the kernal's check for
    ///  <c>A0CBM</c> into the cartridge, or on to BASIC with the cartridge's RAM counted.
    /// </summary>
    /// <param name="software">The list's name for the cartridge.</param>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow("avenger", VicVideoStandard.Ntsc)]
    [DataRow("gorf", VicVideoStandard.Ntsc)]
    [DataRow("dkong", VicVideoStandard.Ntsc)]
    [DataRow("ldrun", VicVideoStandard.Pal)]
    [DataRow("sprexpnd", VicVideoStandard.Ntsc)]
    [DataRow("progaid", VicVideoStandard.Ntsc)]
    public void CartridgeBootMatchesMame(string software, VicVideoStandard standard)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Vic20MachineTests.RomRoot), "mame");
        string hash = Path.Join(Path.GetDirectoryName(mame), "hash");
        string mameMachine = standard == VicVideoStandard.Ntsc ? "vic20" : "vic20p";
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, mameMachine + ".zip")) || !Directory.Exists(hash))
        {
            Assert.Inconclusive("MAME, its hash files or the VIC-20 ROM sets are missing.");
        }

        Vic20Machine machine = Vic20MachineTests.Machine(standard, cartridge: Vic20CartridgeTests.FromSoftwareList(software));
        string carts = Path.Join(ExternalTestData.Root, "vic20-media", "extract", "vic1001_cart");
        List<string> arguments =
        [
            mameMachine, "-iec8", "", software, "-hashpath", hash
        ];

        Compare(mame, machine, arguments, $"{roms};{carts}");
    }

    // MAME's frame at three seconds falls a hair before them on its clock (2.999999999999999880 on the 60 Hz
    // VIC-20), so the script, which compares MAME's time exactly, is asked for that frame by a time just before it.
    private const double MameEnd = 2.999;

    // Traces MAME and the machine for three emulated seconds and compares them instruction by instruction.
    private static void Compare(string mame, Vic20Machine machine, List<string> arguments, string roms)
    {
        ushort irq = (ushort)(machine.Bus.Peek(0xFFFE) | (machine.Bus.Peek(0xFFFF) << 8));
        Dictionary<string, string> environment = [];
        environment["RETRO_CPU"] = "ue10";
        List<Row> expected = PetOracleTests.Collapse(Normalize(
            PetOracleTests.WithoutInterrupts(
                PetOracleTests.RunMame(mame, arguments, roms, seconds: MameEnd, "PetOracle.lua", environment),
                irq,
                machine.Bus.Peek),
            machine.Bus.Peek));

        List<Row> actual = PetOracleTests.Collapse(Normalize(
            PetOracleTests.WithoutInterrupts(RunMachine(machine, seconds: 3), irq, machine.Bus.Peek),
            machine.Bus.Peek));

        expected.Count.Should().BeGreaterThan(5_000, "MAME ran");

        int count = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < count; i++)
        {
            if (expected[i] != actual[i])
            {
                string context = string.Join(
                    '\n',
                    Enumerable.Range(Math.Max(0, i - 8), Math.Min(12, count - Math.Max(0, i - 8)))
                        .Select(j => $"{PetOracleTests.Show(expected[j])}    {PetOracleTests.Show(actual[j])}"));

                Assert.Fail($"Instruction {i} of {count} differs (MAME, then ours):\n{context}");
            }
        }

        // Both end in the same loop, each counted once.
        Math.Abs(expected.Count - actual.Count).Should().BeLessThan(16);
    }

    // The kernal's RAM test (both kernals have it at the same addresses) reads each address, writes $55 and compares.
    // Where nothing answers, the read sees the VIC's bus: ours its last fetch or its read of $001C, MAME's the last
    // byte on it, including the processor's accesses to RAM, the character ROM and the VIC's registers. So A, X and
    // the compare's flags are left out of the check's rows ($FE91-$FEA8) and the loop that calls it ($FDAF-$FDEA),
    // where X still holds the byte; the instructions still match.
    //
    // VIA 1's PA7 drives ATN out through an inverter. A program that makes it an input (as games do, clearing $9113
    // to read the joystick) reads a pin nothing drives: high here, as an open TTL input is, low in MAME. So after a
    // load from port A ($9111 or $911F) the loaded register's bit 7 and the N flag are left out of the next row.
    private static IEnumerable<Row> Normalize(IEnumerable<Row> rows, Func<ushort, byte> peek)
    {
        ushort previous = 0;
        foreach (Row row in rows)
        {
            Row normal = row.Pc is (>= 0xFE91 and <= 0xFEA8) or (>= 0xFDAF and <= 0xFDEA)
                ? row with { A = 0, X = 0, P = (byte)(row.P & 0x7C) }
                : row;

            int operand = peek((ushort)(previous + 1)) | (peek((ushort)(previous + 2)) << 8);
            if (operand is 0x9111 or 0x911F)
            {
                byte p = (byte)(normal.P & 0x7F);
                normal = peek(previous) switch
                {
                    0xAD => normal with { A = (byte)(normal.A & 0x7F), P = p },
                    0xAE => normal with { X = (byte)(normal.X & 0x7F), P = p },
                    0xAC => normal with { Y = (byte)(normal.Y & 0x7F), P = p },
                    _ => normal
                };
            }

            previous = row.Pc;
            yield return normal;
        }
    }

    private static List<Row> RunMachine(Vic20Machine machine, int seconds)
    {
        // The registers' power-on contents are happenstance; take MAME's once the reset sequence is done.
        for (int i = 0; i < 7; i++) { machine.StepCycle(); }
        ProcessorRegisters start = machine.Processor.Registers;
        start.Accumulator = 0;
        start.X = 0x80;
        start.Y = 0;
        start.StackPointer = 0xFD;
        start.Status |= StatusRegister.Zero;
        machine.Processor.Registers = start;

        List<Row> rows = [];
        ulong end = (ulong)(seconds * machine.CpuHertz);
        while (machine.Processor.CycleCount < end)
        {
            ProcessorRegisters r = machine.Processor.Registers;
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer));
            machine.StepInstruction();
        }

        return rows;
    }
}
