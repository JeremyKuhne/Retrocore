// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines;

/// <summary>
///  The characters a machine's text screen shows for its bytes, so a debugger can show memory as the machine would.
/// </summary>
/// <remarks>
///  <para>
///   Each code's character is drawn from the machine's own character generator, as the screen shows it under the
///   current modes, such as the IIe's alternate character set or the Model III's inverse video.
///  </para>
/// </remarks>
public interface ICharacterSet
{
    /// <summary>
    ///  Gets the width of a character in pixels, at most eight.
    /// </summary>
    int CharacterWidth { get; }

    /// <summary>
    ///  Gets the height of a character in scanlines.
    /// </summary>
    int CharacterHeight { get; }

    /// <summary>
    ///  Gets whether a pixel of a code's character is lit.
    /// </summary>
    /// <param name="code">The byte in video memory.</param>
    /// <param name="line">The scanline within the character.</param>
    /// <param name="pixel">The pixel, from the left.</param>
    /// <param name="flashed">
    ///  Whether to draw the other phase of a flashing character, such as the Apple II's flashing text shown normal.
    /// </param>
    /// <returns>Whether the pixel is lit.</returns>
    bool IsLit(byte code, int line, int pixel, bool flashed);

    /// <summary>
    ///  Gets the character a code shows, for copying, finding and typing.
    /// </summary>
    /// <param name="code">The byte in video memory.</param>
    /// <returns>The character, or <c>'\0'</c> for graphics and other codes with no character.</returns>
    char Character(byte code);
}
