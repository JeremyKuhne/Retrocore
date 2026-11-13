// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Apple II emulation on the Apple III, from Apple's Apple II Emulation disk: it locks the machine into a 1 MHz,
///  48K II Plus, boots DOS 3.3, and AppleSoft runs and survives CONTROL-RESET.
/// </summary>
/// <remarks>
///  <para>
///   The Emulation disk is in <c>RETROCORE_APPLE3_DISKS</c> or <c>%USERPROFILE%\Retrocore\apple3-disks</c>, and the
///   DOS 3.3 System Master in <c>iie-disks</c> beside it; the test is inconclusive without them or the ROM.
///  </para>
/// </remarks>
[TestClass]
public class Apple3EmulationTests
{
    private const string Emulation = "Apple3Apple][emulation.dsk";
    private const string Master = "DOS 3.3 System Master - 680-0210-A (1982).dsk";

    private static string Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple3-disks");

    /// <summary>
    ///  The Emulation disk's menu boots DOS 3.3 from the built-in drive, AppleSoft runs a program, and CONTROL-RESET
    ///  is an NMI that returns to AppleSoft with the program kept, still in Apple II mode.
    /// </summary>
    [TestMethod]
    public void EmulationBootsDos33AndAppleSoftRuns()
    {
        string emulation = Path.Join(Disks, Emulation);
        string master = Path.Join(ExternalTestData.Root, "iie-disks", Master);
        if (!File.Exists(emulation))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {Emulation}.");
        }

        if (!File.Exists(master))
        {
            Assert.Inconclusive($"The DOS 3.3 System Master is not in {Path.GetDirectoryName(master)}.");
        }

        Apple3Machine machine = Apple3MachineTests.Machine();
        Insert(machine, emulation);
        RunUntil(machine, "CONFIGURATION MENU", seconds: 30);
        machine.Bus.AppleIIMode.Should().BeFalse("the menu runs before the trap is set");

        // The menu boots whatever is in the built-in drive.
        Insert(machine, master);
        Type(machine, "\r");
        RunUntil(machine, "SYSTEM MASTER", seconds: 60);
        machine.Bus.AppleIIMode.Should().BeTrue();
        (machine.Bus.Environment & Apple3Bus.SlowSpeed).Should().NotBe(0, "emulation runs at 1 MHz");
        (machine.Bus.Environment & Apple3Bus.RomEnable).Should().Be(0, "the II's ROMs are write-protected RAM");
        machine.Run(TimeSpan.FromSeconds(1));

        Type(machine, "10 HOME\r20 PRINT 6*7\r30 GOTO 30\rRUN\r");
        RunUntil(machine, "42", seconds: 10);
        Screen(machine).Should().NotContain("]", "the program is still running");

        machine.PressReset(control: true);
        RunUntil(machine, "]", seconds: 5);
        machine.Bus.AppleIIMode.Should().BeTrue("CONTROL-RESET cannot leave Apple II mode");
        Type(machine, "LIST\r");
        RunUntil(machine, "30  GOTO 30", seconds: 5);
    }

    private static void Insert(Apple3Machine machine, string path)
    {
        machine.Drives[0].Eject();
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(media, Path.GetFileName(path), "DSK");
    }

    private static void Type(Apple3Machine machine, string keys)
    {
        foreach (char key in keys) { machine.Bus.QueueKey((byte)key); }
    }

    private static string Screen(Apple3Machine machine) => string.Join('\n', machine.ReadTextScreen());

    private static void RunUntil(Apple3Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        Screen(machine).Should().Contain(text);
    }
}
