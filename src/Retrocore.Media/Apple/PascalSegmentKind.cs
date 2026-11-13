// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  What a segment of an Apple Pascal code file is, from the segment dictionary.
/// </summary>
public enum PascalSegmentKind
{
    /// <summary>
    ///  Linked code, ready to run.
    /// </summary>
    Linked = 0,

    /// <summary>
    ///  A program's outer segment, with units or external routines still to link.
    /// </summary>
    HostSegment = 1,

    /// <summary>
    ///  A segment procedure (not used in code files).
    /// </summary>
    SegmentProcedure = 2,

    /// <summary>
    ///  A compiled unit, still to link.
    /// </summary>
    Unit = 3,

    /// <summary>
    ///  Separately assembled or compiled routines, still to link.
    /// </summary>
    Separate = 4,

    /// <summary>
    ///  An intrinsic unit, not linked.
    /// </summary>
    UnlinkedIntrinsic = 5,

    /// <summary>
    ///  An intrinsic unit, linked: the system loads it from <c>SYSTEM.LIBRARY</c> for the programs that use it.
    /// </summary>
    LinkedIntrinsic = 6,

    /// <summary>
    ///  An intrinsic unit's data: no code, only the size of its variables.
    /// </summary>
    Data = 7
}
