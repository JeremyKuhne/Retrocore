// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The regions of the Model II family's address space.
/// </summary>
public enum Trs80Model2MemoryArea
{
    /// <summary>
    ///  The 2K boot ROM at <c>$0000</c>-<c>$07FF</c>, until port <c>$F9</c> switches it out.
    /// </summary>
    Rom,

    /// <summary>
    ///  Addresses nothing answers: the upper 32K with no bank selected, or a bank beyond the RAM fitted.
    /// </summary>
    Unmapped,

    /// <summary>
    ///  The 2K of video RAM at <c>$F800</c>-<c>$FFFF</c>, while port <c>$FF</c> bit 7 maps it.
    /// </summary>
    Video,

    /// <summary>
    ///  RAM: the first 32K at <c>$0000</c>, and at <c>$8000</c> the 32K bank port <c>$FF</c> selects.
    /// </summary>
    Ram
}
