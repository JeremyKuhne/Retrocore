// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  One of the 3.5 controller's two drives: an Apple SuperDrive, which takes 400K and 800K Apple disks and 720K and
///  1440K MFM disks.
/// </summary>
public sealed class Apple2Disk35Drive : IDiskDrive
{
    // A block shows as read or written for a thirtieth of a second, so a view can see it.
    private const ulong ActivityCycles = 1_020_484 / 30;

    private readonly Apple2Disk35Card _card;
    private string _label = "";
    private string _format = "";
    private uint? _lastBlock;
    private bool _lastWrite;
    private ulong _lastCycle;
    private bool _switched;

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="card">The controller.</param>
    /// <param name="drive">One or two.</param>
    internal Apple2Disk35Drive(Apple2Disk35Card card, int drive)
    {
        _card = card;
        Drive = drive;
        Id = $"disk35d{drive}";
        Info = new()
        {
            Name = $"3.5 drive {drive}",
            Description = "Apple SuperDrive: 400K and 800K Apple disks, 720K and 1440K MFM disks",
            Controller = "Apple II 3.5 Disk Controller Card",
            Formats = [.. Disk35Disk.Extensions],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect,
            Tracks = 80,
            Sides = 2
        };
    }

    /// <summary>
    ///  Gets the drive's number, one or two, which is its SmartPort unit.
    /// </summary>
    public int Drive { get; }

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.FloppyDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the disk in the drive, or null when it is empty.
    /// </summary>
    public Disk35Disk? Disk { get; private set; }

    /// <summary>
    ///  Gets whether a program ejected the disk, which the host may want to know to save it.
    /// </summary>
    public bool EjectedByProgram { get; private set; }

    /// <summary>
    ///  Gets or sets whether the machine has changed the disk since it was inserted.
    /// </summary>
    internal bool Changed { get; set; }

    /// <inheritdoc/>
    public MediaState? Media => Disk is { } disk ? new(_label, _format, disk.IsReadOnly, Changed) : null;

    /// <inheritdoc/>
    public DeviceActivity Activity
    {
        get
        {
            if (_lastBlock is null || Disk is null || _card.CycleCount - _lastCycle > ActivityCycles)
            {
                return DeviceActivity.Idle;
            }

            return _lastWrite ? DeviceActivity.Writing : DeviceActivity.Reading;
        }
    }

    /// <inheritdoc/>
    /// <remarks>The head is where the last block was; the motor turns while the drive is active.</remarks>
    public DiskHead Head
    {
        get
        {
            bool active = Activity != DeviceActivity.Idle;
            if (_lastBlock is not { } block || Disk is not { } disk || block >= disk.BlockCount)
            {
                return new(active, active, Track: 0, Side: 0, Sector: null);
            }

            (int track, int side, int sector) = disk.Locate(block);
            return new(active, active, track, side, sector);
        }
    }

    /// <summary>
    ///  Inserts a disk.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="label">What the host calls it, such as its image's path.</param>
    /// <param name="format">Its image format, such as <c>PO</c>.</param>
    public void Insert(Disk35Disk disk, string label, string format)
    {
        ArgumentNullException.ThrowIfNull(disk);
        Disk = disk;
        _label = label;
        _format = format;
        _lastBlock = null;
        Changed = false;
        EjectedByProgram = false;
        _switched = true;
    }

    /// <summary>
    ///  Ejects the disk, leaving any unsaved changes to the caller.
    /// </summary>
    /// <returns>The disk, or null when the drive was empty.</returns>
    public Disk35Disk? Eject()
    {
        Disk35Disk? disk = Disk;
        Disk = null;
        _label = "";
        _format = "";
        _lastBlock = null;
        return disk;
    }

    /// <summary>
    ///  Sets whether the disk in the drive is write-protected.
    /// </summary>
    /// <param name="writeProtected">Whether it is.</param>
    public void SetWriteProtected(bool writeProtected)
    {
        if (Disk is { } disk) { disk.IsReadOnly = writeProtected; }
    }

