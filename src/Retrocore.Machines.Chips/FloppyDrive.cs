// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Floppy;

namespace Retrocore.Machines.Chips;

/// <summary>
///  One of the four floppy drives on a <see cref="WesternDigitalFloppyDiskController"/>.
/// </summary>
/// <remarks>
///  <para>
///   Its disk is a medium a host saves, to the formats <see cref="DeviceInfo.SaveFormats"/> lists. The machine
///   describes the drive: its size, sides, tracks and formats.
///  </para>
/// </remarks>
public sealed class FloppyDrive : IDiskDrive, IMediumSlot
{
    private readonly WesternDigitalFloppyDiskController _controller;
    private string _label = "";
    private string _format = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="controller">The disk controller.</param>
    /// <param name="drive">The drive, 0-3.</param>
    /// <param name="info">The drive's description.</param>
    internal FloppyDrive(WesternDigitalFloppyDiskController controller, int drive, DeviceInfo info)
    {
        _controller = controller;
        Drive = drive;
        Id = $"disk{drive}";
        Info = info;
    }

    /// <summary>
    ///  Gets the drive's number, 0-3.
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
    public MediaState? Media => Disk is { } disk
        ? new(_label, _format, disk.IsWriteProtected, disk.IsDirty)
        : null;

    /// <inheritdoc/>
    public IMedium? Medium => Disk;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <inheritdoc/>
    public DeviceActivity Activity => _controller.Activity(Drive);

    /// <inheritdoc/>
    public DiskHead Head
    {
        get
        {
            bool selected = _controller.SelectedDrive == Drive;
            return new(
                _controller.MotorOn,
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
    /// <param name="format">Its image format, such as <c>JV3</c>.</param>
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

    /// <inheritdoc/>
    public void Mount(IMedium medium, string label, string format) =>
        Insert(medium as FloppyDisk ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label, format);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

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
        if (whole)
        {
            disk.MarkSaved();
        }
        else
        {
            disk.MarkChanged();
        }

        _label = label;
        _format = format;
    }
}
