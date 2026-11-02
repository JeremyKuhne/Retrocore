// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.DiskTool;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the DosDisk tool's reading of host files and its disks.
/// </summary>
[TestClass]
public sealed class DosDiskToolTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  A file named in CiderPress II's style takes its DOS type from the ProDOS type, and a binary its load
    ///  address from the auxiliary type.
    /// </summary>
    [TestMethod]
    public void TypedNamesGiveTheFileType()
    {
        string folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string path = Path.Join(folder, "GAME#062000");
            File.WriteAllBytes(path, [0xEA, 0x60]);

            DosFile file = DosDiskBuilder.ReadFile(path);
            file.Name.Should().Be("GAME");
            file.Type.Should().Be(DosFileType.Binary);
            file.Contents.ToArray().Should().Equal(0x00, 0x20, 0x02, 0x00, 0xEA, 0x60);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The tool's disk, with an AppleSoft listing from the folder and a HELLO that runs it, boots and runs it.
    /// </summary>
    [TestMethod]
    public void BuiltDiskRunsTheProgram()
    {
        string folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            File.WriteAllText(Path.Join(folder, "GAME.bas"), "10 POKE 7,90\n");
            byte[] disk = DosDiskBuilder.Build(
                new DosDiskOptions { Files = folder, Run = "GAME", Sources = s_inputs });

            Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
            machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(sectors: 16, s_inputs));
            machine.Drives[0].Insert(SectorDiskConverter.Convert(disk, proDosOrder: false), "built", "DSK");
            for (int second = 0; second < 15 && machine.Bus.Peek(0x07) != 90; second++)
            {
                machine.Run(BasicMachines.IIeClock);
            }

            machine.Bus.Peek(0x07).Should().Be(90, "DOS booted and HELLO ran GAME");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
