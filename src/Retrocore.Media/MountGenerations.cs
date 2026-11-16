// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Gives out mount generations for <see cref="IMediumSlot"/>: each one once in the process, by any drive, so a drive
///  built again, as a card put back in, never repeats one an answer still names.
/// </summary>
public static class MountGenerations
{
    private static int s_last;

    /// <summary>
    ///  Gets a mount generation no mount in the process has had.
    /// </summary>
    /// <returns>The generation.</returns>
    public static int Next() => Interlocked.Increment(ref s_last);
}