    /// <summary>
    ///  Ejects the disk as a program's CONTROL eject does, pushing it out of the drive.
    /// </summary>
    internal void EjectByProgram()
    {
        if (Disk is null) { return; }
        Eject();
        EjectedByProgram = true;
    }

    /// <summary>
    ///  Resets the drive: the head forgets the last block.
    /// </summary>
    internal void Reset() => _lastBlock = null;

    /// <summary>
    ///  Notes a block the card read or wrote, for <see cref="Activity"/> and <see cref="Head"/>.
    /// </summary>
    /// <param name="block">The block.</param>
    /// <param name="write">Whether the card wrote it.</param>
    internal void Touch(uint block, bool write)
    {
        _lastBlock = block;
        _lastWrite = write;
        _lastCycle = _card.CycleCount;
    }

    /// <summary>
    ///  Answers a STATUS call as Apple's card does: 0 the general status, 3 the device information block, and 5 the
    ///  last call's details (8 bytes, here all zero). The device control block (1), newline (2) and the others are
    ///  not answered.
    /// </summary>
    /// <param name="code">The status code.</param>
    /// <param name="extended">
    ///  Whether the call is an extended one, whose block count is a byte longer and whose status reports a changed disk.
    /// </param>
    /// <param name="answer">Where to put the answer, at least 26 bytes.</param>
    /// <returns>The answer's length, or -1 for a code the drive does not answer.</returns>
    internal int Status(int code, bool extended, Span<byte> answer)
    {
        switch (code)
        {
            case 0:
                return GeneralStatus(extended, answer);
            case 3:
                return DeviceInformation(extended, answer);
            case 5:
                answer[..8].Clear();
                return 8;
            default:
                return -1;
        }
    }

    /// <summary>
    ///  Gets and clears whether the disk has changed since a call last asked.
    /// </summary>
    /// <returns>Whether it had.</returns>
    internal bool TakeSwitched()
    {
        bool switched = _switched;
        _switched = false;
        return switched;
    }

    /// <summary>
    ///  Writes status code 0: the status byte, then the block count, two bytes or three for an extended call, and a
    ///  zero byte. The status byte is a block device that reads, writes and formats ($E8), online with a disk ($10),
    ///  write-protected as the disk is ($04), and, for an extended call, with a changed disk ($01).
    /// </summary>
    /// <param name="extended">Whether the call is an extended one.</param>
    /// <param name="answer">Where to put it.</param>
    /// <returns>Its length, 4 or 5.</returns>
    private int GeneralStatus(bool extended, Span<byte> answer)
    {
        int status = 0xE8;
        if (Disk is { } disk)
        {
            status |= 0x10 | (disk.IsReadOnly ? 0x04 : 0) | (extended && _switched ? 0x01 : 0);
        }

        uint blocks = Disk?.BlockCount ?? 0;
        int length = 0;
        answer[length++] = (byte)status;
        answer[length++] = (byte)blocks;
        answer[length++] = (byte)(blocks >> 8);
        if (extended) { answer[length++] = (byte)(blocks >> 16); }
        answer[length++] = 0;
        return length;
    }

    /// <summary>
    ///  Writes status code 3: the general status, then the device information block as Apple's card gives a
    ///  SuperDrive's: the name's length, 8, and "DISK 3.5HD" padded to 16 with spaces, so the name a program shows is
    ///  "DISK 3.5"; then the type $01 (a 3.5-inch disk), the subtype $C1 and the version $1010.
    /// </summary>
    /// <param name="extended">Whether the call is an extended one.</param>
    /// <param name="answer">Where to put it.</param>
    /// <returns>Its length, 25 or 26.</returns>
    private int DeviceInformation(bool extended, Span<byte> answer)
    {
        int length = GeneralStatus(extended, answer);
        answer[length++] = 8;
        answer.Slice(length, 16).Fill((byte)' ');
        "DISK 3.5HD"u8.CopyTo(answer[length..]);
        length += 16;
        answer[length++] = 0x01;
        answer[length++] = 0xC1;
        answer[length++] = 0x10;
        answer[length++] = 0x10;
        return length;
    }
}
