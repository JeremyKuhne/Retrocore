// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Controls when an address operand's zero-page or absolute width is chosen.
/// </summary>
public enum AssemblyWidthPolicy : byte
{
    /// <summary>
    ///  Allows forward references to shrink during layout convergence.
    /// </summary>
    Shrink,

    /// <summary>
    ///  Keeps the width chosen from values known at the statement's first layout.
    /// </summary>
    SourceOrder
}
