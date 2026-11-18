// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Machines.Devices;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  A Commodore drive mechanism's spindle and what it reports, and the PET's sound output's rates, with no ROMs.
/// </summary>
[TestClass]
public class CommodoreFloppyDriveTests
{
    /// <summary>
    ///  Turning many revolutions at once leaves the angle within one turn.
    /// </summary>
    [TestMethod]
    public void ManyTurnsWrapTheAngle()
    {
        CommodoreFloppyDrive drive = new(8, 0, "4040") { Motor = true };
        drive.Turn((int)(CommodoreFloppyDrive.TicksPerTurn * 4) + 7);
        drive.Angle.Should().Be(7);
    }

    /// <summary>
    ///  A mechanism reads while its motor runs, and writes while the controller has it selected for writing.
    /// </summary>
    [TestMethod]
    public void ItSaysWhenItWrites()
    {
        CommodoreFloppyDrive drive = new(8, 0, "4040");
        drive.Activity.Should().Be(DeviceActivity.Idle);
        drive.Insert(CommodoreDisk.Blank(), "blank", "D64", changed: true);
        drive.Motor = true;
        drive.Activity.Should().Be(DeviceActivity.Reading);
        drive.Writing = true;
        drive.Activity.Should().Be(DeviceActivity.Writing);
    }

    /// <summary>
    ///  The sound output takes a rate of a sample a CPU cycle at most.
    /// </summary>
    /// <param name="rate">The rate.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(-1)]
    [DataRow(2_000_000)]
    public void SoundRatesAreChecked(int rate)
    {
        Action create = () => _ = new PetAudio(rate);
        create.Should().Throw<ArgumentOutOfRangeException>();
        new PetAudio(PetTiming.CpuHertz).SampleRate.Should().Be(PetTiming.CpuHertz);
    }
}
