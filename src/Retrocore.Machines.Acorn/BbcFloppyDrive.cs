// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Floppy;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  One of the two 5¼-inch drives on the BBC Micro's 8271. The DFS calls a drive's sides two drives: drive 0's second
///  side is DFS drive 2, drive 1's is drive 3.
/// </summary>
public sealed class BbcFloppyDrive : IDiskDrive, IMediumSlot
{
    private readonly Intel8271 _controller;
    private string _label = "";
    private string _format = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="controller">The 8271.</param>
    /// <param name="drive">0 or 1.</param>
    internal BbcFloppyDrive(Intel8271 controller, int drive)
    {
        _controller = controller;
        Drive = drive;
        Id = $"disk{drive}";
        Info = new()
        {
            Name = $"Drive {drive} ({drive + 2} on side 1)",
            Description = "5¼-inch floppy drive, 40 or 80 tracks, single density",
            Controller = "Intel 8271 on the Acorn disk interface",
            Formats = ["ssd", "dsd"],
            SaveFormats = ["ssd", "dsd"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
            Tracks = 80,
            Sides = 2
        };
    }

    /// <summary>
    ///  Gets the drive's number on the 8271, 0 or 1.
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
    public FloppyDisk? Disk => _controller.Disk(Drive);

    /// <inheritdoc/>
    public MediaState? Media => Disk is { } disk ? new(_label, _format, disk.IsWriteProtected, disk.IsDirty) : null;

    /// <inheritdoc/>
    public IMedium? Medium => Disk;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <inheritdoc/>
    public DeviceActivity Activity => !_controller.IsBusy || _controller.SelectedDrive != Drive || Disk is null
        ? DeviceActivity.Idle
        : _controller.Sector is null
            ? DeviceActivity.Seeking
            : _controller.IsWriting ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public DiskHead Head
    {
        get
        {
            bool selected = _controller.SelectedDrive == Drive;
            return new(
                _controller.HeadLoaded,
                selected,
                _controller.Cylinder(Drive),
                selected ? _controller.Side : 0,
                selected && _controller.IsBusy ? _controller.Sector : null);
        }
    }

    /// <summary>
    ///  Inserts a disk.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">What the host calls it, such as its image's path.</param>
    /// <param name="format">Its image format: <c>SSD</c> or <c>DSD</c>.</param>
    public void Insert(FloppyDisk disk, string label, string format)
    {
        ArgumentNullException.ThrowIfNull(disk);
        _controller.Insert(Drive, disk);
        MountGeneration = MountGenerations.Next();
        _label = label;
        _format = format;
    }

    /// <summary>
    ///  Ejects the disk, leaving any unsaved changes to the caller.
    /// </summary>
    /// <returns>The disk, or null when the drive was empty.</returns>
    public FloppyDisk? Eject()
    {
        FloppyDisk? disk = Disk;
        if (disk is not null) { MountGeneration = MountGenerations.Next(); }
        _controller.Insert(Drive, disk: null);
        _label = "";
        _format = "";
        return disk;
    }

    /// <summary>
    ///  Covers or uncovers the disk's write-protect notch.
    /// </summary>
    /// <param name="writeProtected">Whether the disk is protected.</param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    public void SetWriteProtected(bool writeProtected) =>
        (Disk ?? throw new InvalidOperationException($"{Info.Name} is empty.")).IsWriteProtected = writeProtected;

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        FloppyDisk disk = Disk ?? throw new InvalidOperationException($"{Info.Name} is empty.");
        if (whole) { disk.MarkSaved(); }
        else { disk.MarkChanged(); }
        _label = label;
        _format = format;
    }

    /// <inheritdoc/>
    public void Mount(IMedium medium, string label, string format) =>
        Insert(medium as FloppyDisk ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label, format);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();
}
