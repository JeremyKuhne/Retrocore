// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A stop at breakpoints.
    /// </summary>
    /// <param name="Reason">The DAP stop reason of the first breakpoint.</param>
    /// <param name="Ids">The breakpoints that stop.</param>
    /// <param name="Hidden">The macro levels to hide so a source breakpoint's line shows, or null.</param>
    /// <param name="Description">Why a condition failed, or what a data breakpoint saw.</param>
    private sealed record BreakpointStop(string Reason, int[] Ids, int? Hidden, string? Description);
}
