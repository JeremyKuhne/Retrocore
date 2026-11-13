// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  One of the four floppy drives on a TRS-80 disk controller: the Model I's Expansion Interface or the Color
///  Computer's disk controller cartridge.
/// </summary>
public sealed class Trs80FloppyDrive : IDiskDrive
{
    private readonly Trs80DiskController _controller;
    private string _label = "";
    private string _format = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="controller">The disk controller.</param>
    /// <param name="drive">The drive, 0-3.</param>
    /// <param name="doubler">The doubler fitted to the controller.</param>
    internal Trs80FloppyDrive(Trs80DiskController controller, int drive, Trs80Doubler doubler)
        : this(controller, drive, Model1Info(drive, doubler))
    {
    }

    /// <summary>
    ///  Creates a drive that describes itself.
    /// </summary>
    /// <param name="controller">The disk controller.</param>
    /// <param name="drive">The drive, 0-3.</param>
    /// <param name="info">The drive's description.</param>
    internal Trs80FloppyDrive(Trs80DiskController controller, int drive, DeviceInfo info)
    {
        _controller = controller;
        Drive = drive;
        Id = $"disk{drive}";
        Info = info;
    }

    private static DeviceInfo Model1Info(int drive, Trs80Doubler doubler) => new()
    {
        Name = $"Drive {drive}",
        Description = "5¼-inch floppy drive",
        Controller = doubler switch
        {
            Trs80Doubler.Percom => "FD1771 with a Percom doubler's WD1791, in the Expansion Interface",
            Trs80Doubler.Tandy => "FD1771 with the Radio Shack doubler's WD1791, in the Expansion Interface",
            Trs80Doubler.Both => "FD1771 with a WD1791 doubler (Percom or Radio Shack), in the Expansion Interface",
            _ => "FD1771 in the Expansion Interface"
        },
        Formats = ["dsk", "jv1", "jv3", "dmk", "imd"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect,
        Tracks = 40,

        // Drive 3's select line is the other drives' side select, so drive 3 is single-sided.
        Sides = drive == 3 ? 1 : 2
    };

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
        ? new(_label, _format, disk.WriteProtected, _controller.Changed(Drive))
        : null;

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
        _label = label;
        _format = format;
    }

    /// <summary>
    ///  Ejects the disk.
    /// </summary>
    /// <returns>The disk, or null when the drive was empty.</returns>
    public FloppyDisk? Eject()
    {
        FloppyDisk? disk = Disk;
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
        (Disk ?? throw new InvalidOperationException($"{Info.Name} is empty.")).WriteProtected = writeProtected;
}
