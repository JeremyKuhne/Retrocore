// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A drive the machine can eject a medium from by itself, as a program ejects a 3.5-inch disk: it keeps each medium it
///  ejected until the host takes it, so a changed one is not lost.
/// </summary>
public interface IEjectingSlot : IMediumSlot
{
    /// <summary>
    ///  Takes the media the machine ejected since the last call, oldest first.
    /// </summary>
    /// <returns>The media, empty when none were ejected.</returns>
    IReadOnlyList<EjectedMedium> TakeEjected();
}
