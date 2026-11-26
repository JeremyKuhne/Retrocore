// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Media.Commodore;
// An instruction's address with the registers before it; the B flag is left out, since MAME shows it set.
using Row = (ushort Pc, byte A, byte X, byte Y, byte P, byte S);
// A trace split into the main program and the interrupt handlers' passes.
using Streams = (
    System.Collections.Generic.List<(ushort Pc, byte A, byte X, byte Y, byte P, byte S)> Main,
    System.Collections.Generic.List<System.Collections.Generic.List<(ushort Pc, byte A, byte X, byte Y, byte P, byte S)>> Handlers);

namespace Retrocore.Tests;

/// <summary>
///  The 1541's and 1540's DOS against MAME's <c>c1541</c> and <c>c1540</c> on its <c>vic20</c>: the drive must run
///  the same instructions, with the same registers until the DOS first reads its ports.
/// </summary>
/// <remarks>
///  <para>
///   MAME runs <c>tools\Pet4040Oracle.lua</c> with the drive's 6502 (<c>:iec8:c1541:ucd5</c>) as the one traced.
///   Every interrupt handler of DOS 2.6 returns: ATN only sets a flag the main loop serves, and the controller's
///   timer interrupt runs the disk jobs. Where each interrupt lands depends on the loops' phase to the cycle, so each
///   trace is split into two streams, compared one with the other: the main program with the handlers taken out, and
///   the controller's passes, which run the disk jobs, on their own. In each, a loop repeated back to back counts once, by its last pass, as
///   in the PET drive oracle (<see cref="Pet4040OracleTests"/>). MAME types at its own pace, so the VIC-20 calls the
///   drive at another moment, and its jobs are taken by other passes; so the passes may skip up to 100 on either
///   side to agree again, and only so many in all.
///  </para>
///  <para>
///   The main program's registers must agree until the first interrupt, or the first read of a port's pins, which
///   MAME models otherwise (see <c>LooseFromTheFirstPortRead</c>); after that only the addresses, since the two
///   computers' handshakes race the drive's polling differently.
///  </para>
/// </remarks>
[TestClass]
public class Vic20DiskOracleTests
{
    /// <summary>
    ///  From power-on, the DOS's RAM and ROM tests and its start-up, to the wait for the VIC-20, with no disk.
    /// </summary>
    /// <param name="model">The drive.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow("1541")]
    [DataRow("1540")]
    public void PowerOnMatchesMame(string model) => Compare(model, seconds: 2, disk: null, text: null);

    /// <summary>
    ///  With the Data 20 demo disk in the 1541, <c>LOAD "$",8</c> reads its directory.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Not the 1540: MAME's own 1540 on its <c>vic20</c> takes the LISTEN under ATN as <c>$2A</c>, not the
    ///   <c>$28</c> the VIC-20 sends, and the load ends in <c>?DEVICE NOT PRESENT</c>; ours lists the directory
    ///   (<see cref="Vic20DiskTests.DirectoryLists"/>).
    ///  </para>
    /// </remarks>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DirectoryMatchesMame() =>
        Compare("1541", seconds: 9, Vic20DiskTests.Image("data20dm"), "LOAD\"$\",8\r");

