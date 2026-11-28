// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A recorder recording onto a <see cref="CassetteImage"/> that holds the bits it hears until its motor stops, as the
///  TRS-80's does, to find where bytes start once it has the whole recording.
/// </summary>
public interface ICassetteRecorder
{
    /// <summary>
    ///  Gets the bytes the bits held so far make, as stopping the recorder now would append them, without stopping it
    ///  or changing what it holds.
    /// </summary>
    /// <returns>The bytes, a copy.</returns>
    IReadOnlyList<byte> Buffered();
}
