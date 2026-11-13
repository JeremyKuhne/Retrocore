// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  One of the Disk II card's two drives.
/// </summary>
public sealed class Apple2FloppyDrive : IDiskDrive
{
    private readonly DiskIIController _controller;
    private string _label = "";
    private string _format = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="controller">The Disk II card.</param>
    /// <param name="drive">One or two.</param>
    /// <param name="slot">The slot of the card.</param>
    internal Apple2FloppyDrive(DiskIIController controller, int drive, int slot = 6)
        : this(
            controller,
            drive,
            // Slot six's drives keep the names they had when it was the only slot with a Disk II.
            slot == 6 ? $"disk{drive}" : $"slot{slot}disk{drive}",
            slot == 6 ? $"Drive {drive}" : $"Slot {slot}, drive {drive}",
            "Disk II 5¼-inch floppy drive",
            $"Disk II controller in slot {slot}") => Slot = slot;

    /// <summary>
    ///  Constructs a drive for a machine that names its drives itself, as the Apple III does.
    /// </summary>
    /// <param name="controller">The controller.</param>
    /// <param name="drive">The drive, from one.</param>
    /// <param name="id">The device's identifier.</param>
    /// <param name="name">The drive's name.</param>
    /// <param name="description">What the drive is.</param>
    /// <param name="controllerName">What the controller is.</param>
    internal Apple2FloppyDrive(
        DiskIIController controller,
        int drive,
        string id,
        string name,
        string description,
        string controllerName)
    {
        _controller = controller;
        Drive = drive;
        Id = id;
        Info = new()
        {
            Name = name,
            Description = description,
            Controller = controllerName,
            Formats = ["woz", "dsk", "do", "po"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
            Tracks = 35,
            Sides = 1
        };
    }

    /// <summary>
    ///  Gets the drive's number, one or two.
    /// </summary>
    public int Drive { get; }

    /// <summary>
    ///  Gets the slot of the card the drive is on.
    /// </summary>
    public int Slot { get; }

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.FloppyDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <inheritdoc/>
    public MediaState? Media
    {
        get
        {
            DiskDriveState state = _controller.State(Drive);
            return state.Mounted ? new(_label, _format, state.WriteProtected, state.Dirty) : null;
        }
    }

    /// <inheritdoc/>
    /// <remarks>The Disk II's head reads whenever the motor turns, and writes in the card's write mode.</remarks>
    public DeviceActivity Activity
    {
        get
        {
            DiskDriveState state = _controller.State(Drive);
            if (!state.Motor || !state.Mounted) { return DeviceActivity.Idle; }
            return _controller.WriteMode ? DeviceActivity.Writing : DeviceActivity.Reading;
        }
    }

    /// <inheritdoc/>
    /// <remarks>The head steps in quarter tracks, so the track can have a fraction.</remarks>
    public DiskHead Head
    {
        get
        {
            DiskDriveState state = _controller.State(Drive);
            return new(state.Motor, _controller.SelectedDrive == Drive, state.QuarterTrack / 4.0, Side: 0, Sector: null);
        }
    }

    /// <summary>
    ///  Inserts a disk.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">What the host calls it, such as its image's path.</param>
    /// <param name="format">Its image format, such as <c>WOZ</c>.</param>
    /// <exception cref="InvalidOperationException">The Disk II card's firmware is not installed.</exception>
    public void Insert(WozDisk disk, string label, string format)
    {
        _controller.Mount(Drive, disk);
        _label = label;
        _format = format;
    }

    /// <summary>
    ///  Gets the disk in the drive, which stays in it; null when the drive is empty.
    /// </summary>
    public WozDisk? Disk => _controller.MediaIn(Drive);

    /// <summary>
    ///  Covers or uncovers the disk's write-protect notch. The disk keeps what is written to it in memory; its image
    ///  file does not change.
    /// </summary>
    /// <param name="writeProtected">Whether the disk is protected.</param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    public void SetWriteProtected(bool writeProtected) =>
        (Disk ?? throw new InvalidOperationException($"{Info.Name} is empty.")).IsReadOnly = writeProtected;

    /// <summary>
    ///  Records that the disk was saved to an image, which it now comes from.
    /// </summary>
    /// <param name="label">What the host calls the image, such as its path.</param>
    /// <param name="format">Its image format, such as <c>WOZ</c>.</param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    public void Saved(string label, string format)
    {
        (Disk ?? throw new InvalidOperationException($"{Info.Name} is empty.")).MarkSaved();
        _label = label;
        _format = format;
    }

    /// <summary>
    ///  Ejects the disk, leaving any unsaved changes to the caller.
    /// </summary>
    /// <returns>The disk, or null when the drive was empty.</returns>
    public WozDisk? Eject()
    {
        _label = "";
        _format = "";
        return _controller.Eject(Drive);
    }
}
