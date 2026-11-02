// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  One breakpoint VS Code set, of any kind: what stops it and how often it has been hit.
    /// </summary>
    /// <param name="id">The DAP breakpoint id.</param>
    /// <param name="group">The request that set it, such as a source file's breakpoints.</param>
    private sealed class BreakpointState(int id, string group)
    {
        /// <summary>
        ///  Gets the DAP breakpoint id, which stays while VS Code keeps setting the breakpoint.
        /// </summary>
        internal int Id { get; } = id;

        /// <summary>
        ///  Gets the request that set the breakpoint, whose next list replaces it.
        /// </summary>
        internal string Group { get; } = group;

        /// <summary>
        ///  Gets or sets the DAP stop reason: breakpoint, function breakpoint, instruction breakpoint or data breakpoint.
        /// </summary>
        internal string Kind { get; set; } = "breakpoint";

        /// <summary>
        ///  Gets or sets where the breakpoint is, as the user would name it.
        /// </summary>
        internal string Location { get; set; } = "";

        /// <summary>
        ///  Gets or sets the source line a log message reports, if any.
        /// </summary>
        internal SourceLine? Line { get; set; }

        /// <summary>
        ///  Gets or sets the address a function or instruction breakpoint stops at, once it is bound.
        /// </summary>
        internal int? Address { get; set; }

        /// <summary>
        ///  Gets or sets the expression that must be nonzero for the breakpoint to count a hit.
        /// </summary>
        internal string? Condition { get; set; }

        /// <summary>
        ///  Gets or sets the hit count condition as VS Code gave it.
        /// </summary>
        internal string? HitText { get; set; }

        /// <summary>
        ///  Gets or sets the parsed hit count condition.
        /// </summary>
        internal HitCondition? HitTest { get; set; }

        /// <summary>
        ///  Gets or sets the message a logpoint writes instead of stopping.
        /// </summary>
        internal string? LogMessage { get; set; }

        /// <summary>
        ///  Gets or sets the hits: the times the PC or an access reached the breakpoint with its condition true.
        /// </summary>
        internal int Hits { get; set; }

        /// <summary>
        ///  Gets or sets the hits last reported to VS Code.
        /// </summary>
        internal int Reported { get; set; }

        /// <summary>
        ///  Gets or sets why the breakpoint cannot stop, or null when it is verified.
        /// </summary>
        internal string? Problem { get; set; }

        /// <summary>
        ///  Gets or sets the DAP breakpoint fields other than its message.
        /// </summary>
        internal JsonObject Response { get; set; } = [];
    }
}
