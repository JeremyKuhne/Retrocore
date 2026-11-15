// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;
using System.Diagnostics;
using System.Globalization;

namespace Retrocore.Tests;

/// <summary>
///  The Model III, 4 and II against MAME: both run the same keystrokes on the same ROMs, then their video RAM must
///  match, cell for cell.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>; or <c>mame/mame</c> or <c>mame/mame.exe</c> under
///   <see cref="ExternalTestData.Root"/>; or a Linux package's) runs <c>tools/Trs80Model3Oracle.lua</c> with MAME's
///   ROM sets (<c>trs80m3</c> and <c>trs80m2</c>, as zip or 7z) in <c>trs80-roms/mame</c>. The machines here run the
///   SDK's builds of the same ROMs, which are byte-identical to MAME's. The DOS tests use the images in
///   <c>trs80-disks</c>. The tests are inconclusive without these.
///  </para>
/// </remarks>
[TestClass]
public class Trs80Model3OracleTests
{
    /// <summary>
    ///  Model III BASIC without a disk: <c>Cass?</c> and <c>Memory Size?</c>, a typed program, its run and the free
    ///  memory.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Model3BasicMatchesMame()
    {
        (double At, string Text)[] script =
        [
            (2, "\r"),
            (4, "\r"),
            (8, "10 FOR I=1 TO 3:PRINT I*I;:NEXT\r"),
            (11, "RUN\r"),
            (13, "PRINT MEM\r")
        ];

        Compare(Trs80Model3Variant.Model3, script, finish: 16, disk: null, landmark: "1  4  9");
    }

    /// <summary>
    ///  Model 4 BASIC without a disk, as the Model III's.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Model4BasicMatchesMame()
    {
        (double At, string Text)[] script =
        [
            (2, "\r"),
            (4, "\r"),
            (8, "10 FOR I=1 TO 3:PRINT I*I;:NEXT\r"),
            (11, "RUN\r"),
            (13, "PRINT MEM\r")
        ];

        Compare(Trs80Model3Variant.Model4, script, finish: 16, disk: null, landmark: "1  4  9");
    }

