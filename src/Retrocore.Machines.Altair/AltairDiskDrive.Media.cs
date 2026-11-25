// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Altair;

namespace Retrocore.Machines.Altair;

// The drive as a device that holds a disk: what is in it, and inserting, ejecting and saving it.
public sealed partial class AltairDiskDrive : IDiskDrive, IMediumSlot
{
    private AltairDisk? _disk;
    private string _label = "";
    private string _format = "";

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.FloppyDrive;

    /// <inheritdoc/>
    public DeviceInfo Info => new()
    {
        Name = $"Drive {Number}",
        Description = "Pertec FD-400 8-inch drive",
        Controller = "the 88-DCDD, ports $08-$0A",
        Formats = ["dsk"],
        SaveFormats = ["dsk"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
        Tracks = AltairDisk.Tracks,
        Sides = 1
    };

    /// <summary>
    ///  Gets the disk in the drive, or null.
    /// </summary>
    public AltairDisk? Disk => _disk;

    /// <inheritdoc/>
    public MediaState? Media => _disk is null ? null : new(_label, _format, _disk.IsWriteProtected, _disk.IsDirty);

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => _disk;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <inheritdoc/>
    public DeviceActivity Activity => _controller.Selected != this || _disk is null
        ? DeviceActivity.Idle
        : _controller.Writing ? DeviceActivity.Writing : HeadLoaded ? DeviceActivity.Reading : DeviceActivity.Idle;

    /// <inheritdoc/>
    /// <remarks>The FD-400's motor turns whenever the drive has power, so a disk in it is always turning.</remarks>
    public DiskHead Head
    {
        get
        {
            bool selected = _controller.Selected == this;
            int? sector = selected && HeadLoaded ? _controller.Sector : null;
            return new(_disk is not null, selected, Track, 0, sector);
        }
    }

    /// <summary>
    ///  Puts a disk in the drive.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    /// <param name="format">Its image format.</param>
    /// <param name="changed">Whether it has changes its image lacks.</param>
    public void Insert(AltairDisk disk, string label, string format, bool changed = false)
    {
        ArgumentNullException.ThrowIfNull(disk);
        if (changed) { disk.MarkChanged(); } else { disk.MarkSaved(); }
        Load(disk, label, format);
    }

    /// <inheritdoc/>
    public void Mount(IMedium medium, string label, string format) => Load(
        medium as AltairDisk ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)),
        label,
        format);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Takes the disk out. The controller lets go of the drive; a write in progress keeps the bytes it has written.
    /// </summary>
    /// <returns>The disk, or null when the drive was empty.</returns>
    public AltairDisk? Eject()
    {
        AltairDisk? disk = _disk;
        _controller.Removed(this);
        _disk = null;
        _label = "";
        _format = "";
        if (disk is not null) { MountGeneration = MountGenerations.Next(); }
        return disk;
    }

    /// <summary>
    ///  Sets the disk's write protection.
    /// </summary>
    /// <param name="writeProtected">Whether the drive may not write it.</param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    public void SetWriteProtected(bool writeProtected) =>
        (_disk ?? throw new InvalidOperationException($"{Info.Name} is empty.")).IsWriteProtected = writeProtected;

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (_disk is null) { throw new InvalidOperationException($"{Info.Name} is empty."); }
        _label = label;
        _format = format;
        if (whole) { _disk.MarkSaved(); } else { _disk.MarkChanged(); }
    }

    private void Load(AltairDisk disk, string label, string format)
    {
        Eject();
        _disk = disk;
        _label = label;
        _format = format;
        MountGeneration = MountGenerations.Next();
    }
}
