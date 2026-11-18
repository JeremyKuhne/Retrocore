// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;
// An instruction's address with the registers before it; the B flag is left out, since MAME shows it set.
using Row = (ushort Pc, byte A, byte X, byte Y, byte P, byte S);

namespace Retrocore.Tests;

/// <summary>
///  The 4040's DOS processor against MAME's <c>c4040</c>, on a PET 2001 with BASIC 2: the DOS must run the same
///  instructions with the same registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME runs <c>tools\Pet4040Oracle.lua</c>, which traces the drive's 6502, MAME's first CPU while the PET's
///   IEEE-488 slot holds its default 4040. The PETs type at their own pace, so ATN interrupts the DOS at other
///   moments. Its handler does not return: it resets the stack, serves the bus and goes back to the DOS's main loop.
///   So the comparison cuts each trace where each interrupt starts, and compares the pieces in order, with a loop
///   repeated back to back counted once, by its last pass. Each piece ends in the DOS's wait for the bus, counting
///   through its drives as long as the PET leaves it, so pieces are compared as far as the shorter goes, but for the
///   last few rows, where ATN came in a different pass of the wait.
///  </para>
///  <para>
///   Before the first interrupt, the registers must agree as well as the addresses. After it they are left out: the
///   DOS samples the handshakes as the PET drives them, and MAME's PET, with no beam, takes its own interrupts at
///   other times, so a line can read as already released in one and not yet in the other. Such a race takes a wait
///   one pass more or less, which the collapsed loops hide, but leaves the value read in a register. The addresses
///   must agree throughout. The tests are inconclusive without MAME or the ROM sets.
///  </para>
/// </remarks>
[TestClass]
public class Pet4040OracleTests
{
    // Marks a row whose registers do not count, in the B flag's place, which rows leave clear.
    private const byte Loose = 0x10;

    /// <summary>
    ///  From power-on, the DOS's RAM test, its start-up and the controller's, to the wait for the PET, with no disk.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void PowerOnMatchesMame() => Compare("4040", seconds: 2, disk: null, text: null);

    /// <summary>
    ///  With the 2040 demo disk in drive 0, <c>LOAD "$0",8</c> reads its directory.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DirectoryMatchesMame() => Compare("4040", seconds: 7, PetDiskTests.DemoImage(), "LOAD\"$0\",8\r");

    /// <summary>
    ///  The 2040 from power-on: DOS 1.2's RAM test, its start-up and the controller's, to the wait for the PET.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Dos12PowerOnMatchesMame() => Compare("2040", seconds: 2, disk: null, text: null);

    /// <summary>
    ///  With the DOS 1 demo disk in the 2040's drive 0, the I command initializes it, reading its BAM.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Dos12InitializeMatchesMame() =>
        Compare("2040", seconds: 15, Pet2040DiskTests.DemoImage(), "OPEN15,8,15,\"I0\":CLOSE15\r");

