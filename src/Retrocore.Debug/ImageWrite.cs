// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  What writing an image came to.
/// </summary>
/// <param name="Outcome"><c>written</c>, <c>conflict</c> or <c>readOnly</c>.</param>
/// <param name="Revision">
///  The file's revision: after the write when written, and as it was found for a conflict (null when it is gone).
/// </param>
/// <param name="Reason">
///  For <c>readOnly</c>: <c>file</c> for a read-only file, <c>access</c> where it cannot be written.
/// </param>
/// <param name="Backup">Where the revision it replaced was kept, or null when it replaced none.</param>
internal sealed record ImageWrite(string Outcome, FileRevision? Revision, string? Reason = null, string? Backup = null);
