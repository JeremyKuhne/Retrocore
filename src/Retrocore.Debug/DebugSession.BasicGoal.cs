// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A step or pause on the BASIC thread, which the run checks at each statement.
    /// </summary>
    /// <param name="Step">What it runs to.</param>
    /// <param name="Depth">The GOSUBs in progress when it started.</param>
    /// <param name="CallsMachine">Whether the statement calls machine code, so Step Into stops in it.</param>
    /// <param name="Deadline">The cycle a pause stops at if no statement starts first.</param>
    private sealed record BasicGoal(BasicStep Step, int Depth, bool CallsMachine, ulong Deadline);
}
