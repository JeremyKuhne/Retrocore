// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  The kinds of 3.5-inch disk an Apple II 3.5 controller reads.
/// </summary>
public enum Disk35Format
{
    /// <summary>
    ///  A single-sided Apple disk: 400K, 800 blocks, in GCR.
    /// </summary>
    Gcr400,

    /// <summary>
    ///  A double-sided Apple disk: 800K, 1600 blocks, in GCR.
    /// </summary>
    Gcr800,

    /// <summary>
    ///  A double-density MFM disk: 720K, 1440 blocks, as a PC formats it.
    /// </summary>
    Mfm720,

    /// <summary>
    ///  A high-density MFM disk: 1440K, 2880 blocks, which only a SuperDrive reads.
    /// </summary>
    Mfm1440
}
