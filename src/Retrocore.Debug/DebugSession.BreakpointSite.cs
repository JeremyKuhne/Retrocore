// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A breakpoint's stop at one address: in the module whose code is there, or wherever the PC reaches it.
    /// </summary>
    /// <param name="Module">
    ///  The module with code on the line at this address, or null for an address breakpoint.
    /// </param>
    /// <param name="Line">The breakpoint's source line, or null for an address breakpoint.</param>
    /// <param name="Breakpoint">The breakpoint.</param>
    /// <param name="Bank">
    ///  The memory bank an address breakpoint stops in, only while the CPU runs code from it; null for any code at
    ///  the address.
    /// </param>
    private sealed record BreakpointSite(
        IDebugModule? Module,
        SourceLine? Line,
        BreakpointState Breakpoint,
        DebugMemoryBank? Bank = null);
}
