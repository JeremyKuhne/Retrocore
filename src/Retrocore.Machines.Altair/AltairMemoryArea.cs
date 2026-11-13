// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  What backs an Altair address.
/// </summary>
public enum AltairMemoryArea
{
    /// <summary>
    ///  Nothing: the S-100 bus floats, and reads return $FF.
    /// </summary>
    None,

    /// <summary>
    ///  RAM.
    /// </summary>
    Ram
}
