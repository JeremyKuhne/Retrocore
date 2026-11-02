// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The classification of a contiguous image range.
/// </summary>
public enum AnalysisRegionKind : byte
{
    /// <summary>
    ///  No code or data classification has been established.
    /// </summary>
    Unexplored,

    /// <summary>
    ///  The range contains decoded instructions.
    /// </summary>
    Code,

    /// <summary>
    ///  The caller has explicitly classified this range as data.
    /// </summary>
    Data
}
