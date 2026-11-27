// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  How a routine's code and its documented contract disagree.
/// </summary>
internal enum AnalysisContractProblem
{
    /// <summary>
    ///  <c>Keeps:</c> lists a register or flag that some path to a return changes.
    /// </summary>
    NotKept,

    /// <summary>
    ///  The routine has a <c>Uses:</c> section, and changes a register that it, <c>Out:</c> and <c>Keeps:</c> do not
    ///  list.
    /// </summary>
    NotListed
}
