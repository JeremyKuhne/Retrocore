// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Machines.Atari;

// An instruction's address with the registers before it, the instruction, and its address when it is an absolute
// access to the chips at $D000-$D7FF (else 0). The B flag is left out, since MAME shows it set.
using Row = (
    ushort Pc,
    byte A,
    byte X,
    byte Y,
    byte P,
    byte S,
    Retrocore.Cpu.M6502.Instruction Op,
    ushort Io);

namespace Retrocore.Tests;

/// <summary>
///  The Atari 800 against MAME: from power-on, the OS (and BASIC) must run the same instructions with the same
///  registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\AtariOracle.lua</c>,
///   which traces with its debugger. MAME's 800 runs with 48 KB and nothing on the serial bus, as ours does. The tests
///   are inconclusive without MAME or the ROM sets.
///  </para>
///  <para>
///   MAME's ANTIC takes each scan line's DMA cycles in one lump rather than on their cycles, so its interrupts come at
///   other times, and loops that wait on the hardware run other numbers of times. The comparison leaves out each
///   interrupt, from the vector's target to its RTI, counts a loop repeated back to back once, and leaves out of the
///   registers what a read of the beam's position, the random number generator or the interrupt status gave.
///  </para>
/// </remarks>
[TestClass]
public class AtariOracleTests
{
    // The chips' registers whose values depend on time: VCOUNT, NMIST, RANDOM, IRQST, SKSTAT and KBCODE, and
    // CONSOL, whose speaker bit the vertical blank interrupt sets.
    private static readonly HashSet<ushort> s_timed = [0xD40B, 0xD40F, 0xD20A, 0xD20E, 0xD20F, 0xD209, 0xD01F];

