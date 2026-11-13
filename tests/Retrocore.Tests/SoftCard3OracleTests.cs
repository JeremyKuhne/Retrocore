// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  The SoftCard /// against MAME: booting CP/M from its master disk, the Z80 must run the same instructions from its
///  first switch.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\SoftCardOracle.lua</c>
///   on an Apple III with the card in slot 4, from a ROM path the test builds out of the Apple III's ROM and the card's
///   <c>softcard3.rom</c>. The test is inconclusive without MAME, the ROMs or the disk. Loops repeated back to back
///   count once, as in <see cref="Apple2SoftCardOracleTests"/>.
///  </para>
/// </remarks>
[TestClass]
public class SoftCard3OracleTests
{
    private const string Master = "Apple Softcard III CPM Master Diskette (076-0002) Apple 1982.dsk";
    private const int Seconds = 12;

    /// <summary>
    ///  From the first switch, the card's self-test, to CP/M's wait for a key.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void CpmBootMatchesMame()
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string fixtures = Environment.GetEnvironmentVariable("RETROCORE_SOFTCARD3")
            ?? Path.Join(ExternalTestData.Root, "softcard3");

        string disk = Path.Join(fixtures, Master);
        string prom = Path.Join(fixtures, "extract", "softcard3.rom");
        string apple3 = Apple3MachineTests.RomDirectory;
        string[] needed = [mame, disk, prom, Path.Join(apple3, Apple3Roms.BootRomFile)];
        if (!needed.All(File.Exists))
        {
            Assert.Inconclusive("MAME, the Apple III or SoftCard /// ROM, or the CP/M master is missing.");
        }

        string roms = Directory.CreateTempSubdirectory("retrocore-roms").FullName;
        try
        {
            Directory.CreateDirectory(Path.Join(roms, "apple3"));
            Directory.CreateDirectory(Path.Join(roms, "softcard3"));
            foreach (string file in Directory.GetFiles(apple3))
            {
                File.Copy(file, Path.Join(roms, "apple3", Path.GetFileName(file)));
            }

            File.Copy(prom, Path.Join(roms, "softcard3", "softcard3.rom"));
            List<ushort> expected = Apple2SoftCardOracleTests.RunMame(
                mame,
                ["apple3", "-sl4", "softcard3", "-rompath", roms],
                ":sl4:softcard3:z80",
                disk,
                Seconds);

            Apple2SoftCardOracleTests.Compare(expected, RunMachine(disk));
        }
        finally
        {
            Directory.Delete(roms, recursive: true);
        }
    }

    private static List<ushort> RunMachine(string disk)
    {
        Apple3Machine machine = Apple3MachineTests.Machine();
        SoftCard3 card = machine.Bus.InstallSoftCard(slot: 4, SoftCard3Tests.Prom());
        machine.Drives[0].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(disk), proDosOrder: false), Master, "DSK");
        List<ushort> rows = Apple2SoftCardOracleTests.Record(card);
        machine.Run(TimeSpan.FromSeconds(Seconds));
        return Apple2SoftCardOracleTests.Finish(card, rows);
    }
}
