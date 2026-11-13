// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  The kind of a file on an Apple Pascal volume, from its directory entry.
/// </summary>
public enum PascalFileKind
{
    /// <summary>
    ///  No kind: the volume header.
    /// </summary>
    None = 0,

    /// <summary>
    ///  Bad blocks, kept out of use.
    /// </summary>
    BadBlocks = 1,

    /// <summary>
    ///  A code file (<c>.CODE</c>).
    /// </summary>
    Code = 2,

    /// <summary>
    ///  A text file (<c>.TEXT</c>): a header page, then pages of lines.
    /// </summary>
    Text = 3,

    /// <summary>
    ///  An information file.
    /// </summary>
    Info = 4,

    /// <summary>
    ///  A data file.
    /// </summary>
    Data = 5,

    /// <summary>
    ///  A graphics file.
    /// </summary>
    Graphics = 6,

    /// <summary>
    ///  A photo file.
    /// </summary>
    Photo = 7,

    /// <summary>
    ///  A secure directory.
    /// </summary>
    SecureDirectory = 8
}
