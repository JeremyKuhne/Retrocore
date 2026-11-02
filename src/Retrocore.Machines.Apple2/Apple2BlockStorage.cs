// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The ProDOS block device in slot 7, given when the machine is made.
/// </summary>
public sealed class Apple2BlockStorage : IBlockStorage
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
        Info = new()
        {
            Name = "Slot 7 disk",
            Description = "ProDOS block device",
            Controller = "Retrocore's slot 7 ProDOS driver",
            Formats = ["po"],
            Operations = MediaOperations.None
        };
    }

    /// <summary>
    ///  Gets or sets what the host calls the device's image, such as its path.
    /// </summary>
    public string Label { get; set; } = "";

    /// <inheritdoc/>
    public string Id => "slot7";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.BlockStorage;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <inheritdoc/>
    public MediaState? Media => _bus.BlockDevice is { } device
        ? new(Label, "PO", device.IsReadOnly, _bus.BlockWritten)
        : null;

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
}
