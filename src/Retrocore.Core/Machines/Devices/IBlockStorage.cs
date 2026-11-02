// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  Storage addressed by block number.
/// </summary>
public interface IBlockStorage : IDevice
{
    /// <summary>
    ///  Gets the blocks the media holds, or 0 when there is none.
    /// </summary>
    long BlockCount { get; }

    /// <summary>
    ///  Gets the block the machine last read or wrote, or null before the first.
    /// </summary>
    long? LastBlock { get; }
}
