// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Atari;

namespace Retrocore.Machines.Atari;

/// <summary>
///  A disk drive on the serial bus, <c>D1:</c> to <c>D4:</c>: the slot the host puts disks in, whichever way the drive
///  is emulated.
/// </summary>
/// <remarks>
///  <para>
///   <see cref="Atari810"/> is the 810 at the hardware level, the default; <see cref="AtariSioDiskDrive"/> answers
///   the same commands from the image at the command level, and reads double-density disks too.
///  </para>
/// </remarks>
public abstract class AtariDiskDrive : IDiskDrive, IMediumSlot
{
    private AtariDisk? _disk;

    /// <summary>
    ///  Constructs a drive.
    /// </summary>
    /// <param name="number">The drive number, 1-4: <c>D1:</c> to <c>D4:</c>.</param>
    /// <param name="controller">How the drive is emulated, for its description.</param>
    private protected AtariDiskDrive(int number, string controller)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(number, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(number, 4);
        Number = number;
        Info = new()
        {
            Name = $"D{number}:",
            Description = "5¼-inch single-sided floppy drive",
            Controller = controller,
            Formats = ["atr", "xfd"],
            SaveFormats = ["atr", "xfd"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect | MediaOperations.Save,
            Tracks = 40,
            Sides = 1
        };
    }

    /// <summary>
    ///  Gets the drive number, 1-4.
    /// </summary>
    public int Number { get; }

    /// <summary>
    ///  Gets the disk in the drive, or null.
    /// </summary>
    public AtariDisk? Disk => _disk;

    /// <summary>
    ///  Gets or sets what the host calls the disk's image, such as its path.
    /// </summary>
    public string Label { get; set; } = "";

    /// <summary>
    ///  Gets or sets the image's format, <c>ATR</c> or <c>XFD</c>.
    /// </summary>
    public string Format { get; set; } = "ATR";

    /// <inheritdoc/>
    public string Id => $"d{Number}";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.FloppyDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <inheritdoc/>
    public MediaState? Media => _disk is { } disk ? new(Label, Format, disk.IsWriteProtected, disk.IsDirty) : null;

    /// <inheritdoc/>
    public IMedium? Medium => _disk;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <inheritdoc/>
    public abstract DeviceActivity Activity { get; }

    /// <inheritdoc/>
    public abstract DiskHead Head { get; }

    /// <summary>
    ///  Puts a disk in the drive.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">What the host calls its image.</param>
    /// <param name="format">The image's format, <c>ATR</c> or <c>XFD</c>.</param>
    public void Insert(AtariDisk disk, string label = "", string format = "ATR")
    {
        ArgumentNullException.ThrowIfNull(disk);
        _disk = disk;
        Label = label;
        Format = format;
        MountGeneration = MountGenerations.Next();
        Changed();
    }

    /// <summary>
    ///  Takes the disk out.
    /// </summary>
    public void Eject()
    {
        _disk = null;
        MountGeneration = MountGenerations.Next();
        Changed();
    }

    /// <inheritdoc/>
    public void Mount(IMedium medium, string label, string format) =>
        Insert(medium as AtariDisk ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label, format);

    /// <inheritdoc/>
    public IMedium? Unmount()
    {
        AtariDisk? disk = _disk;
        Eject();
        return disk;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole = true)
    {
        AtariDisk disk = _disk ?? throw new InvalidOperationException($"{Info.Name} is empty.");
        if (whole)
        {
            disk.MarkSaved();
        }
        else
        {
            disk.MarkChanged();
        }

        Label = label;
        Format = format;
    }

    /// <summary>
    ///  Called after a disk goes in or comes out.
    /// </summary>
    private protected virtual void Changed()
    {
    }
}
