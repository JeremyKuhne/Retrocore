// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A debug target that writes what it keeps between sessions to a file of its own when the session ends, as the
///  Model 100 keeps its RAM image. A tape's recording is not one of these: it is a changed tape, saved as a disk is
///  and kept in the recovery journal.
/// </summary>
internal interface IRecordingTarget
{
    /// <summary>
    ///  Writes what the target keeps to its file. A save that fails can be tried again, since nothing is let go.
    /// </summary>
    /// <exception cref="IOException">The file could not be written.</exception>
    /// <exception cref="UnauthorizedAccessException">The file cannot be written.</exception>
    void SaveRecordings();
}
