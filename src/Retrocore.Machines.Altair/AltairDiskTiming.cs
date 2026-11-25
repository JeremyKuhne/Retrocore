// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Altair;

namespace Retrocore.Machines.Altair;

/// <summary>
///  The 88-DCDD's and the Pertec FD-400's timing, in CPU cycles at 2 MHz (two cycles a microsecond).
/// </summary>
/// <remarks>
///  <para>
///   The figures are those Mike Douglas's FDC+ uses to reproduce MITS's controller (its firmware's
///   <c>altair-8in.s</c>): the disk turns at 360 RPM, a revolution of 32 hard sectors in 166.67 ms, and data passes
///   a bit every 4 µs, a byte every 32 µs. His "Disk IO Timing" note on MITS's read loops agrees on the byte time.
///  </para>
/// </remarks>
public static class AltairDiskTiming
{
    /// <summary>
    ///  The cycles one sector takes to pass the head: 5.2085 ms, so 32 make a revolution of 166.67 ms.
    /// </summary>
    public const int SectorCycles = 10_417;

    /// <summary>
    ///  The cycles a revolution takes.
    /// </summary>
    public const int RevolutionCycles = SectorCycles * AltairDisk.SectorsPerTrack;

    /// <summary>
    ///  How long Sector True stays asserted after a sector's pulse: 32 µs.
    /// </summary>
    public const int SectorTrueCycles = 64;

    /// <summary>
    ///  How far into a sector a write enable still starts writing that sector: the controller ignores read data for
    ///  the first 212 µs, and a write it is told of in that time writes this sector. One told of later is forgotten at
    ///  <see cref="EndOfSectorCycles"/>, so only one after that writes the next sector.
    /// </summary>
    public const int ReadClearCycles = 424;

    /// <summary>
    ///  When a write's first handshake comes: 388 µs into the sector, after zeros have been written over the start.
    ///  The controller writes one more byte of zeros while the 8080 sends its first byte, which is taken a byte time
    ///  later.
    /// </summary>
    public const int WriteClearCycles = 776;

    /// <summary>
    ///  When a sector's first byte is ready to read: written a byte of zeros after <see cref="WriteClearCycles"/>, it
    ///  is assembled a byte time after it begins, 452 µs into the sector.
    /// </summary>
    public const int FirstByteCycles = WriteClearCycles + (2 * ByteCycles);

    /// <summary>
    ///  The cycles a byte takes: 32 µs.
    /// </summary>
    public const int ByteCycles = 64;

    /// <summary>
    ///  The cycles a bit takes: 4 µs.
    /// </summary>
    public const int BitCycles = ByteCycles / 8;

    /// <summary>
    ///  When the controller ends a sector's reading or writing: about 200 µs past its data, 5.008 ms into it, as the
    ///  FDC+ counts it in 4 µs ticks.
    /// </summary>
    public const int EndOfSectorCycles = 10_016;

    /// <summary>
    ///  When, in the sector after a write, the drive's trim erase ends and head movement is allowed again: 452 µs.
    /// </summary>
    public const int TrimEraseCycles = 904;

    /// <summary>
    ///  How long after a step the controller holds off head movement: 10.5 ms.
    /// </summary>
    public const int StepCycles = 21_000;

    /// <summary>
    ///  How long, after <see cref="StepCycles"/>, a further step is allowed before the head settles: 1 ms.
    /// </summary>
    public const int StepWindowCycles = 2_000;

    /// <summary>
    ///  How long after that window movement is held off again, while the head settles: 32 ms.
    /// </summary>
    public const int SettleStepCycles = 64_000;

    /// <summary>
    ///  How long after a head load, or a step, the head is loaded and settled for reading and writing: 50 ms.
    /// </summary>
    public const int HeadLoadCycles = 100_000;
}