    /// <summary>
    ///  Each DOS boots from drive 0, takes the date and time and lists its directory. The images are in
    ///  <c>trs80-disks</c>; see <c>docs/Trs80Model3And2.md</c>. TRSDOS 1.3 and 6.0 use their IMD copies, as MAME 0.264
    ///  does not read their DMK images.
    /// </summary>
    /// <param name="variant">The model.</param>
    /// <param name="image">The image's file name.</param>
    /// <param name="listed">A file its directory lists.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(Trs80Model3Variant.Model3, "TRSDOS13.imd", "MEMTEST/CMD")]
    [DataRow(Trs80Model3Variant.Model3, "LDOS513.dsk", "ALEDIT/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "TRSDOS60.imd", "REPAIR/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "TRSDOS62.imd", "REPAIR/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "LSDOS63J.dsk", "REPAIR/CMD")]
    public void DosMatchesMame(Trs80Model3Variant variant, string image, string listed)
    {
        string disk = Path.Join(Root, "trs80-disks", image);
        if (!File.Exists(disk)) { Assert.Inconclusive($"{disk} is missing."); }
        (double At, string Text)[] script =
        [
            (15, "11/14/86\r"),
            (18, "\r"),
            (22, "DIR\r")
        ];

        Compare(variant, script, finish: 60, disk, landmark: listed);
    }

    /// <summary>
    ///  Each Model II boot ROM tests the machine, finds no disk in drive 0 and asks for one, as MAME's does with the
    ///  same version, chosen by its BIOS name.
    /// </summary>
    /// <param name="version">The boot ROM's version, as <c>Model2Boot.asm</c> numbers it.</param>
    /// <param name="bios">MAME's name for it.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(1, "c8ff")]
    [DataRow(2, "2bff")]
    [DataRow(3, "2119")]
    [DataRow(5, "9733")]
    public void Model2BootMatchesMame(int version, string bios)
    {
        string mame = FindMame();
        string sets = Path.Join(Root, "trs80-roms", "mame");
        if (!Directory.Exists(sets) || !Directory.EnumerateFiles(sets, "trs80m2.*").Any())
        {
            Assert.Inconclusive("MAME's trs80m2 ROM set is missing.");
        }

        const double Finish = 6;
        byte[] dump = RunMame(mame, sets, "trs80m2", ":video_ram", [], Finish, disk: null, ["-bios", bios], cpu: ":u12");

        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] boot = Trs80SdkModules.AssembleModel2Boot(Path.Join(roms, "Model2Boot.asm"), version).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules.AssembleModel2CharacterGenerator(Path.Join(roms, "Model2CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        Trs80Model2Machine machine = new(new Trs80Model2Configuration(), new Trs80Model2Roms(boot, characters));
        machine.Run((ulong)(Finish * Trs80Model2Timing.ClockHertz));

        const int Cells = 80 * 24;
        string expected = Screen(dump[0x10000..(0x10000 + Cells)], 80);
        Console.WriteLine(expected);
        expected.Should().Contain("INSERT DISKETTE", "MAME's boot ROM asks for a diskette");
        Match(dump[0x10000..(0x10000 + Cells)], [.. Enumerable.Range(0, Cells).Select(machine.Bus.Video.Read)], 80);
    }

    private static string Root => ExternalTestData.Root;

    private static void Compare(
        Trs80Model3Variant variant,
        (double At, string Text)[] script,
        double finish,
        string? disk,
        string landmark)
    {
        string mame = FindMame();
        string sets = Path.Join(Root, "trs80-roms", "mame");
        if (!Directory.Exists(sets) || !Directory.EnumerateFiles(sets, "trs80m3.*").Any())
        {
            Assert.Inconclusive("MAME's trs80m3 ROM set is missing.");
        }

        string driver = variant == Trs80Model3Variant.Model4 ? "trs80m4" : "trs80m3";
        byte[] dump = RunMame(mame, sets, driver, ":videoram", script, finish, disk);

        Trs80Model3Machine machine = Create(variant, disk);
        Run(machine, script, finish);

        // What the screen shows, 64x16 or 80x24: the Model 4's video RAM holds 2K, past the 80x24 screen.
        int columns = machine.Bus.Video.Eighty ? 80 : 64;
        int cells = columns * machine.Bus.Video.Rows;
        byte[] oracle = dump[0x10000..(0x10000 + cells)];
        byte[] ours = [.. Enumerable.Range(0, cells).Select(machine.Bus.Video.Read)];
        string expected = Screen(oracle, columns);
        Console.WriteLine(expected);
        expected.Should().Contain(landmark, "MAME got through the script");

        // A DOS blinks its cursor, so the two may catch it in different phases: one cell may differ, where one side
        // shows a space.
        int[] differing = [.. Enumerable.Range(0, oracle.Length).Where(index => oracle[index] != ours[index])];
        if (differing.Length == 1 && (oracle[differing[0]] == ' ' || ours[differing[0]] == ' '))
        {
            ours[differing[0]] = oracle[differing[0]];
        }

        Match(oracle, ours, columns);
    }

    // Compares video RAM byte for byte, showing this side's screen and the first differing cell when they differ.
    private static void Match(byte[] oracle, byte[] ours, int columns)
    {
        int first = Enumerable.Range(0, oracle.Length).FirstOrDefault(index => oracle[index] != ours[index], -1);
        if (first < 0) { return; }
        Console.WriteLine($"Ours:\n{Screen(ours, columns)}");
        Assert.Fail($"Video RAM differs at row {first / columns}, column {first % columns}: "
            + $"${ours[first]:X2} here, ${oracle[first]:X2} in MAME.");
    }

    private static Trs80Model3Machine Create(Trs80Model3Variant variant, string? disk)
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        int model = variant == Trs80Model3Variant.Model4 ? 4 : 3;
        byte[] system = Trs80SdkModules.AssembleModel3(Path.Join(roms, "Model3.asm"), model).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules
            .AssembleModel3CharacterGenerator(Path.Join(roms, "Model3CharacterGenerator.asm"), model4P: false)
            .Sections[0].Bytes.ToArray();

        // MAME's Model III has 48K, its Model 4 64K. Its drives are a configuration switch, off by default, which the
        // runs with a disk turn on: the controller is fitted when they are.
        Trs80Model3Configuration configuration = new()
        {
            Variant = variant,
            RamKilobytes = variant == Trs80Model3Variant.Model4 ? 64 : 48,
            DiskController = disk is not null
        };

        Trs80Model3Machine machine = new(configuration, new Trs80Model3Roms(system, characters));
        if (disk is not null)
        {
            (FloppyDisk image, string format) = Trs80DiskImage.Read(File.ReadAllBytes(disk), Path.GetExtension(disk));
            machine.Drives[0].Insert(image, Path.GetFileName(disk), format);
        }

        return machine;
    }

    // Runs the schedule in the devices' time, which counts 2 MHz T-states whether the Z80 runs at 2 or 4 MHz,
    // typing each entry when its time comes.
    private static void Run(Trs80Model3Machine machine, (double At, string Text)[] script, double finish)
    {
        double time = 0;
        void RunTo(double seconds)
        {
            double target = seconds * Trs80Model3Timing.ClockHertz;
            while (time < target)
            {
                bool fast = machine.Bus.Fast;
                machine.StepCycle();
                time += fast ? 0.5 : 1;
            }
        }

        // MAME types an uppercase letter with shift, and Type types it without: swapping the case presses the same
        // keys, which matters where a DOS starts with caps lock off, as TRSDOS 6.0 does.
        foreach ((double at, string text) in script)
        {
            RunTo(at);
            foreach (char character in text) { machine.Bus.Keyboard.Type((byte)SwapCase(character)); }
        }

        RunTo(finish);
    }

    private static byte[] RunMame(
        string mame,
        string sets,
        string driver,
        string share,
        (double At, string Text)[] script,
        double finish,
        string? disk,
        string[]? options = null,
        string cpu = ":maincpu")
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            List<string> arguments =
            [
                driver, "-rompath", sets, "-cfg_directory", Path.Join(work, "cfg"), "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-seconds_to_run", ((int)finish + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool("Trs80Model3Oracle.lua")
            ];

            arguments.AddRange(options ?? []);
            if (disk is not null)
            {
                Directory.CreateDirectory(Path.Join(work, "cfg"));
                File.WriteAllText(Path.Join(work, "cfg", driver + ".cfg"), $$"""
                    <?xml version="1.0"?>
                    <mameconfig version="10"><system name="{{driver}}"><input>
                    <port tag=":CONFIG" type="CONFIG" mask="128" defvalue="0" value="128" />
                    </input></system></mameconfig>
                    """);

                arguments.AddRange(["-flop1", disk]);
            }

            string output = Path.Join(work, "memory.bin");
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
            start.Environment["RETRO_SHARE"] = share;
            start.Environment["RETRO_CPU"] = cpu;
            using Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start.");
            // Both streams drain as MAME runs, so the timeout holds even if MAME stops with them open.
            Task<string> errors = process.StandardError.ReadToEndAsync();
            Task<string> standard = process.StandardOutput.ReadToEndAsync();
            if (!process.WaitForExit(120_000))
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit();
                Assert.Fail("MAME did not finish within 120 seconds.");
            }

            Task.WaitAll(errors, standard);
            File.Exists(output).Should().BeTrue($"the Lua script dumps memory: {errors.Result}");
            return File.ReadAllBytes(output);
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    private static string FindMame()
    {
        string? named = Environment.GetEnvironmentVariable("RETROCORE_MAME");
        string[] candidates = named is not null
            ? [named]
            : [Path.Join(Root, "mame", "mame.exe"), Path.Join(Root, "mame", "mame"), "/usr/games/mame", "/usr/bin/mame"];

        string? found = candidates.FirstOrDefault(File.Exists);
        if (found is null) { Assert.Inconclusive("MAME is missing."); }
        return found;
    }

    private static char SwapCase(char character)
    {
        if (char.IsAsciiLetterUpper(character)) { return char.ToLowerInvariant(character); }
        return char.IsAsciiLetterLower(character) ? char.ToUpperInvariant(character) : character;
    }

    private static string ScriptEntry((double At, string Text) entry)
    {
        string at = entry.At.ToString(CultureInfo.InvariantCulture);
        return $"{at}={entry.Text.Replace("\r", "\\r", StringComparison.Ordinal)}";
    }

    // Video RAM as text, a line to a row: graphics characters as #, control codes as dots.
    private static string Screen(byte[] video, int columns)
    {
        string[] rows = new string[video.Length / columns];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[columns];
            for (int column = 0; column < columns; column++)
            {
                byte code = video[(row * columns) + column];
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
