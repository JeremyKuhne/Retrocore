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

    /// <summary>
    ///  Records that the medium was saved to an image, which it now comes from.
    /// </summary>
    /// <param name="label">What the host calls the image, such as its path.</param>
    /// <param name="format">Its image format, such as <c>WOZ</c>.</param>
    /// <param name="whole">
    ///  Whether the image holds all of the medium; a lossy save leaves it changed, as reloading the image would not
    ///  give it back.
    /// </param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    void Saved(string label, string format, bool whole);

    /// <summary>
    ///  Puts a medium in the drive, as a host puts back a disk it kept for Undo, in place of the one there.
    /// </summary>
    /// <param name="medium">The medium, of the kind the drive takes.</param>
    /// <param name="label">What the host calls it, such as its image's path.</param>
    /// <param name="format">Its image format, such as <c>WOZ</c>.</param>
    /// <exception cref="ArgumentException">The drive does not take that kind of medium.</exception>
    /// <exception cref="NotSupportedException">The drive's medium cannot be changed.</exception>
    void Mount(IMedium medium, string label, string format);

    /// <summary>
    ///  Takes the medium out of the drive, leaving any unsaved changes to the caller.
    /// </summary>
    /// <returns>The medium, or null when the drive was empty.</returns>
    /// <exception cref="NotSupportedException">The drive's medium cannot be changed.</exception>
    IMedium? Unmount();
}
