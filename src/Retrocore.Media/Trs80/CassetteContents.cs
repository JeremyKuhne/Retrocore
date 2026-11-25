// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  What a CAS tape holds, as the bytes after its leader say: which BASIC recorded it, and so which ROM can read it.
/// </summary>
public enum CassetteContents
{
    /// <summary>
    ///  A tape whose first recording is none of the others, such as a 1500 baud Model III one, or a blank tape.
    /// </summary>
    Unknown,

    /// <summary>
    ///  A 250 baud Level I recording: <c>$A5</c>, then its start and end addresses, high bytes first.
    /// </summary>
    Level1,

    /// <summary>
    ///  A 500 baud Level II BASIC program, as <c>CSAVE</c> writes it: <c>$A5</c>, then three <c>$D3</c> header bytes.
    /// </summary>
    Level2Basic,

    /// <summary>
    ///  A 500 baud Level II <c>SYSTEM</c> tape of machine language: <c>$A5</c>, then the <c>$55</c> that begins its name.
    /// </summary>
    Level2System
}
