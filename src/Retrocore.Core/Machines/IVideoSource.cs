// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines;

/// <summary>
///  A machine's display, rendered as RGBA frames.
/// </summary>
public interface IVideoSource
{
    /// <summary>
    ///  Gets the frame width in pixels.
    /// </summary>
    int Width { get; }

    /// <summary>
    ///  Gets the frame height in pixels.
    /// </summary>
    int Height { get; }

    /// <summary>
    ///  Gets the number of CPU cycles in one frame.
    /// </summary>
    int CyclesPerFrame { get; }

    /// <summary>
    ///  Renders a frame into caller-owned storage.
    /// </summary>
    /// <param name="pixels">Exactly <see cref="Width"/> * <see cref="Height"/> * 4 bytes of opaque RGBA.</param>
    /// <param name="scanned">
    ///  Whether to render what the beam captured during the frame, rather than current video memory.
    /// </param>
    void Render(Span<byte> pixels, bool scanned);
}
