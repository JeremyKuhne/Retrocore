// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  What the static check of a program's <c>Keeps:</c> and <c>Uses:</c> contracts found.
/// </summary>
/// <param name="Findings">Where the code surely does not do what the documentation says.</param>
/// <param name="Checked">The routines whose returns the analysis reached and checked.</param>
/// <param name="Unverified">
///  The <c>Keeps:</c> items whose value at a return is unknown, as after a call the analysis could not follow.
/// </param>
/// <param name="Skipped">The routines whose returns the analysis did not reach, each with why.</param>
/// <param name="Conditions">
///  The ways the conditional branches, calls and returns the analysis reached went, over every routine it followed
///  through them, by address: bit 0 for not taken, bit 1 for taken.
/// </param>
internal sealed record AnalysisContractReport(
    IReadOnlyList<AnalysisContractFinding> Findings,
    int Checked,
    int Unverified,
    IReadOnlyList<string> Skipped,
    IReadOnlyDictionary<ushort, int> Conditions)
{
    /// <summary>
    ///  Gets the conditions that go one way in every routine the analysis followed through them, by address: true
    ///  for always taken, false for never.
    /// </summary>
    internal IReadOnlyDictionary<ushort, bool> FixedConditions => Conditions
        .Where(pair => pair.Value != 3)
        .ToDictionary(pair => pair.Key, pair => pair.Value == 2);
}
