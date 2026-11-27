// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Serial;

namespace Retrocore.Tests;

/// <summary>
///  The 1541's gate array on its own, with no disk and no ROMs: its bit counter still runs while the motor does, so
///  BYTE READY pulses each eighth bit while SOE lets it.
/// </summary>
[TestClass]
public class Cbm1541GateArrayTests
{
    /// <summary>
    ///  SOE going low while BYTE READY is low raises it, and the next run counts that change, so the drive passes it
    ///  to CA1 and SO rather than losing the edge.
    /// </summary>
    [TestMethod]
    public void SoeRaisingByteReadyIsCounted()
    {
        (CommodoreFloppyDrive drive, Cbm1541GateArray gate) = Running();
        RunToByteReady(gate);

        gate.ByteReadyEnabled = false;
        gate.ByteReady.Should().BeTrue("SOE low holds BYTE READY high");
        gate.Advance(ticks: 16);
        gate.ByteReadyChanges.Should().Be(1, "the rise SOE made is counted, and BYTE READY stays high");
        drive.Motor.Should().BeTrue();
    }

    /// <summary>
    ///  The motor stopping while BYTE READY is low raises it, and that is counted too.
    /// </summary>
    [TestMethod]
    public void MotorStoppingRaisesByteReady()
    {
        (CommodoreFloppyDrive drive, Cbm1541GateArray gate) = Running();
        RunToByteReady(gate);

        drive.Motor = false;
        gate.Advance(ticks: 16);
        gate.ByteReady.Should().BeTrue();
        gate.ByteReadyChanges.Should().Be(1);
    }

    // A single drive with its motor on, reading, and its gate array with SOE high.
    private static (CommodoreFloppyDrive Drive, Cbm1541GateArray Gate) Running()
    {
        CommodoreFloppyDrive drive = new("disk8", "Drive 8", "A 1541", "Its gate array", ["g64", "d64"], drive: 0);
        Cbm1541GateArray gate = new(drive) { ReadSelect = true, ByteReadyEnabled = true };
        drive.Motor = true;
        gate.Advance(ticks: 16);
        return (drive, gate);
    }

    // Runs a microsecond at a time until BYTE READY is low after a run.
    private static void RunToByteReady(Cbm1541GateArray gate)
    {
        for (int microsecond = 0; microsecond < 1000 && gate.ByteReady; microsecond++) { gate.Advance(ticks: 16); }
        gate.ByteReady.Should().BeFalse("a byte's worth of bits has passed");
    }
}
