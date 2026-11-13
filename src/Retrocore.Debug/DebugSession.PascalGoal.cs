// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A step on the Pascal thread.
    /// </summary>
    /// <param name="Step">How it ends.</param>
    /// <param name="Mark">The MSCW of the procedure it started in; callers' are above it.</param>
    /// <param name="Deadline">When a pause gives up waiting for a p-code.</param>
    private sealed record PascalGoal(PascalStep Step, ushort Mark, ulong Deadline);
}
