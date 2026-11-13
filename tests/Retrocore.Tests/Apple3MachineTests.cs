// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  The Apple III on its own boot ROM, which needs the dump: MAME's <c>apple3</c> set, unzipped, in
///  <c>RETROCORE_APPLE3_ROMS</c> or <c>%USERPROFILE%\Retrocore\apple3-roms\mame\apple3</c>.
/// </summary>
[TestClass]
public class Apple3MachineTests
{
    /// <summary>
    ///  Gets the directory holding the boot ROM and the disk sequencer PROM.
    /// </summary>
    internal static string RomDirectory => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_ROMS")
        ?? Path.Join(ExternalTestData.Root, "apple3-roms", "mame", "apple3");

    /// <summary>
    ///  Makes a machine at power-on, or marks the test inconclusive without the dump.
    /// </summary>
    /// <param name="ramKilobytes">128, 256 or 512.</param>
    /// <returns>The machine.</returns>
    internal static Apple3Machine Machine(int ramKilobytes = 256)
    {
        if (!File.Exists(Path.Join(RomDirectory, Apple3Roms.BootRomFile)))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE3_ROMS to a directory with MAME's apple3 set unzipped.");
        }

        return new(Apple3Roms.LoadFromDirectory(RomDirectory), ramKilobytes);
    }

    /// <summary>
    ///  The boot ROM tests the RAM, the ROM, the VIAs and the serial port, then, finding no disk to boot, prints
    ///  RETRY at the top of the screen: the tests passed, since a failure stops with its own message.
    /// </summary>
    /// <param name="ramKilobytes">The RAM size.</param>
    [TestMethod]
    [DataRow(128)]
    [DataRow(256)]
    [DataRow(512)]
    public void BootRomPassesItsDiagnosticsAndAsksForADisk(int ramKilobytes)
    {
        Apple3Machine machine = Machine(ramKilobytes);
        RunToRetry(machine);

        string[] screen = machine.ReadTextScreen();
        screen[0].TrimEnd().Should().Be("RETRY", string.Join('\n', screen));

        // The rest is blank, but for the cursor, a $7F block that comes and goes, under RETRY.
        screen[1][0].Should().BeOneOf(' ', '\x7F');
        screen.Skip(1).Should().AllSatisfy(line => line.Replace('\x7F', ' ').Trim().Should().BeEmpty());

        // It leaves the ROM in and I/O on.
        machine.Bus.ReadArea(0xF000).Should().Be(Apple3MemoryArea.Rom);
        machine.Bus.ReadArea(0xC000).Should().Be(Apple3MemoryArea.Io);
    }

    /// <summary>
    ///  A key typed at RETRY reaches the keyboard port with its strobe, and the ROM takes it.
    /// </summary>
    [TestMethod]
    public void KeyAtRetryIsTaken()
    {
        Apple3Machine machine = Machine();
        RunToRetry(machine);

        machine.Bus.QueueKey((byte)'\r');
        machine.Bus.Peek(0xC000).Should().Be(0x8D);
        machine.Run(TimeSpan.FromSeconds(0.5));
        machine.Bus.Peek(0xC000).Should().Be(0x0D, "the ROM cleared the strobe");
    }

    /// <summary>
    ///  Runs until RETRY shows, for up to 30 emulated seconds.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal static void RunToRetry(Apple3Machine machine)
    {
        for (int tenth = 0; tenth < 300; tenth++)
        {
            if (machine.ReadTextScreen()[0].StartsWith("RETRY", StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }
    }
}
