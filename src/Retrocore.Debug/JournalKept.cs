// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A disk's version as the recovery journal's last commit holds it, which its drive's row says.
/// </summary>
/// <param name="Version">The disk's version the journal holds.</param>
/// <param name="When">When the commit that holds it was written, in UTC.</param>
/// <param name="MidWrite">
///  Whether its drive was writing as the snapshot was taken, so the snapshot may hold half of what it wrote.
/// </param>
internal sealed record JournalKept(long Version, DateTime When, bool MidWrite);
