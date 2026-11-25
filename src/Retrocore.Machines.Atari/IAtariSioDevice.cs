// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  A peripheral on the serial bus that answers command frames at the command level, as the SIO protocol has it: an
///  ACK or NAK for the command, a data frame from the computer if the command takes one, then Complete or Error and a
///  data frame from the device if the command returns one.
/// </summary>
/// <remarks>
///  <para>
///   Devices emulated at the hardware level, such as <see cref="Atari810"/>, don't use it: they drive the bus's
///   lines bit by bit.
///  </para>
/// </remarks>
internal interface IAtariSioDevice
{
    /// <summary>
    ///  Gets the device ID the command frames address, such as <c>$31</c> for <c>D1:</c>.
    /// </summary>
    byte DeviceId { get; }

    /// <summary>
    ///  Checks a command frame addressed to the device.
    /// </summary>
    /// <param name="command">The command byte.</param>
    /// <param name="aux">The auxiliary bytes, AUX1 in the low byte.</param>
    /// <returns>
    ///  Null to NAK the command; otherwise the length of the data frame the computer sends next, or 0 for none.
    /// </returns>
    int? Accept(byte command, ushort aux);

    /// <summary>
    ///  Runs an accepted command.
    /// </summary>
    /// <param name="command">The command byte.</param>
    /// <param name="aux">The auxiliary bytes, AUX1 in the low byte.</param>
    /// <param name="data">The data frame the computer sent, without its checksum, or empty.</param>
    /// <param name="cycle">The machine cycle the command runs at.</param>
    /// <returns>
    ///  Whether it succeeded (Complete rather than Error), the data frame to send back (empty for none), and how long
    ///  the command takes, in machine cycles.
    /// </returns>
    (bool Success, byte[] Data, int Cycles) Execute(byte command, ushort aux, ReadOnlySpan<byte> data, long cycle);
}
