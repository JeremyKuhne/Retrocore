// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Machines.Coco;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Color Computer against MAME: the same keystrokes at the same emulated times leave the same screen and BASIC
///  program in memory.
/// </summary>
[TestClass]
public class CocoOracleTests
{
    private const ushort ProgramStart = 0x0019;
    private const ushort VariablesStart = 0x001B;
    private const ushort CursorAddress = 0x0088;

    /// <summary>
    ///  Color BASIC 1.2 with Extended 1.1 on a 64 KB CoCo 2 types, lists and runs a program as MAME's does.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void ExtendedColorBasicMatchesMame()
    {
        // Lowercase types unshifted letters, which Color BASIC shows as uppercase, on both.
        (double At, string Text)[] script =
        [
            (3, "10 for i=1 to 3:print i*i;:next\r"),
            (7, "20 print mem\r"),
            (10, "run\r"),
            (13, "list\r")
        ];

        Compare("coco", "b12e11", CocoModel.Coco2, 12, 11, script, finish: 17, landmark: "1  4  9");
    }

    /// <summary>
    ///  Color BASIC 1.3 on a CoCo 2B runs a program as MAME's does.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void ColorBasic13MatchesMame()
    {
        (double At, string Text)[] script =
        [
            (3, "10 print \"hello\";2*21\r"),
            (7, "run\r")
        ];

        Compare("coco2b", bios: null, CocoModel.Coco2, 13, 11, script, finish: 10, landmark: "HELLO 42");
    }

    /// <summary>
    ///  Extended Color BASIC 2.0 on a 128 KB CoCo 3 runs a program in its 32-column screen as MAME's does.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Coco3MatchesMame()
    {
        (double At, string Text)[] script =
        [
            (4, "10 for i=1 to 4:print i*i;:next\r"),
            (8, "run\r")
        ];

        Compare("coco3", bios: null, CocoModel.Coco3, 0, 0, script, finish: 11, landmark: "1  4  9  16");
    }

    /// <summary>
    ///  Disk Extended Color BASIC 1.1 saves a program to a formatted disk byte for byte as MAME's FDC does.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DiskSaveMatchesMame()
    {
        (double At, string Text)[] script = [(3, "10 print \"saved\";6*7\rsave \"hello\"\r")];
        const double Finish = 14;
        string mame = Mame(out string zips);
        byte[] formatted = JvcFormat.Write(JvcFormat.Formatted());
        (byte[] oracle, byte[]? oracleDisk) = RunMame(mame, zips, "coco", "b12e11", "64K", script, Finish, formatted);

        CocoMachine machine = new(
            new() { Model = CocoModel.Coco2, RamKilobytes = 64 },
            CocoTestRoms.Load(CocoModel.Coco2),
            new CocoDiskController(CocoTestRoms.DiskBasic()));

        FloppyDisk disk = JvcFormat.Read(formatted);
        machine.Bus.DiskController?.Drives[0].Insert(disk, "formatted", "dsk");
        Play(machine, script, Finish);

        string expected = Screen(address => oracle[address]);
        Console.WriteLine(expected);
        expected.Should().Contain("SAVE \"HELLO\"", "MAME got through the script");
        Screen(address => machine.Bus.Peek((ushort)address)).Should().Be(expected);
        JvcFormat.Write(disk).Should().Equal(oracleDisk);
    }

    private static void Play(CocoMachine machine, (double At, string Text)[] script, double finish)
    {
        foreach ((double at, string text) in script)
        {
            machine.Run((ulong)(at * CocoTiming.ClockHertz) - machine.Processor.CycleCount);
            foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
        }

        machine.Run((ulong)(finish * CocoTiming.ClockHertz) - machine.Processor.CycleCount);
    }

    private static string Mame(out string zips)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        zips = Path.Join(ExternalTestData.Root, "coco-roms", "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(zips, "coco.zip")))
        {
            Assert.Inconclusive("MAME or the Color Computer ROM zips are missing.");
        }

        return mame;
    }