    /// <summary>
    ///  From power-on through the OS's start, its try to boot a disk and Memo Pad, or BASIC's start to <c>READY</c>.
    /// </summary>
    /// <param name="basic">Whether Atari BASIC (rev. C) is in the left slot.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(data: false, DisplayName = "Memo Pad")]
    [DataRow(data: true, DisplayName = "BASIC")]
    public void BootMatchesMame(bool basic)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(AtariMachineTests.RomDirectory)), "mame");
        string cartridge = Path.Join(AtariMachineTests.BasicDirectory, "basic-revc.rom");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "a800.zip")) || (basic && !File.Exists(cartridge)))
        {
            Assert.Inconclusive("MAME, the Atari ROM sets or Atari BASIC are missing.");
        }

        AtariMachine machine = AtariMachineTests.Machine(basic: basic ? 'C' : null);
        List<Row> mameRows = RunMame(mame, roms, seconds: 4, basic ? cartridge : null);
        List<Row> expected = Collapse(Normalize(WithoutInterrupts(mameRows, machine)));
        List<Row> actual = Collapse(Normalize(WithoutInterrupts(RunMachine(machine, seconds: 4), machine)));
        expected.Count.Should().BeGreaterThan(5_000, "MAME ran the OS");

        Compare(expected, actual);
    }

    /// <summary>
    ///  With DOS 2.0S's master disk in D1: and MAME's command-level disk drive (<c>-sio fdc</c>), the OS boots DOS, which
    ///  loads DUP.SYS: the same instructions, with the drives' different timing left out with the interrupts.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   MAME's drive sometimes takes a command frame as a bad one and answers Error, where a drive ignores a bad frame
    ///   (Altirra 9.1), so its OS retries. The comparison stops at MAME's first Error or NAK, which the OS's SIO
    ///   routine compares at <c>$EA40</c>.
    ///  </para>
    /// </remarks>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DosBootMatchesMame()
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(AtariMachineTests.RomDirectory)), "mame");
        string disk = Path.Join(ExternalTestData.Root, "atari8-media", "810_Master_Disk_DOS_2.0s_1980_Atari.atr");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "a800.zip")) || !File.Exists(disk))
        {
            Assert.Inconclusive("MAME, the Atari ROM sets or DOS 2.0S's master disk are missing.");
        }

        // MAME's -sio fdc drive answers at the command level, as ours does.
        AtariMachine machine = AtariDiskTests.Machine(kind: AtariDiskDriveKind.CommandLevel);
        List<Row> mameRows = RunMame(mame, roms, seconds: 8, cartridge: null, disk: disk);
        List<Row> expected = Collapse(Normalize(WithoutInterrupts(mameRows, machine)));
        List<Row> actual = Collapse(Normalize(WithoutInterrupts(RunMachine(machine, seconds: 8), machine)));
        expected.Count.Should().BeGreaterThan(5_000, "MAME ran the OS");

        // MAME's drive answers faster or slower than ours, so the two finish at different points; compare what both ran,
        // up to MAME's first error reply.
        int error = expected.FindIndex(row => row.Pc == 0xEA40 && row.A is 0x45 or 0x4E);
        int count = Math.Min(error < 0 ? expected.Count : error, actual.Count);
        count.Should().BeGreaterThan(200_000, "DOS loads before any difference");
        Compare(expected[..count], actual[..count]);
        machine.Bus.Peek(0x0A).Should().Be(0x9F, "DOS set DOSVEC");
    }

    /// <summary>
    ///  An 810 on the serial bus, switched on with the computer: its 6507 runs the same instructions with the same
    ///  registers as MAME's <c>atari810</c> through its start-up: the RIOT and the FD1771 set up, the head stepped out
    ///  40 tracks against the stop and back in to track 39, each step timed by the RIOT's timer.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The comparison ends at the firmware's first read of the RIOT's port A (<c>$0C30</c>, the write-protect
    ///   sensor). MAME's 810 has no floppy drive attached, and its port A reads <c>$FF</c> from then on: write-protected,
    ///   with the FD1771's DRQ and INTRQ always high, so it takes sectors of nothing. Disk operations are tested against
    ///   DOS instead (<see cref="AtariDiskTests"/>).
    ///  </para>
    /// </remarks>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Atari810PowerOnMatchesMame()
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Path.GetDirectoryName(AtariMachineTests.RomDirectory)), "mame");
        AtariRoms atariRoms = AtariRoms.LoadFromDirectory(AtariMachineTests.RomDirectory);
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "atari810.zip")) || atariRoms.DiskDrive.IsEmpty)
        {
            Assert.Inconclusive("MAME or the Atari and 810 ROM sets are missing.");
        }

        const int Seconds = 1;
        List<Row> mameRows = RunMame(mame, roms, Seconds, cartridge: null, sio: "a810", cpu: ":sio:a810:fdcpu");
        List<Row> expected = Collapse(WithoutDataOut(mameRows));

        // The drive warms up when it's built; switch both on again together, as MAME does.
        AtariMachine machine = new(atariRoms, diskDrives: 1);
        Atari810 drive = (Atari810)machine.Drives[0];
        drive.PowerOn();
        machine.PowerOn();

        // POKEY's output bit powers on in no fixed state; MAME's is low.
        machine.Bus.Pokey.SerialDataBit = false;
        List<Row> actual = Collapse(WithoutDataOut(RunDrive(machine, drive, Seconds)));
        int end = expected.FindIndex(row => row.Pc == 0x0C30);
        end.Should().BeGreaterThan(40_000, "MAME ran the drive's start-up");
        actual.Count.Should().BeGreaterThan(end);
        Compare(expected[..(end + 1)], actual[..(end + 1)]);
    }

    private static List<Row> RunDrive(AtariMachine machine, Atari810 drive, int seconds)
    {
        OpCode[] opcodes = OpcodeTable.Get(ProcessorVariant.Mos6502).ToArray();
        List<Row> rows = [];
        drive.InstructionStarting = () =>
        {
            ProcessorRegisters r = drive.Processor.Registers;
            if (rows.Count == 0)
            {
                // The registers' power-on contents are happenstance; take MAME's.
                r.Accumulator = 0;
                r.X = 0x80;
                r.Y = 0;
                r.StackPointer = 0xFD;
                r.Status = (StatusRegister)0x36;
                drive.Processor.Registers = r;
            }

            byte status = (byte)((byte)r.Status & 0xEF);
            OpCode opcode = opcodes[drive.Bus.Peek(r.ProgramCounter)];
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, status, r.StackPointer, opcode.Instruction, 0));
        };

        long end = (long)seconds * AtariTiming.CpuHertz(AtariVideoStandard.Ntsc);
        while (machine.Bus.Cycles < end) { machine.StepCycle(); }
        drive.InstructionStarting = null;
        return rows;
    }

    // The step routine's read of port B (at $08F2) shows the computer's data-out line in bit 7, which changes when the
    // OS first sets SKCTL: some milliseconds apart in the two, as MAME's ANTIC takes its DMA in lumps. The routine masks
    // it off at once, so the read's sign is left out.
    private static IEnumerable<Row> WithoutDataOut(IEnumerable<Row> rows)
    {
        ushort previous = 0;
        foreach (Row row in rows)
        {
            yield return previous == 0x08F2 ? row with { A = (byte)(row.A & 0x7F), P = (byte)(row.P & 0x7F) } : row;
            previous = row.Pc;
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

        string tails = string.Join(
            '\n',
            expected.TakeLast(8).Select(Show).Zip(actual.TakeLast(8).Select(Show), (mame, ours) => $"{mame}    {ours}"));

        string counts = $"MAME has {expected.Count} rows and ours {actual.Count}; the last of each:";
        Math.Abs(expected.Count - actual.Count).Should().BeLessThan(64, counts + "\n" + tails);
    }

    private static string Show(Row row) =>
        $"{row.Pc:X4} {row.A:X2} {row.X:X2} {row.Y:X2} {row.P:X2} {row.S:X2} {row.Op}";

    // Leaves out each interrupt, from the row at a vector's target through the RTI that ends it. The OS's handlers
    // enable interrupts again, so they nest. MAME logs the instruction it is about to run when it takes an interrupt
    // instead, then again after the RTI, so that repeat is dropped.
    private static List<Row> WithoutInterrupts(IEnumerable<Row> rows, AtariMachine machine)
    {
        ushort nmi = (ushort)(machine.Bus.Peek(0xFFFA) | (machine.Bus.Peek(0xFFFB) << 8));
        ushort irq = (ushort)(machine.Bus.Peek(0xFFFE) | (machine.Bus.Peek(0xFFFF) << 8));
        List<Row> kept = [];
        Stack<ushort> interrupted = [];
        bool returned = false;
        bool resumed = false;
        ushort previous = 0;
        foreach (Row row in rows)
        {
            bool repeat = resumed && row.Pc == previous;
            bool entry = !repeat && (row.Pc == nmi || row.Pc == irq);

            resumed = false;
            if (entry) { interrupted.Push(previous); }

            if (interrupted.Count > 0)
            {
                if (row.Op == Instruction.RTI)
                {
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

    // The instructions that write each register.
    private static readonly HashSet<Instruction> s_writeA =
    [
        Instruction.LDA, Instruction.PLA, Instruction.TXA, Instruction.TYA, Instruction.AND, Instruction.ORA,
        Instruction.EOR, Instruction.ADC, Instruction.SBC
    ];

    private static readonly HashSet<Instruction> s_writeX = [Instruction.LDX, Instruction.TAX, Instruction.TSX];
    private static readonly HashSet<Instruction> s_writeY = [Instruction.LDY, Instruction.TAY];

    // The instructions whose flags show what they read.
    private static readonly HashSet<Instruction> s_setFlags =
    [
        Instruction.BIT, Instruction.CMP, Instruction.CPX, Instruction.CPY, Instruction.LDA, Instruction.LDX,
        Instruction.LDY, Instruction.AND, Instruction.ORA, Instruction.EOR
    ];

    // After a read of a timed register, what it gave is left out: the register it went to and the flags, until an
    // instruction writes them again.
    private static IEnumerable<Row> Normalize(IEnumerable<Row> rows)
    {
        bool a = false, x = false, y = false, flags = false;
        Row? previous = null;
        foreach (Row row in rows)
        {
            if (previous is { } last)
            {
                Instruction op = last.Op;
                bool timed = s_timed.Contains(last.Io);
                if (s_writeA.Contains(op))
                {
                    a = timed && op is Instruction.LDA or Instruction.AND or Instruction.ORA or Instruction.EOR;
                }

                if (s_writeX.Contains(op)) { x = timed && op == Instruction.LDX; }
                if (s_writeY.Contains(op)) { y = timed && op == Instruction.LDY; }
                if (op is Instruction.TAX) { x = a; }
                if (op is Instruction.TAY) { y = a; }
                if (op is Instruction.TXA) { a = x; }
                if (op is Instruction.TYA) { a = y; }
                if (s_setFlags.Contains(op)) { flags = timed; }
            }

            previous = row;
            yield return row with
            {
                A = a ? (byte)0 : row.A,
                X = x ? (byte)0 : row.X,
                Y = y ? (byte)0 : row.Y,
                P = flags ? (byte)(row.P & 0x3C) : row.P
            };
        }
    }

    // Drops every repeat of a run of up to 32 rows that comes straight after itself.
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

    private static List<Row> RunMachine(AtariMachine machine, int seconds)
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
        long end = (long)seconds * AtariTiming.CpuHertz(AtariVideoStandard.Ntsc);
        while (machine.Bus.Cycles < end)
        {
            ProcessorRegisters r = machine.Processor.Registers;
            OpCode opcode = opcodes[machine.Bus.Peek(r.ProgramCounter)];
            int low = machine.Bus.Peek((ushort)(r.ProgramCounter + 1));
            int high = machine.Bus.Peek((ushort)(r.ProgramCounter + 2));
            bool io = opcode.AddressMode == AddressMode.Absolute && high is >= 0xD0 and < 0xD8;
            ushort address = io ? (ushort)((high << 8) | low) : (ushort)0;
            byte status = (byte)((byte)r.Status & 0xEF);
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, status, r.StackPointer, opcode.Instruction, address));

            // Our machine runs an interrupt and the handler's first instruction as one step; a read of a vector
            // shows it, and the handler's first row is added as MAME logs it.
            ushort? vector = Step(machine);
            if (vector is ushort at)
            {
                ProcessorRegisters h = machine.Processor.Registers;
                ushort target = (ushort)(machine.Bus.Peek(at) | (machine.Bus.Peek((ushort)(at + 1)) << 8));
                OpCode first = opcodes[machine.Bus.Peek(target)];
                rows.Add((target, h.Accumulator, h.X, h.Y, (byte)((byte)h.Status & 0xEF), h.StackPointer, first.Instruction, 0));
            }
        }

        return rows;
    }

    // Steps an instruction, as AtariMachine.StepInstruction does; returns the vector read if an interrupt came first.
    private static ushort? Step(AtariMachine machine)
    {
        ushort? vector = null;
        bool instruction = machine.Processor.CurrentOpCode is not null;
        for (int index = 0; index < 1024; index++)
        {
            machine.StepCycle();
            ProcessorCycle cycle = machine.LastCycle;
            if (cycle.Operation == BusOperation.Read && !cycle.IsStalled && cycle.Address is 0xFFFA or 0xFFFE)
            {
                vector = cycle.Address;
            }

            instruction |= machine.Processor.FetchedOpcode;
            if (instruction && machine.Processor.IsInstructionBoundary) { break; }
        }

        return vector;
    }

    private static List<Row> RunMame(
        string mame,
        string roms,
        int seconds,
        string? cartridge,
        string? disk = null,
        string? sio = null,
        string? cpu = null)
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
                "a800", "-ramsize", "48K", "-sio", sio ?? (disk is null ? "" : "fdc"), "-rompath", roms, "-cfg_directory", work,
                "-nvram_directory", work, "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-debug", "-debugger", "none", "-seconds_to_run", (seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool("AtariOracle.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            if (disk is not null)
            {
                // MAME opens a disk for writing, which would lock the shared image and could change it: give it a copy.
                string copy = Path.Join(work, Path.GetFileName(disk));
                File.Copy(disk, copy);
                start.ArgumentList.Add("-flop1");
                start.ArgumentList.Add(copy);
            }

            if (cartridge is not null)
            {
                start.ArgumentList.Add("-cart1");
                start.ArgumentList.Add(cartridge);
            }

            start.Environment["RETRO_END"] = seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            if (cpu is not null) { start.Environment["RETRO_CPU"] = cpu; }
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                process.StandardOutput.ReadToEnd();
                process.WaitForExit(600_000).Should().BeTrue("MAME finishes");
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
                    Io(line[(bar + 7)..])));
            }

            return rows;
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }

        static byte Hex(string text) => byte.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);

        // MAME's disassembly: "lda $d40b", "rti".
        static Instruction Mnemonic(string text) =>
            Enum.TryParse(text.Split(' ')[0], ignoreCase: true, out Instruction instruction) ? instruction : Instruction.JAM;

        static ushort Io(string text)
        {
            string[] parts = text.Split(' ');
            bool absolute = parts.Length == 2 && parts[1].Length == 5 && parts[1].StartsWith("$d", StringComparison.Ordinal);
            ushort address = absolute
                ? ushort.Parse(parts[1].AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
                : (ushort)0;

            return address is >= 0xD000 and < 0xD800 ? address : (ushort)0;
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
