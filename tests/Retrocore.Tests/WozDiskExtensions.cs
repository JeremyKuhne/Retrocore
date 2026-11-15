// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Helpers for the tests' Disk II disks.
/// </summary>
internal static class WozDiskExtensions
{
    /// <summary>
    ///  Copies a disk with its lock off, as a disk the machine can write: a disk read from a sector image comes in
    ///  locked, as the Disk II's do, and its exported image keeps the lock.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>A writable copy.</returns>
    internal static WozDisk Writable(this WozDisk disk)
    {
        WozDisk copy = WozDisk.Load(disk.Export(), writable: true);
        copy.IsWriteProtected = false;
        return copy;
    }
}
