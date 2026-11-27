// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Model II with its boot ROM, built from <c>Model2Boot.asm</c>, booting its DOSes from the images in
///  <c>trs80-disks</c> under <see cref="ExternalTestData.Root"/>.
/// </summary>
[TestClass]
public class Trs80Model2RomTests
{
    private const int Columns = 80;
    private const int Rows = 24;

    /// <summary>
    ///  Each TRSDOS boots from drive 0: its boot code's diagnostics pass, including the DMA's (which stopped at
    ///  <c>BOOT ERROR DM 23</c> while the DMA's end-of-block vector was wrong), it takes the date and time and lists
    ///  its directory. The test is inconclusive without the image; see <c>docs/Trs80Model3And2.md</c>.
    /// </summary>
    /// <param name="image">The image's file name.</param>
    /// <param name="listed">A file its directory lists.</param>
    [TestMethod]
    [DataRow("M2TRSDOS12.imd", "HERZ50")]
    [DataRow("M2TRSDOS20A.imd", "PRTBKSP")]
    [DataRow("M2TRSDOS20B.imd", "BASCOM64")]
    public void BootsItsDos(string image, string listed)
    {
        string path = Path.Join(ExternalTestData.Root, "trs80-disks", image);
        if (!File.Exists(path)) { Assert.Inconclusive($"{path} is missing."); }

        Trs80Model2Machine machine = Create();
        (FloppyDisk disk, string format) = Trs80DiskImage.Read(File.ReadAllBytes(path), Path.GetExtension(path));
        machine.Drives[0].Insert(disk, image, format);

        // TRSDOS 1.2 asks in capitals and 2.0 does not.
        ShowsWithin(machine, "ENTER DATE", seconds: 30);
        Type(machine, "11/14/1986\r");
        ShowsWithin(machine, "ENTER TIME", seconds: 10);
        Type(machine, "12.00.00\r");
        ShowsWithin(machine, "TRSDOS READY", seconds: 20);

        // TRSDOS 1.2 drops the keys typed as it shows its prompt.
        machine.Run(Trs80Model2Timing.ClockHertz);
        Type(machine, "DIR\r");
        ShowsWithin(machine, listed, seconds: 20);
    }

    /// <summary>
    ///  Creates a Model II with version 5 of its boot ROM, as MAME's default BIOS.
    /// </summary>
    /// <returns>The machine.</returns>
    internal static Trs80Model2Machine Create()
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] boot = Trs80SdkModules.AssembleModel2Boot(Path.Join(roms, "Model2Boot.asm"), 5).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules.AssembleModel2CharacterGenerator(Path.Join(roms, "Model2CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        return new(new Trs80Model2Configuration(), new Trs80Model2Roms(boot, characters));
    }

    private static void Type(Trs80Model2Machine machine, string text)
    {
        foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
    }

    // Runs until the screen shows the text, ignoring case, checking every tenth of a second.
    private static void ShowsWithin(Trs80Model2Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.OrdinalIgnoreCase)) { return; }
            machine.Run(Trs80Model2Timing.ClockHertz / 10);
        }

        string screen = Screen(machine);
        screen.Should().ContainEquivalentOf(text, $"the screen shows it within {seconds} seconds:\n{screen}");
    }

    // Video RAM as text, a line to a row, with control codes and graphics as dots.
    private static string Screen(Trs80Model2Machine machine)
    {
        char[] screen = new char[Rows * (Columns + 1)];
        for (int row = 0; row < Rows; row++)
        {
            for (int column = 0; column < Columns; column++)
            {
                byte code = machine.Bus.Video.Read((row * Columns) + column);
                screen[(row * (Columns + 1)) + column] = code is >= 0x20 and < 0x7F ? (char)code : '.';
            }

            screen[(row * (Columns + 1)) + Columns] = '\n';
        }

        return new string(screen);
    }
}