    private static void Compare(string model, int seconds, byte[]? disk, string? text)
    {
        const int typeAt = 3;
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Vic20MachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, $"c{model}.zip")) || !File.Exists(Path.Join(roms, "vic20.zip")))
        {
            Assert.Inconclusive($"MAME or the VIC-20 and {model} ROM sets are missing.");
        }

        (Vic20Machine machine, Cbm1541 unit) = Vic20DiskTests.Machine(model);
        string work = Directory.CreateTempSubdirectory("retrocore-1541").FullName;
        try
        {
            List<string> arguments = ["vic20", "-iec8", $"c{model}"];
            if (disk is not null)
            {
                bool g64 = G64Format.IsG64(disk);
                string image = Path.Join(work, g64 ? "disk.g64" : "disk.d64");
                File.WriteAllBytes(image, disk);
                arguments.AddRange(["-flop", image]);
                unit.Drive.Insert(g64 ? G64Format.Read(disk) : D64Format.Read(disk), "disk", g64 ? "G64" : "D64");
            }

            Dictionary<string, string> environment = [];
            environment["RETRO_CPU"] = $":iec8:c{model}:ucd5";
            if (text is not null)
            {
                environment["RETRO_TYPE"] = text.Replace("\r", "\\n", StringComparison.Ordinal);
                environment["RETRO_TYPE_AT"] = typeAt.ToString(CultureInfo.InvariantCulture);
            }

            ushort irq = (ushort)(unit.Bus.Peek(0xFFFE) | (unit.Bus.Peek(0xFFFF) << 8));
            Streams expected = Split(
                PetOracleTests.RunMame(mame, arguments, roms, seconds, "Pet4040Oracle.lua", environment),
                irq,
                unit.Bus.Peek);

            Streams actual = Split(Run(machine, unit, seconds, text, typeAt), irq, unit.Bus.Peek);
            expected.Main.Count.Should().BeGreaterThan(300, "MAME traced the DOS");
            if (text is not null)
            {
                string[] screen = machine.ReadTextScreen();
                screen.Should().Contain(line => line.StartsWith("LOADING", StringComparison.Ordinal), string.Join('\n', screen));
            }

            int main = Math.Min(expected.Main.Count, actual.Main.Count);
            Pet4040OracleTests.Match("the main program", expected.Main[..main], actual.Main[..main], registers: true);
            MatchPasses(expected.Handlers, actual.Handlers);
            Math.Abs(expected.Handlers.Count - actual.Handlers.Count).Should().BeLessThanOrEqualTo(
                expected.Handlers.Count / 50,
                "the DOS takes as many interrupts");
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    // The controller's routine, which the interrupt handler calls at $FE7C for VIA 2's timer, and where it returns.
    private const ushort Controller = 0xF2B0;
    private const ushort ControllerReturn = 0xFE7F;

    // Takes the interrupt handlers' rows out of the main program's: from the IRQ vector's target to the RTI. Of the
    // handlers, the controller's passes are kept, each its own list; the rest only sets the ATN flag, at a moment the
    // VIC-20 decides. MAME
    // logs the instruction it takes an interrupt at, then again after the RTI, so that repeat is dropped; ours takes the
    // interrupt with the handler's first instruction, so the target's row is left out of the handlers. Each stream's
    // loops are collapsed, and the main program's rows from the first interrupt or the first port read are loose.
    private static Streams Split(IEnumerable<Row> rows, ushort irq, Func<ushort, byte> peek)
    {
        List<Row> main = [];
        List<List<Row>> handlers = [];
        List<Row> pass = [];
        int interrupts = 0;
        bool controller = false;
        bool inside = false;
        bool returned = false;
        foreach (Row row in rows)
        {
            if (!inside && (row.Pc == irq || row.Pc == irq + 1))
            {
                inside = true;
                interrupts++;
            }

            if (inside)
            {
                // The controller's pass: from its start to its return into the handler.
                if (row.Pc == Controller) { controller = true; }
                if (controller && row.Pc == ControllerReturn)
                {
                    controller = false;
                    handlers.Add(Collapse(pass));
                    pass = [];
                }

                if (controller) { pass.Add(row with { P = (byte)(row.P | Pet4040OracleTests.Loose) }); }
                if (peek(row.Pc) == 0x40)
                {
                    inside = false;
                    returned = true;
                }

                continue;
            }

            if (returned && main.Count != 0 && main[^1].Pc == row.Pc)
            {
                returned = false;
                continue;
            }

            returned = false;
            main.Add(interrupts == 0 ? row : row with { P = (byte)(row.P | Pet4040OracleTests.Loose) });
        }

        return (Collapse(LooseFromTheFirstPortRead(main, peek)), handlers);
    }

    // The controller's passes agree by address. Where they part, up to 100 passes (1.5 seconds) are skipped on either
    // side to the first place two in a row agree again: a job taken sooner on one side, as MAME types at its own pace.
    private static void MatchPasses(List<List<Row>> expected, List<List<Row>> actual)
    {
        const int Window = 100;
        int i = 0;
        int j = 0;
        int skipped = 0;
        while (i < expected.Count - 1 && j < actual.Count - 1)
        {
            if (Same(expected[i], actual[j]))
            {
                i++;
                j++;
                continue;
            }

            (int, int)? resync = null;
            for (int skip = 1; skip <= Window && resync is null; skip++)
            {
                foreach ((int a, int b) in (ReadOnlySpan<(int, int)>)[(skip, 0), (0, skip)])
                {
                    if (i + a + 2 > expected.Count || j + b + 2 > actual.Count) { continue; }
                    if (Same(expected[i + a], actual[j + b]) && Same(expected[i + a + 1], actual[j + b + 1]))
                    {
                        resync = (a, b);
                        break;
                    }
                }
            }

            if (resync is null)
            {
                List<Row> e = expected[i];
                List<Row> o = actual[j];
                int shorter = Math.Min(e.Count, o.Count);
                int first = Enumerable.Range(0, shorter).FirstOrDefault(k => e[k].Pc != o[k].Pc, shorter);
                string context = string.Join(
                    '\n',
                    Enumerable.Range(Math.Max(0, first - 6), 10)
                        .Select(k => $"{(k < e.Count ? PetOracleTests.Show(e[k]) : "")}    {(k < o.Count ? PetOracleTests.Show(o[k]) : "")}"));

                Assert.Fail($"Interrupt pass {i} (ours {j}) differs at row {first} (MAME, then ours):\n{context}");
            }

            (int skipE, int skipA) = resync.Value;
            i += skipE;
            j += skipA;
            skipped += skipE + skipA;
        }

        skipped.Should().BeLessThanOrEqualTo(Window + (expected.Count / 20), "the passes agree but where a job is taken");

        static bool Same(List<Row> first, List<Row> second) =>
            first.Count == second.Count && first.Select(row => row.Pc).SequenceEqual(second.Select(row => row.Pc));
    }

    // As the PET drive oracle's Collapse, for loops of up to 64 rows: the DOS's idle loop is longer than 8, and the
    // VIC-20's ATN or a job's end comes in one pass of it or the next, as the two computers race. A pass whose
    // addresses repeat the pass before it replaces it, its first row marked loose.
    private static List<Row> Collapse(List<Row> rows)
    {
        const int Longest = 64;
        List<Row> collapsed = [];
        foreach (Row row in rows)
        {
            collapsed.Add(row);
            for (int length = 1; length <= Longest && collapsed.Count >= 2 * length; length++)
            {
                int start = collapsed.Count - length;
                if (collapsed[^1].Pc != collapsed[start - 1].Pc) { continue; }
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
                        P = (byte)(collapsed[start - length].P | Pet4040OracleTests.Loose)
                    };

                    break;
                }
            }
        }

        return collapsed;
    }

    private static List<Row> Run(Vic20Machine machine, Cbm1541 unit, int seconds, string? text, int typeAt)
    {
        // The registers' power-on contents are happenstance; take MAME's once the reset sequence is done.
        while (!unit.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        ProcessorRegisters start = unit.Processor.Registers;
        start.Accumulator = 0;
        start.X = 0x80;
        start.Y = 0;
        start.StackPointer = 0xFD;
        start.Status = StatusRegister.IRQBDisable | StatusRegister.Zero | (StatusRegister)0x20;
        unit.Processor.Registers = start;

        List<Row> rows = [Row(unit)];
        ulong end = (ulong)(seconds * machine.CpuHertz);
        ulong typeCycle = (ulong)(typeAt * machine.CpuHertz);
        ulong driveCycles = unit.Processor.CycleCount;
        bool boundary = true;
        bool typed = text is null;
        for (ulong cycle = 0; cycle < end; cycle++)
        {
            if (!typed && cycle == typeCycle)
            {
                foreach (char c in text ?? "") { machine.Keyboard.Type((byte)c); }
                typed = true;
            }

            machine.StepCycle();
            if (unit.Processor.CycleCount == driveCycles) { continue; }
            driveCycles = unit.Processor.CycleCount;
            if (!unit.Processor.IsInstructionBoundary)
            {
                boundary = false;
            }
            else if (!boundary)
            {
                rows.Add(Row(unit));
                boundary = true;
            }
        }

        return rows;
    }

    // The registers count until the DOS first reads a VIA's port B ($1800 or $1C00). Before the DOS sets their
    // directions, those pins float high here, as the TTL inputs they drive hold them, and read low in MAME; VIA 2's
    // also run the motor, so BYTE READY sets V, and MAME's gate array reports SYNC before it has run. From that read
    // on, only the addresses count, as after an interrupt; and V never does before the first, as the DOS tests it only
    // in disk jobs, after CLV.
    private static List<Row> LooseFromTheFirstPortRead(List<Row> rows, Func<ushort, byte> peek)
    {
        List<Row> kept = [];
        ushort previous = 0;
        bool loose = false;
        foreach (Row row in rows)
        {
            int operand = peek((ushort)(previous + 1)) | (peek((ushort)(previous + 2)) << 8);
            loose |= operand is 0x1800 or 0x1C00 && peek(previous) is 0xAD or 0xAE or 0xAC or 0x2C;
            byte p = (byte)(row.P & ~0x40);
            kept.Add(row with { P = loose ? (byte)(p | Pet4040OracleTests.Loose) : p });
            previous = row.Pc;
        }

        return kept;
    }

    private static Row Row(Cbm1541 unit)
    {
        ProcessorRegisters r = unit.Processor.Registers;
        return (r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer);
    }
}
