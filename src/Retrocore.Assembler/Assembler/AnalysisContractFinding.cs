// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A place where a routine's code does not do what its <c>Keeps:</c> or <c>Uses:</c> says.
/// </summary>
/// <param name="Routine">The routine's name.</param>
/// <param name="Address">The routine's address.</param>
/// <param name="Item">The register or flag, as the documentation names it.</param>
/// <param name="Kind">What is wrong.</param>
/// <param name="ChangedAt">
///  An instruction that changes the item on a path to a return, or null when the paths disagree.
/// </param>
/// <param name="Path">The documentation's file.</param>
/// <param name="Line">The documentation's line.</param>
internal sealed record AnalysisContractFinding(
    string Routine,
    ushort Address,
    string Item,
    AnalysisContractProblem Kind,
    ushort? ChangedAt,
    string Path,
    int Line)
{
    /// <inheritdoc/>
    public override string ToString()
    {
        string where = ChangedAt is { } at ? $" by the instruction at ${at:X4}" : " on some path";
        return Kind == AnalysisContractProblem.NotKept
            ? $"{Routine} (${Address:X4}) documents Keeps: {Item}, but {Item} is changed{where}."
            : $"{Routine} (${Address:X4}) changes {Item}{where}, which its Uses:, Out: and Keeps: do not list.";
    }
}
