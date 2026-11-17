// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A medium a machine can change, such as a floppy disk: it counts its changes, holds its lock, and gives an
///  immutable copy of itself to save.
/// </summary>
/// <remarks>
///  <para>
///   A host saves a medium from its <see cref="Snapshot"/>, through an <see cref="IImageCodec"/> for the image's
///   format, so the machines know no formats and nothing saves from a medium the machine is still writing.
///  </para>
/// </remarks>
public interface IMedium
{
    /// <summary>
    ///  Gets the medium's version, which changes on every write and on every change of its lock.
    /// </summary>
    long Version { get; }

    /// <summary>
    ///  Gets or sets whether the machine can write the medium, as a disk's write-protect tab says. Changing it
    ///  changes <see cref="Version"/>, as the lock is part of the medium and saved with it.
    /// </summary>
    bool IsWriteProtected { get; set; }

    /// <summary>
    ///  Takes an immutable copy of the medium as it is now, which nothing the machine writes afterward changes.
    /// </summary>
    /// <returns>The snapshot.</returns>
    MediumSnapshot Snapshot();

    /// <summary>
    ///  Gets whether the medium has changes not saved to the image it comes from.
    /// </summary>
    bool IsDirty { get; }

    /// <summary>
    ///  Records that the medium was saved whole to an image, so it has no unsaved changes.
    /// </summary>
    void MarkSaved();

    /// <summary>
    ///  Marks the medium changed though nothing was written, as after a save to an image that could not hold all of it.
    /// </summary>
    void MarkChanged();
}