    private static void Compare(
        string driver,
        string? bios,
        CocoModel model,
        int color,
        int extended,
        (double At, string Text)[] script,
        double finish,
        string landmark)
    {
        string mame = Mame(out string zips);
        string ram = model == CocoModel.Coco3 ? "128K" : "64K";
        (byte[] oracle, _) = RunMame(mame, zips, driver, bios, ram, script, finish, disk: null);
        int kilobytes = model == CocoModel.Coco3 ? 128 : 64;
        CocoMachine machine = CocoMachineTests.Create(model, color, extended, kilobytes);
        Play(machine, script, finish);

        // The cursor blinks, so its cell depends on the moment and is left out.
        int oracleCursor = (oracle[CursorAddress] << 8) | oracle[CursorAddress + 1];
        int cursor = (machine.Bus.Peek(CursorAddress) << 8) | machine.Bus.Peek(CursorAddress + 1);
        cursor.Should().Be(oracleCursor);
        string expected = Screen(address => address == oracleCursor ? (byte)0x60 : oracle[address]);
        string actual = Screen(address => address == cursor ? (byte)0x60 : machine.Bus.Peek((ushort)address));
        Console.WriteLine(expected);
        expected.Should().Contain(landmark, "MAME got through the script");
        actual.Should().Be(expected);

        int start = (oracle[ProgramStart] << 8) | oracle[ProgramStart + 1];
        int end = (oracle[VariablesStart] << 8) | oracle[VariablesStart + 1];
        ((machine.Bus.Peek(ProgramStart) << 8) | machine.Bus.Peek(ProgramStart + 1)).Should().Be(start);
        byte[] program = [.. Enumerable.Range(start, end - start).Select(address => machine.Bus.Peek((ushort)address))];
        program.Should().Equal(oracle[start..end]);
    }

    private static string Screen(Func<int, byte> read) => string.Join(
        '\n',
        Enumerable.Range(0, 16).Select(row => new string(
            [.. Enumerable.Range(0, 32).Select(column => CocoVideo.Character(read(0x0400 + (row * 32) + column)))])));

    // Runs MAME and returns its address space at the end and, with a disk in drive 0, the disk as MAME left it.
    private static (byte[] Memory, byte[]? Disk) RunMame(
        string mame,
        string zips,
        string driver,
        string? bios,
        string ram,
        (double At, string Text)[] script,
        double finish,
        byte[]? disk)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "memory.bin");
            string lua = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "..", "..", "..", "..", "tools", "Trs80Oracle.lua"));
            if (!File.Exists(lua)) { lua = FindTool("Trs80Oracle.lua"); }

            List<string> arguments = [driver, "-rompath", zips, "-cfg_directory", work, "-nvram_directory", work];
            if (bios is not null) { arguments.AddRange(["-bios", bios]); }
            string image = Path.Join(work, "disk.dsk");
            arguments.AddRange(["-ramsize", ram]);
            if (disk is null)
            {
                arguments.AddRange(["-ext", ""]);
            }
            else
            {
                File.WriteAllBytes(image, disk);
                arguments.AddRange(["-ext", "fdc", "-flop1", image]);
            }

            arguments.AddRange(["-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo"]);
            arguments.AddRange(["-seconds_to_run", ((int)finish + 5).ToString(CultureInfo.InvariantCulture)]);
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
            start.Environment["RETRO_END"] = finish.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start.");
            string log = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
            process.WaitForExit(120_000).Should().BeTrue("MAME finishes");
            File.Exists(output).Should().BeTrue($"the Lua script dumps memory; MAME said: {log}");
            return (File.ReadAllBytes(output), disk is null ? null : File.ReadAllBytes(image));
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    private static string ScriptEntry((double At, string Text) entry)
    {
        string at = entry.At.ToString(CultureInfo.InvariantCulture);
        return $"{at}={entry.Text.Replace("\r", "\\r", StringComparison.Ordinal)}";
    }

    private static string FindTool(string name)
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            string path = Path.Join(directory.FullName, "tools", name);
            if (File.Exists(path)) { return path; }
        }

        throw new FileNotFoundException(name);
    }
}
