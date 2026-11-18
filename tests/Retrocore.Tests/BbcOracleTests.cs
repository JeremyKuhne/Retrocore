// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Machines.Acorn;
// An instruction's address with the registers before it, the instruction, and its address when it is an absolute
// access to SHEILA (else 0). The instruction is taken as it runs: the paged ROMs share addresses, and the DFS rewrites
// its NMI handler in RAM. The B flag is left out, since MAME shows it set.
using Row = (
    ushort Pc,
    byte A,
    byte X,
    byte Y,
    byte P,
    byte S,
    Retrocore.Cpu.M6502.Instruction Op,
    ushort Sheila);

namespace Retrocore.Tests;

/// <summary>
///  The BBC Micro against MAME: from power-on to BASIC's prompt and on, the ROMs must run the same instructions with
///  the same registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\BbcOracle.lua</c>,
///   which traces with its debugger. Its Model B runs without the disk interface and the speech chip, so both
///   machines have MOS 1.20 and BASIC II alone. The tests are inconclusive without MAME or the ROM set.
///  </para>
///  <para>
///   MAME halves the CPU's clock for a slow access, where the BBC stretches the cycle by one or two 2 MHz cycles by
///   phase, and its 6845 and VIAs keep their own time. So interrupts come at other times, and loops that wait on the
///   hardware run other numbers of times. The comparison leaves out each interrupt, from the vector's target to its
///   RTI, and counts a loop repeated back to back once.
///  </para>
/// </remarks>
[TestClass]
public class BbcOracleTests
{
    /// <summary>
    ///  From power-on through clearing memory, the banner and BASIC's start to the wait for a key: without a disk
    ///  interface, and with the 8271 and DNFS 1.20, MAME's default, whose DFS sets the controller up and finds no disk.
    /// </summary>
    /// <param name="filingSystem">The filing system ROM, or empty for none and no disk interface.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow("")]
    [DataRow("dnfs120.rom")]
    public void BootMatchesMame(string filingSystem)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(BbcMachineTests.RomDirectory)), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "bbcb.zip")))
        {
            Assert.Inconclusive("MAME or the BBC ROM sets are missing.");
        }

        bool disks = filingSystem.Length != 0;
        BbcMachine machine = BbcMachineTests.Machine(filingSystem: disks ? filingSystem : null, diskInterface: disks);
        ushort irq = (ushort)(machine.Bus.Peek(0xFFFE) | (machine.Bus.Peek(0xFFFF) << 8));
        List<Row> mameRows = RunMame(mame, roms, seconds: 2, diskInterface: disks);
        List<Row> expected = Collapse(Normalize(WithoutInterrupts(mameRows, irq, machine), machine));
        List<Row> actual = Collapse(Normalize(WithoutInterrupts(RunMachine(machine, seconds: 2), irq, machine), machine));
        expected.Count.Should().BeGreaterThan(5_000, "MAME reached BASIC");

        Compare(expected, actual);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == ">");
    }

    /// <summary>
    ///  With the Welcome disk in drive 0, *CAT typed at 2 seconds: the DFS's commands to the 8271, its NMI-driven
    ///  reading of the catalogue and the listing match MAME's, outside the interrupts.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void CatalogueMatchesMame()
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(BbcMachineTests.RomDirectory)), "mame");
        string zip = Path.Join(ExternalTestData.Root, "bbc-media", "extract", "bbcb_flop", "bbcb_flop", "welcome.zip");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "bbcb.zip")) || !File.Exists(zip))
        {
            Assert.Inconclusive("MAME, the BBC ROM sets or the bbcb_flop software list are missing.");
        }

        string work = Directory.CreateTempSubdirectory("retrocore-ssd").FullName;
        try
        {
            string ssd = Path.Join(work, "welcome.ssd");
            byte[] image = BbcDiskTests.Welcome();
            File.WriteAllBytes(ssd, image);
            BbcMachine machine = BbcMachineTests.Machine(filingSystem: "dnfs120.rom");
            machine.Drives[0].Insert(Retrocore.Media.Acorn.AcornDiskImage.Read(image, doubleSided: false), ssd, "SSD");
            ushort irq = (ushort)(machine.Bus.Peek(0xFFFE) | (machine.Bus.Peek(0xFFFF) << 8));
            List<Row> mameRows = RunMame(mame, roms, 6, diskInterface: true, disk: ssd, keys: "*CAT\r", keysAt: 2);
            List<Row> ourRows = RunMachine(machine, 6, "*CAT\r", keysAt: 2);
            List<Row> expected = Collapse(Normalize(WithoutInterrupts(mameRows, irq, machine), machine));
            List<Row> actual = Collapse(Normalize(WithoutInterrupts(ourRows, irq, machine), machine));
            Compare(expected, actual);
            machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "    !B                  !BOOT");
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    // Fails at the first row that differs, or when one run is more than a loop's worth longer.
    private static void Compare(List<Row> expected, List<Row> actual)
    {
        int count = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < count; i++)
        {
            if (expected[i] != actual[i])
            {
                string context = string.Join(
                    '\n',
                    Enumerable.Range(Math.Max(0, i - 12), Math.Min(16, count - Math.Max(0, i - 12)))
                        .Select(j => $"{Show(expected[j])}    {Show(actual[j])}"));

                Assert.Fail($"Instruction {i} of {count} differs (MAME, then ours):\n{context}");
            }
        }

        // Both end waiting for a key, in a loop each counted once.
        string tails = string.Join(
            '\n',
            expected.TakeLast(8).Select(Show).Zip(actual.TakeLast(8).Select(Show), (mame, ours) => $"{mame}    {ours}"));

        string counts = $"MAME has {expected.Count} rows and ours {actual.Count}; the last of each:";
        Math.Abs(expected.Count - actual.Count).Should().BeLessThan(32, counts + "\n" + tails);
    }

    private static string Show(Row row) =>
        $"{row.Pc:X4} {row.A:X2} {row.X:X2} {row.Y:X2} {row.P:X2} {row.S:X2}";

    // Leaves out each interrupt: from the row at the IRQ vector's target through the RTI that ends it. Our machine
    // steps the interrupt and the handler's first instruction (the MOS's STA $FC) together, so its first row is the
    // next one, two bytes on. MAME logs the instruction it is about to run when it takes an interrupt instead, then
    // again after the RTI, so the row after an interrupt is dropped when it repeats the one before.
    private static List<Row> WithoutInterrupts(IEnumerable<Row> rows, ushort irq, BbcMachine machine)
    {
        // The MOS's handlers enable interrupts again for slow work, so interrupts nest. The DFS's NMI handler, for
        // each byte of a disk transfer, starts at the NMI vector's target; ours shows its first row an instruction in.
        ushort nmi = (ushort)(machine.Bus.Peek(0xFFFA) | (machine.Bus.Peek(0xFFFB) << 8));
        // An interrupt between the IRQ handler's first two instructions returns to the second, which is no new
        // interrupt: each interrupt keeps the row before it, and its RTI brings that back as the row before. Both
        // traces log the instruction about to run when an interrupt is taken instead, and again after the RTI; that
        // row starts nothing, and an RTI logged that way had not returned yet, so its return is taken back.
        List<Row> kept = [];
        Stack<ushort> interrupted = [];
        bool returned = false;
        bool resumed = false;
        ushort previous = 0;
        (ushort Popped, ushort Pc)? lastReturn = null;
        foreach (Row row in rows)
        {
            bool inNmi = row.Pc - nmi is >= 0 and < 4;
            bool wasInNmi = previous - nmi is >= 0 and < 4;
            bool repeat = resumed && row.Pc == previous;
            bool entry = !repeat
                && (row.Pc == irq || (row.Pc == irq + 2 && previous != irq) || (inNmi && !wasInNmi));

            if (entry && lastReturn is { } undone)
            {
                interrupted.Push(undone.Popped);
                previous = undone.Pc;
                returned = false;
            }

            resumed = false;
            lastReturn = null;
            if (entry) { interrupted.Push(previous); }

            if (interrupted.Count > 0)
            {
                if (row.Op == Instruction.RTI)
                {
                    lastReturn = (interrupted.Peek(), row.Pc);
                    previous = interrupted.Pop();
                    returned = interrupted.Count == 0;
                    resumed = true;
                }
                else
                {
                    previous = row.Pc;
                }

                continue;
            }

            previous = row.Pc;

            if (returned && kept.Count != 0 && kept[^1] == row)
            {
                returned = false;
                continue;
            }

            returned = false;
            kept.Add(row);
        }

        return kept;
    }

    // The instructions that set overflow, and negative.
    private static readonly HashSet<Instruction> s_setOverflow =
        [Instruction.ADC, Instruction.SBC, Instruction.BIT, Instruction.CLV, Instruction.PLP, Instruction.RTI];

    // The instructions that write the accumulator (the shifts only in their accumulator form).
    private static readonly HashSet<Instruction> s_writeAccumulator =
    [
        Instruction.LDA, Instruction.PLA, Instruction.TXA, Instruction.TYA, Instruction.AND, Instruction.ORA,
        Instruction.EOR, Instruction.ADC, Instruction.SBC
    ];

    private static readonly HashSet<Instruction> s_setNegative =
    [
        Instruction.LDA, Instruction.LDX, Instruction.LDY, Instruction.TAX, Instruction.TAY, Instruction.TXA,
        Instruction.TYA, Instruction.TSX, Instruction.PLA, Instruction.PLP, Instruction.INX, Instruction.INY,
        Instruction.DEX, Instruction.DEY, Instruction.INC, Instruction.DEC, Instruction.AND, Instruction.ORA,
        Instruction.EOR, Instruction.ADC, Instruction.SBC, Instruction.CMP, Instruction.CPX, Instruction.CPY,
        Instruction.BIT, Instruction.ASL, Instruction.LSR, Instruction.ROL, Instruction.ROR, Instruction.RTI
    ];

    // The system VIA's interrupt flags show when its timers ran out, which is timing: after a BIT of them ($FE4D),
    // negative and overflow are left out until an instruction sets each again. The 8271's drive status shows the
    // index hole, which is where the disk is in its turn, and drive 1's ready line, which MAME's board ties to the
    // motor where ours, like a drive, is ready only with a disk in: after a read drive status command, the result's
    // bits 4 and 6 are left out of the accumulator until it is next written.
    private static IEnumerable<Row> Normalize(IEnumerable<Row> rows, BbcMachine machine)
    {
        bool negative = false;
        bool overflow = false;
        bool statusCommand = false;
        bool index = false;
        Row? previous = null;
        foreach (Row row in rows)
        {
            if (previous is { } last)
            {
                Instruction instruction = last.Op;
                if (instruction == Instruction.BIT && last.Sheila == 0xFE4D)
                {
                    negative = overflow = true;
                }
                else
                {
                    if (s_setOverflow.Contains(instruction)) { overflow = false; }
                    if (s_setNegative.Contains(instruction)) { negative = false; }
                }

                bool command = instruction == Instruction.STA && last.Sheila == 0xFE80;
                bool result = instruction == Instruction.LDA && last.Sheila == 0xFE81;
                if (command) { statusCommand = (last.A & 0x3F) == 0x2C; }
                if (result)
                {
                    index = statusCommand;
                    statusCommand = false;
                }
                else if (s_writeAccumulator.Contains(instruction))
                {
                    index = false;
                }
            }

            previous = row;
            byte mask = (byte)((negative ? 0x80 : 0) | (overflow ? 0x40 : 0));
            yield return row with { P = (byte)(row.P & ~mask), A = (byte)(index ? row.A & ~0x50 : row.A) };
        }
    }

    // Drops every repeat of a run of up to 32 rows that comes straight after itself: the MOS's wait for a key is 24.
    private static List<Row> Collapse(IEnumerable<Row> rows)
    {
        List<Row> collapsed = [];
        foreach (Row row in rows)
        {
            collapsed.Add(row);
            for (int length = 1; length <= 32 && collapsed.Count >= 2 * length; length++)
            {
                int start = collapsed.Count - length;
                bool repeat = true;
                for (int i = 0; i < length && repeat; i++)
                {
                    repeat = collapsed[start + i] == collapsed[start - length + i];
                }

                if (repeat)
                {
                    collapsed.RemoveRange(start, length);
                    break;
                }
            }
        }

        return collapsed;
    }

    private static List<Row> RunMachine(BbcMachine machine, int seconds, string? keys = null, int keysAt = 0)
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

        OpCode[] opcodes = OpcodeTable.Get(ProcessorVariant.Mos6502).ToArray();
        List<Row> rows = [];
        long end = (long)seconds * BbcTiming.CpuHertz;
        long typeAt = (long)keysAt * BbcTiming.CpuHertz;
        while (machine.Bus.Cycles < end)
        {
            if (keys is not null && machine.Bus.Cycles >= typeAt)
            {
                foreach (char key in keys) { machine.Keyboard.Type((byte)key); }
                keys = null;
            }

            ProcessorRegisters r = machine.Processor.Registers;
            OpCode opcode = opcodes[machine.Bus.Peek(r.ProgramCounter)];
            int low = machine.Bus.Peek((ushort)(r.ProgramCounter + 1));
            int high = machine.Bus.Peek((ushort)(r.ProgramCounter + 2));
            ushort sheila = opcode.AddressMode == AddressMode.Absolute && high == 0xFE ? (ushort)(0xFE00 | low) : (ushort)0;
            byte status = (byte)((byte)r.Status & 0xEF);
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, status, r.StackPointer, opcode.Instruction, sheila));
            machine.StepInstruction();
        }

        return rows;
    }

    private static List<Row> RunMame(
        string mame,
        string roms,
        int seconds,
        bool diskInterface,
        string? disk = null,
        string? keys = null,
        int keysAt = 0)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "trace.log");
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                "bbcb", "-fdc", diskInterface ? "acorn8271" : "", "-vsp", "", "-rompath", roms, "-cfg_directory", work, "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-debug", "-debugger", "none", "-seconds_to_run", (seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool("BbcOracle.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            if (disk is not null)
            {
                start.ArgumentList.Add("-flop1");
                start.ArgumentList.Add(disk);
            }

            if (keys is not null)
            {
                start.Environment["RETRO_KEYS"] = keys.Replace("\r", "\\r", StringComparison.Ordinal);
                start.Environment["RETRO_KEYS_AT"] = keysAt.ToString(CultureInfo.InvariantCulture);
            }

            start.Environment["RETRO_END"] = seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                // Both pipes drain as MAME writes, so a full one cannot stall it; the timeout holds while they do.
                Task stdout = process.StandardOutput.ReadToEndAsync();
                Task stderr = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(300_000))
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit();
                    Assert.Fail("MAME did not finish in five minutes.");
                }

                Task.WaitAll(stdout, stderr);
            }

            File.Exists(output).Should().BeTrue("the Lua script traces");
            List<Row> rows = [];
            foreach (string line in File.ReadLines(output))
            {
                int bar = line.IndexOf('|', StringComparison.Ordinal);
                if (bar < 0 || line.Length < bar + 5) { continue; }
                ushort pc = ushort.Parse(line.AsSpan(bar + 1, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                string[] registers = line[..bar].Split(' ');
                rows.Add((
                    pc,
                    Hex(registers[0]),
                    Hex(registers[1]),
                    Hex(registers[2]),
                    (byte)(Hex(registers[3]) & 0xEF),
                    (byte)(int.Parse(registers[4], NumberStyles.HexNumber, CultureInfo.InvariantCulture) & 0xFF),
                    Mnemonic(line[(bar + 7)..]),
                    Sheila(line[(bar + 7)..])));
            }

            return rows;
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }

        static byte Hex(string text) => byte.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);

        // MAME's disassembly: "lda $fe81", "bit $fe4d", "rti".
        static Instruction Mnemonic(string text) =>
            Enum.TryParse(text.Split(' ')[0], ignoreCase: true, out Instruction instruction) ? instruction : Instruction.JAM;

        static ushort Sheila(string text)
        {
            string[] parts = text.Split(' ');
            return parts.Length == 2 && parts[1].Length == 5 && parts[1].StartsWith("$fe", StringComparison.Ordinal)
                ? ushort.Parse(parts[1].AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
                : (ushort)0;
        }
    }

    private static string FindTool(string name)
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            string candidate = Path.Join(directory.FullName, "tools", name);
            if (File.Exists(candidate)) { return candidate; }
        }

        throw new FileNotFoundException(name);
    }
}
