// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A drive that holds a medium: what is in it, and a mount generation that changes each time a medium goes in or
///  comes out.
/// </summary>
/// <remarks>
///  <para>
///   A host checks the generation before it marks a save done, so a save that finishes after its disk came out, or
///   after another went in, marks nothing.
///  </para>
/// </remarks>
public interface IMediumSlot
{
    /// <summary>
    ///  Gets the medium in the drive, or null when it is empty.
    /// </summary>
    IMedium? Medium { get; }

    /// <summary>
    ///  Gets the mount generation, which changes each time a medium goes in or comes out and is never reused in the
    ///  process, even by a drive built again, so with the drive's id it names one mount.
    /// </summary>
    int MountGeneration { get; }
}
