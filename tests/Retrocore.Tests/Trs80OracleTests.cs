// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Model I against MAME: both run the same keystrokes on Tandy's ROMs, then the screens must match
///  exactly, and so must the BASIC program bytes, which do not depend on timing.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs
///   <c>tools\Trs80Oracle.lua</c> with the ROM zips in <c>%USERPROFILE%\Retrocore\trs80-roms\zips</c>. The
///   tests are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class Trs80OracleTests
{
    private const ushort ProgramStart = 0x40A4;
    private const ushort VariablesStart = 0x40F9;
    private const ushort CursorAddress = 0x4020;

    /// <summary>
    ///  Level II without disks: boot, a typed program, its run and the free memory.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void LevelTwoBasicMatchesMame()
    {
        (double At, string Text)[] script =
        [
            (2, "\r"),
            (6, "10 FOR I=1 TO 3:PRINT I*I;:NEXT\r"),
            (10, "RUN\r"),
            (12, "PRINT MEM\r")
        ];

        Compare(script, finish: 15, disk: null, comparesProgram: true, landmark: "1  4  9");
    }

    /// <summary>
    ///  NEWDOS/80 boots from drive 0 and lists its directory.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void NewDosMatchesMame()
    {
        string disk = Path.Join(Cache, "trs80-disks", "NEWDOS_80sssd_jv1.DSK");
        if (!File.Exists(disk)) { Assert.Inconclusive("The NEWDOS/80 image is missing."); }
        Compare([(12, "DIR 0\r")], finish: 20, disk, comparesProgram: false, landmark: "SUPERZAP/CMD");
    }

    private static string Cache => ExternalTestData.Root;

    private static void Compare(
        (double At, string Text)[] script,
        double finish,
        string? disk,
        bool comparesProgram,
        string landmark)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME") ?? Path.Join(Cache, "mame", "mame.exe");
        string zips = Path.Join(Cache, "trs80-roms", "zips");
        if (!File.Exists(mame) || !File.Exists(Path.Join(zips, "trs80l2.zip")))
        {
            Assert.Inconclusive("MAME or the Model I ROM zips are missing.");
        }

        byte[] oracle = RunMame(mame, zips, script, finish, disk);
        Trs80Machine machine = RunMachine(script, finish, disk);

        // Stock video RAM has no bit 6; both read it as the inverse of bit 5. A DOS blinks the cursor, so the
        // cell at the video DCB's cursor address depends on the moment and is left out.
        int oracleCursor = (oracle[CursorAddress] | (oracle[CursorAddress + 1] << 8)) - 0x3C00;
        int cursor = (machine.Bus.Peek(CursorAddress) | (machine.Bus.Peek(CursorAddress + 1) << 8)) - 0x3C00;
        string expected = Screen(index => index == oracleCursor ? (byte)' ' : Normalize(oracle[0x3C00 + index]));
        string actual = Screen(index => index == cursor ? (byte)' ' : machine.Bus.Video.Read(index));
        cursor.Should().Be(oracleCursor);
        Console.WriteLine(expected);
        expected.Should().Contain(landmark, "MAME got through the script");
        actual.Should().Be(expected);

        if (comparesProgram)
        {
            int start = oracle[ProgramStart] | (oracle[ProgramStart + 1] << 8);
            int end = oracle[VariablesStart] | (oracle[VariablesStart + 1] << 8);
            (machine.Bus.Peek(ProgramStart) | (machine.Bus.Peek(ProgramStart + 1) << 8)).Should().Be(start);
            byte[] program = [.. Enumerable.Range(start, end - start).Select(address => machine.Bus.Peek((ushort)address))];
            program.Should().Equal(oracle[start..end]);
        }
    }

    private static byte[] RunMame(string mame, string zips, (double At, string Text)[] script, double finish, string? disk)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string cfg = Directory.CreateDirectory(Path.Join(work, "cfg")).FullName;
            List<string> arguments = ["trs80l2", "-rompath", zips, "-cfg_directory", cfg, "-nvram_directory", work];
            if (disk is not null)
            {
                // The Model I's drives are a configuration switch, off by default.
                File.WriteAllText(Path.Join(cfg, "trs80l2.cfg"), """
                    <?xml version="1.0"?>
                    <mameconfig version="10"><system name="trs80l2"><input>
                    <port tag=":CONFIG" type="CONFIG" mask="128" defvalue="0" value="128" />
                    </input></system></mameconfig>
                    """);

                arguments.AddRange(["-floppy0", "80t_qd", "-flop1", disk]);
            }

            string output = Path.Join(work, "memory.bin");
            string lua = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "..", "..", "..", "..", "tools", "Trs80Oracle.lua"));
            if (!File.Exists(lua)) { lua = FindTool("Trs80Oracle.lua"); }
            arguments.AddRange(["-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo"]);
            arguments.AddRange(["-seconds_to_run", ((int)finish + 5).ToString(System.Globalization.CultureInfo.InvariantCulture)]);
            arguments.AddRange(["-autoboot_script", lua]);

            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_SCRIPT"] = string.Join('|', script.Select(ScriptEntry));
            start.Environment["RETRO_END"] = finish.ToString(System.Globalization.CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start.");
            process.StandardOutput.ReadToEnd();
            process.WaitForExit(120_000).Should().BeTrue("MAME finishes");
            File.Exists(output).Should().BeTrue("the Lua script dumps memory");
            return File.ReadAllBytes(output);
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    // Runs the same schedule in emulated time, typing each entry when its time comes.
    private static Trs80Machine RunMachine((double At, string Text)[] script, double finish, string? disk)
    {
        string roms = Path.Join(Cache, "trs80-roms", "extract");
        byte[] level2 =
        [
            .. File.ReadAllBytes(Path.Join(roms, "rom-a.z1")),
            .. File.ReadAllBytes(Path.Join(roms, "rom-b.z2")),
            .. File.ReadAllBytes(Path.Join(roms, "rom-c.z3"))
        ];

        // NEWDOS/80 probes for a Percom doubler, as MAME's Model I has.
        Trs80Configuration configuration = new()
        {
            DiskController = disk is not null,
            Doubler = disk is not null ? Trs80Doubler.Percom : Trs80Doubler.None
        };

        byte[] characters = File.ReadAllBytes(Path.Join(roms, "mcm6670p.z29"));
        Trs80Machine machine = new(configuration, new(level2, characters));
        if (disk is not null) { machine.Bus.Disks.Insert(0, Jv1Format.Read(File.ReadAllBytes(disk))); }
        foreach ((double at, string text) in script)
        {
            machine.Run((ulong)(at * Trs80Timing.ClockHertz) - machine.Processor.CycleCount);
            foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
        }

        machine.Run((ulong)(finish * Trs80Timing.ClockHertz) - machine.Processor.CycleCount);
        return machine;
    }

    private static string ScriptEntry((double At, string Text) entry)
    {
        string at = entry.At.ToString(System.Globalization.CultureInfo.InvariantCulture);
        return $"{at}={entry.Text.Replace("\r", "\\r", StringComparison.Ordinal)}";
    }

    private static byte Normalize(byte value) => (byte)(value | ((~value & 0x20) << 1));

    private static string Screen(Func<int, byte> read)
    {
        string[] rows = new string[Trs80Video.Rows];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[Trs80Video.Columns];
            for (int column = 0; column < line.Length; column++)
            {
                byte code = read((row * Trs80Video.Columns) + column);
                line[column] = code is >= 0x20 and < 0x7F ? (char)code : code >= 0x80 ? '#' : '.';
            }

            rows[row] = new string(line).TrimEnd();
        }

        return string.Join('\n', rows).TrimEnd('\n');
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
