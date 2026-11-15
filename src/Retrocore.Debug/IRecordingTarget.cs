// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A debug target that records onto media, such as a cassette, kept in memory until it comes out.
/// </summary>
internal interface IRecordingTarget
{
    /// <summary>
    ///  Saves each recording to its path, leaving it in. A save that fails can be tried again, since nothing comes out.
    /// </summary>
    /// <exception cref="IOException">A recording could not be written.</exception>
    /// <exception cref="UnauthorizedAccessException">A recording's path cannot be written.</exception>
    void SaveRecordings();
}
