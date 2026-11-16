// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The ProDOS block device in slot 7, given when the machine is made.
/// </summary>
/// <remarks>
///  <para>
///   Its image stays in it while the machine runs. Its lock refuses writes at once, as ProDOS's write-protected
///   error ($2B); the slot's ROM also says whether the device writes, which ProDOS reads as it starts, so that part
///   of a lock changed while it runs shows from the next reset.
///  </para>
/// </remarks>
public sealed class Apple2BlockStorage : IBlockStorage, IMediumSlot
{
    // A block command shows as reading or writing for a thirtieth of a second, so a view can see it.
    private const ulong ActivityCycles = 1_020_484 / 30;

    private readonly Apple2Bus _bus;

    /// <summary>
    ///  Creates the device.
    /// </summary>
    /// <param name="bus">The bus, whose slot 7 holds the device.</param>
    internal Apple2BlockStorage(Apple2Bus bus)
    {
        _bus = bus;
        bool saves = bus.BlockDevice is MemoryBlockDevice;
        Info = new()
        {
            Name = "Slot 7 disk",
            Description = "ProDOS block device",
            Controller = "Retrocore's slot 7 ProDOS driver",
            Formats = ["po"],
            SaveFormats = saves ? ["po", "hdv", "2mg"] : [],
            Operations = saves ? MediaOperations.WriteProtect | MediaOperations.Save : MediaOperations.None
        };
    }

    /// <summary>
    ///  Gets or sets what the host calls the device's image, such as its path.
    /// </summary>
    public string Label { get; set; } = "";

    /// <summary>
    ///  Gets or sets the image's format, such as <c>PO</c>.
    /// </summary>
    public string Format { get; set; } = "PO";

    /// <inheritdoc/>
    public string Id => "slot7";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.BlockStorage;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <inheritdoc/>
    public MediaState? Media => _bus.BlockDevice is { } device
        ? new(Label, Format, device.IsReadOnly, device is MemoryBlockDevice memory ? memory.IsDirty : _bus.BlockWritten)
        : null;

    /// <inheritdoc/>
    public IMedium? Medium => _bus.BlockDevice as IMedium;

    /// <inheritdoc/>
    /// <remarks>The image never leaves the slot, so its one mount has one generation.</remarks>
    public int MountGeneration { get; } = MountGenerations.Next();

    /// <summary>
    ///  Gets whether the slot's ROM says the device writes, as it did when the machine last started or reset; it
    ///  differs from the lock after the lock changes, until the next reset.
    /// </summary>
    public bool WritesAnnounced => _bus.BlockWritesAnnounced;

    /// <inheritdoc/>
    public DeviceActivity Activity
    {
        get
        {
            (uint? block, bool write, ulong cycle) = _bus.LastBlockAccess;
            if (block is null || _bus.CycleCount - cycle > ActivityCycles) { return DeviceActivity.Idle; }
            return write ? DeviceActivity.Writing : DeviceActivity.Reading;
        }
    }

    /// <inheritdoc/>
    public long BlockCount => _bus.BlockDevice?.BlockCount ?? 0;

    /// <inheritdoc/>
    public long? LastBlock => _bus.LastBlockAccess.Block;

    /// <summary>
    ///  Locks or unlocks the image: writes are refused or allowed at once, and the ROM says so from the next reset, or
    ///  at once for a lock set before the machine has run, which is the lock it starts with.
    /// </summary>
    /// <param name="writeProtected">Whether the image is locked.</param>
    /// <param name="powerOn">
    ///  Whether the lock is the one the machine starts with, as a saved machine restores it, so the ROM says so now.
    /// </param>
    /// <exception cref="InvalidOperationException">The image cannot be unlocked.</exception>
    public void SetWriteProtected(bool writeProtected, bool powerOn = false)
    {
        IMedium medium = Medium ?? throw new InvalidOperationException($"{Info.Name}'s image cannot be unlocked.");
        medium.IsWriteProtected = writeProtected;
        if (powerOn || _bus.CycleCount == 0) { _bus.RefreshSlot7Rom(); }
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole = true)
    {
        MemoryBlockDevice image = _bus.BlockDevice as MemoryBlockDevice ?? throw new InvalidOperationException($"{Info.Name} cannot be saved.");
        if (whole)
        {
            image.MarkSaved();
        }
        else
        {
            image.MarkChanged();
        }

        Label = label;
        Format = format;
    }
}
