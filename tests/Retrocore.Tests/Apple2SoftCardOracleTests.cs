// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  The SoftCard against MAME: booting CP/M, the Z80 must run the same instructions from its first switch.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\SoftCardOracle.lua</c>
///   on a II Plus with a language card, the SoftCard in slot 4 and a Disk II in slot 6, from the ROM path in
///   <c>%USERPROFILE%\Retrocore\apple2-roms\mame</c>. The test is inconclusive without MAME, the ROM path or the disk.
///  </para>
///  <para>
///   MAME's trace gives each instruction's address; its debugger does not log the Z80's registers in this setup.
///   Loops that wait on the 6502, the disk or the keyboard run as many times as the timing says, so a loop repeated
///   back to back counts once. The card's refresh read is turned off, as MAME has none; it changes no Z80 state.
///  </para>
/// </remarks>
[TestClass]
public class Apple2SoftCardOracleTests
{
    private const string Disk = "CPM_Z80SoftCard.dsk";
    private const int Seconds = 6;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  From the first switch to CP/M's wait for a key: cold boot, the banner, and loading the CCP through the 6502.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void CpmBootMatchesMame()
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(ExternalTestData.Root, "apple2-roms", "mame");
        string disk = Path.Join(ExternalTestData.Root, "softcard-disks", Disk);
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "apple2p", "341-0020-00.f8")) || !File.Exists(disk))
        {
            Assert.Inconclusive("MAME, its II Plus ROM path or the SoftCard CP/M disk is missing.");
        }

        List<ushort> expected = Collapse(RunMame(mame, roms, disk));
        List<ushort> actual = Collapse(RunMachine(disk));
        expected.Count.Should().BeGreaterThan(1_000, "MAME booted CP/M");

        int count = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < count; i++)
        {
            if (expected[i] != actual[i])
            {
                Assert.Fail($"Instruction {i} is at ${actual[i]:X4}; MAME's is at ${expected[i]:X4}.");
            }
        }

        actual.Count.Should().Be(expected.Count);
    }

    // Removes loops repeated back to back, of up to 16 instructions, keeping one pass.
    private static List<ushort> Collapse(IEnumerable<ushort> rows)
    {
        List<ushort> collapsed = [];
        foreach (ushort row in rows)
        {
            collapsed.Add(row);
            for (int length = 1; length <= 16 && collapsed.Count >= 2 * length; length++)
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

    private static List<ushort> RunMachine(string disk)
    {
        Apple2Machine machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, s_inputs));
        machine.Bus.InstallLanguageCard();
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(sectors: 16, s_inputs));
        SoftCard card = machine.Bus.InstallSoftCard(slot: 4);
        card.RefreshesHost = false;
        machine.Drives[0].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(disk), proDosOrder: false), Disk, "DSK");
        machine.Reset();

        // The Z80 starts at zero; the hook reports each instruction after that as the one before it ends.
        List<ushort> rows = [0x0000];
        card.InstructionBoundary = softCard => rows.Add(softCard.Processor.Registers.PC);
        machine.Run((ulong)(Seconds * BasicMachines.IIeClock));
        return rows;
    }

    private static List<ushort> RunMame(string mame, string roms, string disk)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "trace.log");

            // MAME opens its disk for writing, which would lock the shared image away from other tests.
            string copy = Path.Join(work, Disk);
            File.Copy(disk, copy);
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                "apple2p", "-sl4", "softcard", "-sl6", "diskiing", "-flop1", copy,
                "-rompath", roms, "-cfg_directory", work, "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-debug", "-debugger", "none", "-seconds_to_run", (Seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool("SoftCardOracle.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = Seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                process.StandardOutput.ReadToEnd();
                process.WaitForExit(300_000).Should().BeTrue("MAME finishes");
            }

            File.Exists(output).Should().BeTrue("the Lua script traces");
            List<ushort> rows = [];
            foreach (string line in File.ReadLines(output))
            {
                int colon = line.IndexOf(':', StringComparison.Ordinal);
                if (colon < 4) { continue; }
                rows.Add(ushort.Parse(line.AsSpan(colon - 4, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
            }

            return rows;
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
