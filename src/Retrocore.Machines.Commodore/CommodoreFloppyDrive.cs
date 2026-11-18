// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  One of a Commodore dual drive's two mechanisms: a 5¼-inch single-sided drive with a stepper that moves the head
///  a half track at a step, and its disk turning at 300 rpm while its motor runs.
/// </summary>
public sealed class CommodoreFloppyDrive : IDiskDrive, IMediumSlot
{
    /// <summary>
    ///  The 16 MHz ticks of one turn of the disk.
    /// </summary>
    internal const long TicksPerTurn = 3_200_000;

    private CommodoreDisk? _disk;
    private string _label = "";
    private string _format = "";
    private int _phase;

    /// <summary>
    ///  Builds a mechanism.
    /// </summary>
    /// <param name="unit">The unit's device number, 8-15.</param>
    /// <param name="drive">0 or 1.</param>
    /// <param name="model">
    ///  The unit's name, <c>2040</c> or <c>4040</c>; a 2040's disks save as D67 sectors, a 4040's as D64.
    /// </param>
    internal CommodoreFloppyDrive(int unit, int drive, string model)
    {
        Drive = drive;
        Id = $"disk{unit}-{drive}";
        Info = new()
        {
            Name = $"Drive {drive} of unit {unit}",
            Description = $"Commodore {model} dual drive, 5¼-inch single-sided, 35 tracks",
            Controller = $"The {model}'s 6504 and its GCR read/write logic, on the IEEE-488 bus as device {unit}",
            Formats = ["d64", "d67", "g64"],
            SaveFormats = model == "2040" ? ["g64", "d67"] : ["g64", "d64"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
            Tracks = 35,
            Sides = 1
        };
    }

    /// <summary>
    ///  Gets the mechanism's number in its unit, 0 or 1.
    /// </summary>
    public int Drive { get; }

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.FloppyDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the disk in the drive, or null.
    /// </summary>
    public CommodoreDisk? Disk => _disk;

    /// <summary>
    ///  Gets the head's half-track position, 0 (track 1) to 83.
    /// </summary>
    public int Position { get; private set; }

    /// <summary>
    ///  Gets whether the spindle motor runs.
    /// </summary>
    public bool Motor { get; internal set; }

    /// <summary>
    ///  Gets whether the controller has this mechanism selected.
    /// </summary>
    public bool Selected { get; internal set; }

    /// <summary>
    ///  Gets where the disk is in its turn, in 16 MHz ticks.
    /// </summary>
    internal long Angle { get; private set; }

    /// <inheritdoc/>
    public DiskHead Head => new(Motor, Selected, (Position / 2.0) + 1, 0, Sector: null);

    /// <inheritdoc/>
    public MediaState? Media => _disk is null ? null : new(_label, _format, _disk.IsWriteProtected, _disk.IsDirty);

    /// <inheritdoc/>
    public DeviceActivity Activity => !Motor || _disk is null ? DeviceActivity.Idle : DeviceActivity.Reading;

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => _disk;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <summary>
    ///  Puts a disk in.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">Its name, for display.</param>
    /// <param name="format">Its image format, such as <c>D64</c>.</param>
    /// <param name="changed">Whether it differs from its image, as a blank disk does.</param>
    public void Insert(CommodoreDisk disk, string label, string format, bool changed = false)
    {
        ArgumentNullException.ThrowIfNull(disk);
        if (changed) { disk.MarkChanged(); } else { disk.MarkSaved(); }
        Load(disk, label, format);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk keeps its changes, as a disk put back for Undo has them.
    ///  </para>
    /// </remarks>
    public void Mount(IMedium medium, string label, string format) => Load(
        medium as CommodoreDisk ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)),
        label,
        format);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Takes the disk out.
    /// </summary>
    /// <returns>The disk, or null.</returns>
    public CommodoreDisk? Eject()
    {
        CommodoreDisk? disk = _disk;
        _disk = null;
        _label = "";
        _format = "";
        MountGeneration = MountGenerations.Next();
        return disk;
    }

    /// <summary>
    ///  Sets the disk's write protection, as covering its notch does.
    /// </summary>
    /// <param name="writeProtected">Whether it is protected.</param>
    public void SetWriteProtected(bool writeProtected)
    {
        _disk?.IsWriteProtected = writeProtected;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (_disk is null) { throw new InvalidOperationException($"{Info.Name} is empty."); }
        _label = label;
        _format = format;
        if (whole) { _disk.MarkSaved(); } else { _disk.MarkChanged(); }
    }

    private void Load(CommodoreDisk disk, string label, string format)
    {
        _disk = disk;
        _label = label;
        _format = format;
        MountGeneration = MountGenerations.Next();
    }

    /// <summary>
    ///  Drives the stepper's two phases: a step to the next phase up moves the head inward a half track, down
    ///  outward. With the motor stopped the stepper is not powered, and the phases it is given count for nothing.
    /// </summary>
    /// <param name="phase">The phases, 0-3.</param>
    internal void Step(int phase)
    {
        phase &= 3;
        if (!Motor || phase == _phase) { return; }

        if (phase == ((_phase + 1) & 3)) { Position = Math.Min(Position + 1, CommodoreDisk.Positions - 1); }
        else if (phase == ((_phase + 3) & 3)) { Position = Math.Max(Position - 1, 0); }
        _phase = phase;
    }

    /// <summary>
    ///  Turns the disk while the motor runs.
    /// </summary>
    /// <param name="ticks">16 MHz ticks.</param>
    internal void Turn(int ticks)
    {
        if (!Motor) { return; }
        Angle += ticks;
        if (Angle >= TicksPerTurn) { Angle -= TicksPerTurn; }
    }
}
