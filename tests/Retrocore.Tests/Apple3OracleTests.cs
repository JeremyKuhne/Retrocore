// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Machines.Apple3;

// An instruction's address with the registers before it; the B flag is left out, since MAME shows it set.
using Row = (ushort Pc, byte A, byte X, byte Y, byte P, byte S);

namespace Retrocore.Tests;

/// <summary>
///  The Apple III against MAME: from power-on, the boot ROM must run the same instructions with the same registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\Apple3Oracle.lua</c>,
///   which traces with its debugger. The tests are inconclusive without MAME or the ROM set.
///  </para>
///  <para>
///   Some things differ by nature, so the comparison allows for them. Loops that wait on the video beam or a timer
///   run as many times as the clocks say, and the clocks differ (our lines are the manual's 912 dots, MAME's 910),
///   so a loop repeated back to back counts once, as MAME's own trace collapses loops. A register that samples the
///   beam is masked. And the comparison stops where the ROM first asks the disk whether it spins: MAME's empty
///   drive is silent, while ours, like a real one, reads noise.
///  </para>
/// </remarks>
[TestClass]
public class Apple3OracleTests
{
    // F12B checks whether the drive spins; F12D is its first read of the data latch.
    private const ushort DriveCheck = 0xF12D;

    /// <summary>
    ///  The diagnostics, from power-on to the first disk access: RAM, ROM checksum, VIAs, serial port, keyboard,
    ///  character RAM and the screen.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DiagnosticsMatchMame()
    {
        string mame = System.Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.GetDirectoryName(Apple3MachineTests.RomDirectory) ?? ".";
        if (!File.Exists(mame) || !File.Exists(Path.Join(Apple3MachineTests.RomDirectory, Apple3Roms.BootRomFile)))
        {
            Assert.Inconclusive("MAME or the Apple III ROM set is missing.");
        }

        List<Row> expected = Collapse(RunMame(mame, roms, seconds: 1).Select(Normalize));
        List<Row> actual = Collapse(RunMachine().Select(Normalize));
        expected.Count.Should().BeGreaterThan(10_000, "MAME reached the drive check");

        int count = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < count; i++)
        {
            if (expected[i] != actual[i])
            {
                string context = string.Join(
                    '\n',
                    Enumerable.Range(Math.Max(0, i - 8), Math.Min(12, count - Math.Max(0, i - 8)))
                        .Select(j => $"{Show(expected[j])}    {Show(actual[j])}"));

                Assert.Fail($"Instruction {i} differs (MAME, then ours):\n{context}");
            }
        }

        actual.Count.Should().Be(expected.Count);
    }

    /// <summary>
    ///  The RETRY screen, pixel for pixel, but for the blinking cursor's cell under RETRY.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void RetryScreenMatchesMame()
    {
        string mame = System.Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.GetDirectoryName(Apple3MachineTests.RomDirectory) ?? ".";
        if (!File.Exists(mame) || !File.Exists(Path.Join(Apple3MachineTests.RomDirectory, Apple3Roms.BootRomFile)))
        {
            Assert.Inconclusive("MAME or the Apple III ROM set is missing.");
        }

        byte[] expected = RunMameFrame(mame, roms, seconds: 4);
        Apple3Machine machine = Apple3MachineTests.Machine();
        Apple3MachineTests.RunToRetry(machine);
        byte[] actual = machine.Video.RenderBitmap();
        expected.Should().HaveCount(actual.Length, "MAME's screen is 560×192 too");
        for (int y = 0; y < 192; y++)
        {
            for (int x = 0; x < 560; x++)
            {
                if (y is >= 8 and < 16 && x < 14) { continue; }
                int offset = ((y * 560) + x) * 4;
                if (!expected.AsSpan(offset, 3).SequenceEqual(actual.AsSpan(offset, 3)))
                {
                    Assert.Fail($"The first difference is at ({x}, {y}).");
                }
            }
        }
    }

    // Leaves out what samples the beam. $F60F reads VIA 1's port B, whose bit 6 is screen blank, and masks it off
    // next; where the beam is then depends on the line length, 912 dots here and 910 in MAME.
    private static Row Normalize(Row row) => row.Pc == 0xF612 ? row with { A = (byte)(row.A & ~0x40) } : row;

    private static string Show(Row row) =>
        $"{row.Pc:X4} {row.A:X2} {row.X:X2} {row.Y:X2} {row.P:X2} {row.S:X2}";

    // Drops every repeat of a run of up to 8 rows that comes straight after itself.
    private static List<Row> Collapse(IEnumerable<Row> rows)
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

    private static List<Row> RunMachine()
    {
        Apple3Machine machine = Apple3MachineTests.Machine();

        // The registers' power-on contents are happenstance; take MAME's once the reset sequence is done.
        for (int i = 0; i < 7; i++) { machine.StepCycle(); }
        ProcessorRegisters start = machine.Processor.Registers;
        start.X = 0x80;
        start.StackPointer = 0xFD;
        start.Status |= StatusRegister.Zero;
        machine.Processor.Registers = start;

        List<Row> rows = [];
        while (rows.Count < 2_000_000)
        {
            ProcessorRegisters r = machine.Processor.Registers;
            if (r.ProgramCounter == DriveCheck) { break; }
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer));
            machine.StepInstruction();
        }

        return rows;
    }

    private static List<Row> RunMame(string mame, string roms, int seconds)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "trace.log");
            string lua = FindTool("Apple3Oracle.lua");
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                "apple3", "-rompath", roms, "-cfg_directory", work, "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-debug", "-debugger", "none", "-seconds_to_run", (seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", lua, "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                process.StandardOutput.ReadToEnd();
                process.WaitForExit(300_000).Should().BeTrue("MAME finishes");
            }

            File.Exists(output).Should().BeTrue("the Lua script traces");
            List<Row> rows = [];
            foreach (string line in File.ReadLines(output))
            {
                int bar = line.IndexOf('|', StringComparison.Ordinal);
                if (bar < 0 || line.Length < bar + 5) { continue; }
                ushort pc = ushort.Parse(line.AsSpan(bar + 1, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                if (pc == DriveCheck) { break; }
                string[] registers = line[..bar].Split(' ');
                rows.Add((
                    pc,
                    Hex(registers[0]),
                    Hex(registers[1]),
                    Hex(registers[2]),
                    (byte)(Hex(registers[3]) & 0xEF),
                    (byte)(int.Parse(registers[4], NumberStyles.HexNumber, CultureInfo.InvariantCulture) & 0xFF)));
            }

            return rows;
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }

        static byte Hex(string text) => byte.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    private static byte[] RunMameFrame(string mame, string roms, int seconds)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "frame.rgba");
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                "apple3", "-rompath", roms, "-cfg_directory", work, "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-seconds_to_run", (seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool("Apple3Frame.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                process.StandardOutput.ReadToEnd();
                process.WaitForExit(300_000).Should().BeTrue("MAME finishes");
            }

            File.Exists(output).Should().BeTrue("the Lua script writes the frame");
            return File.ReadAllBytes(output);
        }
        finally
        {
            Directory.Delete(work, recursive: true);
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
