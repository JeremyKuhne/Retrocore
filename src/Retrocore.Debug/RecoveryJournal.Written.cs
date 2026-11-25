// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class RecoveryJournal
{
    /// <summary>
    ///  The snapshot a disk's journaled version is in.
    /// </summary>
    /// <param name="Version">The disk's version it holds.</param>
    /// <param name="File">The snapshot's file name, in the journal's media folder.</param>
    /// <param name="Kind">The snapshot's kind, such as <c>woz2</c>.</param>
    /// <param name="WriteProtected">Whether the disk was locked.</param>
    /// <param name="MidWrite">
    ///  Whether its drive was writing as the snapshot was taken, so the snapshot may hold half of what it wrote.
    /// </param>
    private sealed record Written(long Version, string File, string Kind, bool WriteProtected, bool MidWrite = false);
}
