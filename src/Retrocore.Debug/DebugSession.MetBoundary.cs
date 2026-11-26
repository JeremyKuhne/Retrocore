// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  An instruction boundary an interrupt was taken at, which its handler returns to, and what was met there.
    /// </summary>
    /// <param name="Cpu">The CPU.</param>
    /// <param name="Address">The boundary's address.</param>
    /// <param name="Stack">The stack pointer at the boundary.</param>
    /// <param name="Token">The boundary's token, which what was met there was marked with.</param>
    /// <param name="Breakpoints">The breakpoints met there.</param>
    /// <param name="Trap">Whether the BRK filter's check ran there.</param>
    /// <param name="Basic">Whether BASIC's stops were checked there.</param>
    /// <param name="Pascal">Whether Pascal's stops were checked there.</param>
    /// <param name="BasicGoal">BASIC's step goal then: a new one is checked where the interrupt returns.</param>
    /// <param name="PascalGoal">Pascal's step goal then.</param>
    private sealed record MetBoundary(
        IDebugTarget Cpu,
        ushort Address,
        int Stack,
        long Token,
        BreakpointState[] Breakpoints,
        bool Trap,
        bool Basic,
        bool Pascal,
        BasicGoal? BasicGoal,
        PascalGoal? PascalGoal);
}
