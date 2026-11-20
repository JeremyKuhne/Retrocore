// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Altair;

namespace Retrocore.Machines.Altair;

/// <summary>
///  A Pertec FD-400 8-inch drive on the 88-DCDD: its head's track, whether it is loaded, and its step and settle
///  times.
/// </summary>
/// <remarks>
///  <para>
///   A step moves the head at once, but the status shows the move as the drive does: head movement is held off for
///   <see cref="AltairDiskTiming.StepCycles"/>, when track 0 also changes, then allowed for
///   <see cref="AltairDiskTiming.StepWindowCycles"/> so a seek can step again, then held off while the head settles,
///   until <see cref="AltairDiskTiming.HeadLoadCycles"/> after the step. Loading the head takes the same 50 ms to
///   settle. Selecting a drive unloads its head, as the controller drops every drive signal first.
///  </para>
/// </remarks>
public sealed partial class AltairDiskDrive
{
    private readonly AltairDiskController _controller;
    private ulong _settleAt;
    private ulong _stepAt;
    private bool _stepped;
    private bool _trackZeroBefore;

    /// <summary>
    ///  Builds a drive.
    /// </summary>
    /// <param name="controller">The controller it is on.</param>
    /// <param name="number">Its number, 0-15.</param>
    internal AltairDiskDrive(AltairDiskController controller, int number)
    {
        _controller = controller;
        Number = number;
        Id = $"disk{number}";
    }

    /// <summary>
    ///  Gets the drive's number on the controller.
    /// </summary>
    public int Number { get; }

    /// <summary>
    ///  Gets the track the head is on, 0-76.
    /// </summary>
    public int Track { get; private set; }

    /// <summary>
    ///  Gets whether the head is loaded against the disk.
    /// </summary>
    public bool HeadLoaded { get; private set; }

    /// <summary>
    ///  Gets whether the head is loaded and has settled.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    /// <returns>True once the head may read and write.</returns>
    internal bool Settled(ulong cycle) => HeadLoaded && cycle >= _settleAt;

    /// <summary>
    ///  Gets whether the status allows a step.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    /// <returns>True when head movement is allowed.</returns>
    internal bool MayStep(ulong cycle)
    {
        if (!_stepped) { return true; }
        ulong since = cycle - _stepAt;
        if (since < AltairDiskTiming.StepCycles) { return false; }
        if (since < AltairDiskTiming.StepCycles + AltairDiskTiming.StepWindowCycles) { return true; }
        return since >= AltairDiskTiming.StepCycles + AltairDiskTiming.StepWindowCycles + AltairDiskTiming.SettleStepCycles;
    }

    /// <summary>
    ///  Gets track 0 as the status shows it, which follows a step only once the step's first period ends.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    /// <returns>True when the status shows track 0.</returns>
    internal bool AtTrackZero(ulong cycle) =>
        _stepped && cycle - _stepAt < AltairDiskTiming.StepCycles ? _trackZeroBefore : Track == 0;

    /// <summary>
    ///  Steps the head a track, as far as track 0 and track 76.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    /// <param name="inward">Whether to step in, toward the higher tracks.</param>
    internal void Step(ulong cycle, bool inward)
    {
        _trackZeroBefore = AtTrackZero(cycle);
        if (inward)
        {
            if (Track < AltairDisk.Tracks - 1) { Track++; }
        }
        else if (Track > 0)
        {
            Track--;
        }

        _stepAt = cycle;
        _stepped = true;
        _settleAt = cycle + AltairDiskTiming.HeadLoadCycles;
    }

    /// <summary>
    ///  Loads the head, which settles <see cref="AltairDiskTiming.HeadLoadCycles"/> later.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    internal void Load(ulong cycle)
    {
        HeadLoaded = true;
        _settleAt = cycle + AltairDiskTiming.HeadLoadCycles;
    }

    /// <summary>
    ///  Unloads the head.
    /// </summary>
    internal void Unload() => HeadLoaded = false;

    /// <summary>
    ///  Readies the drive as the controller selects it: the head is unloaded and may be stepped.
    /// </summary>
    /// <param name="cycle">The cycle count now.</param>
    internal void Selected(ulong cycle)
    {
        HeadLoaded = false;
        _stepped = false;
        _settleAt = cycle;
    }
}
