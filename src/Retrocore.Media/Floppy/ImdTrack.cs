// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  A track as an IMD image has it, which <see cref="ImdFormat"/> reads and writes back.
/// </summary>
/// <param name="Mode">Its mode: 0-2 single density at 500, 300 and 250 kbps, 3-5 double density.</param>
/// <param name="Cylinder">The cylinder it lies on.</param>
/// <param name="Side">The side it lies on, the head byte's bit 0.</param>
/// <param name="Head">The head byte, with bit 7 for a cylinder map and bit 6 for a head map.</param>
/// <param name="SizeCode">Its sectors' size code, 0 for 128 bytes to 6 for 8192.</param>
/// <param name="Numbers">Its sector numbers in rotational order.</param>
/// <param name="Cylinders">Each sector's ID cylinder, or empty when they are the track's.</param>
/// <param name="Heads">Each sector's ID head, or empty when they are the side's.</param>
/// <param name="Records">
///  Each sector's record type: 0 for no data, then odd for data and even for a filled sector.
/// </param>
/// <param name="Data">Each sector's data, null for one with none.</param>
internal sealed record ImdTrack(
    byte Mode,
    byte Cylinder,
    int Side,
    byte Head,
    byte SizeCode,
    byte[] Numbers,
    byte[] Cylinders,
    byte[] Heads,
    byte[] Records,
    byte[]?[] Data);
