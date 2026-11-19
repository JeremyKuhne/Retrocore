// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Whose drive a disk image goes in, which says which formats it reads.
/// </summary>
internal enum FloppyFamily
{
    /// <summary>
    ///  A TRS-80's: JV1, JV3, DMK and IMD.
    /// </summary>
    Trs80,

    /// <summary>
    ///  A Color Computer's: JVC and DMK.
    /// </summary>
    Coco,

    /// <summary>
    ///  A Kaypro's: raw images, IMD and DMK.
    /// </summary>
    Kaypro
}