    // Runs MAME and ours with a unit of the model as device 8, a disk image (a D64, or a G64) in its drive 0, and
    // text typed, and compares the DOS processors' traces.
    private static void Compare(string model, int seconds, byte[]? disk, string? text)
    {
        const int typeAt = 2;
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(PetMachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, $"c{model}.zip")) || !File.Exists(Path.Join(roms, "pet2001n.zip")))
        {
            Assert.Inconclusive($"MAME or the PET and {model} ROM sets are missing.");
        }

        PetMachine machine = model == "2040"
            ? Pet2040DiskTests.Machine(ramKilobytes: 8)
            : PetDiskTests.Machine(ramKilobytes: 8);

        Cbm4040 unit = machine.Disks[0];
        string work = Directory.CreateTempSubdirectory("retrocore-4040").FullName;
        try
        {
            List<string> arguments = ["pet2001n"];
            if (model == "2040") { arguments.AddRange(["-ieee8", "c2040"]); }
            if (disk is not null)
            {
                bool g64 = G64Format.IsG64(disk);
                string image = Path.Join(work, g64 ? "disk.g64" : "disk.d64");
                File.WriteAllBytes(image, disk);
                arguments.AddRange(["-flop1", image]);
                unit.Drive0.Insert(g64 ? G64Format.Read(disk) : D64Format.Read(disk), "disk", g64 ? "G64" : "D64");
            }

            Dictionary<string, string> environment = [];
            if (text is not null)
            {
                environment["RETRO_TYPE"] = text.Replace("\r", "\\n", StringComparison.Ordinal);
                environment["RETRO_TYPE_AT"] = typeAt.ToString(CultureInfo.InvariantCulture);
            }

            ushort irq = (ushort)(unit.DosBus.Peek(0xFFFE) | (unit.DosBus.Peek(0xFFFF) << 8));
            List<List<Row>> expected = Split(
                PetOracleTests.RunMame(mame, arguments, roms, seconds, "Pet4040Oracle.lua", environment), irq);

            List<List<Row>> actual = Split(Run(machine, seconds, text, typeAt), irq);
            expected[0].Count.Should().BeGreaterThan(1_000, "MAME traced the DOS");
            if (text is not null)
            {
                string[] screen = machine.ReadTextScreen();
                string shown = string.Join('\n', screen);
                if (text.StartsWith("LOAD", StringComparison.Ordinal))
                {
                    expected.Count.Should().BeGreaterThan(4, "the PET called the drive for each step of the load");
                    screen.Should().Contain(line => line.StartsWith("LOADING", StringComparison.Ordinal), shown);
                }
                else
                {
                    // A command, sent under one ATN and closed under another, is done once READY comes back.
                    expected.Count.Should().BeGreaterThan(1, "the PET called the drive");
                    screen.Count(line => line.StartsWith("READY.", StringComparison.Ordinal)).Should().Be(2, shown);
                }
            }

            int count = Math.Min(expected.Count, actual.Count);
            for (int i = 0; i < count; i++)
            {
                Match(i == 0 ? "before the first interrupt" : $"from interrupt {i}", expected[i], actual[i], registers: i == 0);
            }

            actual.Count.Should().Be(expected.Count, "the DOS takes as many interrupts");
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    // The two sequences agree as far as the shorter goes, less the pass of the wait it ends in: the addresses, and
    // when asked the registers, but in a row either side marks as loose.
    private static void Match(string what, List<Row> expected, List<Row> actual, bool registers)
    {
        int count = Math.Max(0, Math.Min(expected.Count, actual.Count) - 16);
        for (int i = 0; i < count; i++)
        {
            bool loose = !registers || ((expected[i].P | actual[i].P) & Loose) != 0;
            if (expected[i].Pc != actual[i].Pc || (!loose && expected[i] != actual[i]))
            {
                int first = Math.Max(0, i - 8);
                string context = string.Join(
                    '\n',
                    Enumerable.Range(first, Math.Min(12, count - first))
                        .Select(j => $"{PetOracleTests.Show(expected[j])}    {PetOracleTests.Show(actual[j])}"));

                Assert.Fail($"{what}: instruction {i} of {count} differs (MAME, then ours):\n{context}");
            }
        }
    }

    // Cuts the rows where each interrupt starts, each piece with its loops collapsed. Our processor takes the
    // interrupt and the handler's first instruction together, so that row is left out.
    private static List<List<Row>> Split(IEnumerable<Row> rows, ushort irq)
    {
        List<List<Row>> pieces = [];
        List<Row> piece = [];
        foreach (Row row in rows)
        {
            if (row.Pc == irq)
            {
                pieces.Add(Collapse(piece));
                piece = [];
                continue;
            }

            piece.Add(row);
        }

        pieces.Add(Collapse(piece));
        return pieces;
    }

    // Keeps only the last pass of each loop of up to 8 instructions: a run whose addresses repeat the run before it
    // replaces it. The PETs hand bytes over at their own pace, so a wait runs as many times as each takes, and the
    // registers it polls change on its last pass. The kept pass's first row holds the flags of whatever ran before it,
    // a pass the other side may not have run, so it is marked loose: only its address counts.
    private static List<Row> Collapse(List<Row> rows)
    {
        List<Row> collapsed = [];
        foreach (Row row in rows)
        {
            collapsed.Add(row);
            for (int length = 1; length <= 8 && collapsed.Count >= 2 * length; length++)
            {
                int start = collapsed.Count - length;
                bool repeat = true;
                for (int i = 0; i < length && repeat; i++)
                {
                    repeat = collapsed[start + i].Pc == collapsed[start - length + i].Pc;
                }

                if (repeat)
                {
                    collapsed.RemoveRange(start - length, length);
                    collapsed[start - length] = collapsed[start - length] with
                    {
                        P = (byte)(collapsed[start - length].P | Loose)
                    };

                    break;
                }
            }
        }

        return collapsed;
    }

    private static List<Row> Run(PetMachine machine, int seconds, string? text, int typeAt)
    {
        Cbm4040 unit = machine.Disks[0];

        // The registers' power-on contents are happenstance; take MAME's once the reset sequence is done.
        while (!unit.DosProcessor.IsInstructionBoundary) { machine.StepCycle(); }
        ProcessorRegisters start = unit.DosProcessor.Registers;
        start.Accumulator = 0;
        start.X = 0x80;
        start.Y = 0;
        start.StackPointer = 0xFD;
        start.Status = StatusRegister.IRQBDisable | StatusRegister.Zero | (StatusRegister)0x20;
        unit.DosProcessor.Registers = start;

        List<Row> rows = [];
        ulong end = (ulong)seconds * PetTiming.CpuHertz;
        bool boundary = true;
        bool typed = text is null;
        for (ulong cycle = 0; cycle < end; cycle++)
        {
            if (unit.DosProcessor.IsInstructionBoundary)
            {
                if (!boundary)
                {
                    ProcessorRegisters r = unit.DosProcessor.Registers;
                    rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer));
                }

                boundary = true;
            }

            if (cycle == 0)
            {
                ProcessorRegisters r = unit.DosProcessor.Registers;
                rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer));
            }

            if (!typed && cycle == (ulong)typeAt * PetTiming.CpuHertz)
            {
                foreach (char c in text ?? "") { machine.Keyboard.Type((byte)c); }
                typed = true;
            }

            machine.StepCycle();
            if (!unit.DosProcessor.IsInstructionBoundary) { boundary = false; }
        }

        return rows;
    }
}
