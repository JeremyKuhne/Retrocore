// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    // What is checked at an instruction boundary is met there once. Each boundary a CPU arrives at gets a token, and
    // what is checked there is marked with it: each breakpoint and the BRK, BASIC and Pascal checks, as are those a
    // continue or step passes where it starts. A CPU keeps its token while it idles at the boundary; the instruction
    // there starts the next. An interrupt taken there keeps the boundary and its marks, and returning to it restores
    // them, so what was met is not met again, while what was not, such as a breakpoint set in the handler, still is.
    private long _boundaryTokens;
    private (long Token, ushort Address) _machineBoundary;
    private (long Token, ushort Address) _coprocessorBoundary;
    private long _trapToken;
    private long _basicToken;
    private long _pascalToken;


    // The boundaries interrupts were taken at, innermost last.
    private readonly List<MetBoundary> _metBoundaries = [];

    // Interrupts nest only so deep; a handler that never returns leaves its boundary behind.
    private const int MaximumMetBoundaries = 64;

    // How far above a boundary's stack its return may land: a 6809's CWAI stacks its 12 bytes before it waits, so
    // returning lands that much higher. Farther above, the CPU is on another stack, as a handler's own.
    private const int UnwoundStack = 0x20;

    private ref (long Token, ushort Address) BoundaryOf(IDebugTarget cpu)
    {
        if (IsMachineCpu(cpu)) { return ref _machineBoundary; }
        return ref _coprocessorBoundary;
    }

    // Passes the boundary a continue or step starts at: its breakpoints and BASIC's and Pascal's stops are met there.
    private void PassBoundary(IDebugTarget cpu, ushort address)
    {
        long here = BoundaryToken(cpu, address);
        foreach (BreakpointSite site in _breakpoints.GetValueOrDefault(address) ?? s_noSites)
        {
            site.Breakpoint.MetToken = here;
        }

        foreach ((_, BreakpointState state) in _systemCallBreakpoints) { state.MetToken = here; }
        if (IsMachineCpu(cpu))
        {
            _basicToken = here;
            _pascalToken = here;
        }
    }

    // Forgets every boundary, as a launch or reset does, or running the machine outside Execute, as BASIC's own runs do.
    private void ForgetBoundaries()
    {
        _metBoundaries.Clear();
        _machineBoundary = default;
        _coprocessorBoundary = default;
    }

    // Notes that a CPU has left the boundary it was at.
    private void LeftBoundary(IDebugTarget cpu) => BoundaryOf(cpu).Token = 0;

    /// <summary>
    ///  Gets the token of the boundary a CPU is at: its own while it stays there, the one it had when it comes back
    ///  from an interrupt taken there, with what was met there, or a new one.
    /// </summary>
    /// <param name="cpu">The CPU, between instructions.</param>
    /// <param name="address">Its program counter.</param>
    /// <returns>The token.</returns>
    private long BoundaryToken(IDebugTarget cpu, ushort address)
    {
        ref (long Token, ushort Address) boundary = ref BoundaryOf(cpu);
        if (boundary.Token != 0 && boundary.Address == address) { return boundary.Token; }

        boundary.Address = address;
        int index = _metBoundaries.Count == 0 ? -1 : FindMet(cpu, address);
        if (index < 0)
        {
            boundary.Token = ++_boundaryTokens;
            return boundary.Token;
        }

        MetBoundary met = _metBoundaries[index];
        foreach (BreakpointState state in met.Breakpoints) { state.MetToken = met.Token; }
        if (met.Trap) { _trapToken = met.Token; }
        if (met.Basic) { _basicToken = met.Token; }
        if (met.Pascal) { _pascalToken = met.Token; }

        boundary.Token = met.Token;
        return met.Token;
    }

    /// <summary>
    ///  Notes that a CPU leaves its boundary: for an interrupt, which keeps the boundary and what was met there for
    ///  its return, or for the instruction there, which forgets a boundary an interrupt returned to.
    /// </summary>
    /// <param name="cpu">The CPU.</param>
    /// <param name="address">The boundary's address.</param>
    /// <param name="stack">The stack pointer at the boundary.</param>
    /// <param name="interrupt">Whether it leaves for an interrupt's response.</param>
    /// <param name="met">Whether the boundary is one an interrupt returned to, or null to find out.</param>
    private void LeaveFor(IDebugTarget cpu, ushort address, int stack, bool interrupt, bool? met)
    {
        ref (long Token, ushort Address) boundary = ref BoundaryOf(cpu);
        long token = boundary.Address == address ? boundary.Token : 0;
        boundary.Token = 0;
        int index = met == false || _metBoundaries.Count == 0 ? -1 : FindMet(cpu, address);
        if (index >= 0) { _metBoundaries.RemoveAt(index); }

        // Nothing checked there is nothing to keep.
        if (!interrupt || token == 0) { return; }
        List<BreakpointState> breakpoints = [];
        foreach (BreakpointSite site in _breakpoints.GetValueOrDefault(address) ?? s_noSites)
        {
            BreakpointState state = site.Breakpoint;
            if (state.MetToken == token && !breakpoints.Contains(state)) { breakpoints.Add(state); }
        }

        foreach ((_, BreakpointState state) in _systemCallBreakpoints)
        {
            if (state.MetToken == token && !breakpoints.Contains(state)) { breakpoints.Add(state); }
        }

        if (_metBoundaries.Count == MaximumMetBoundaries) { _metBoundaries.RemoveAt(0); }
        _metBoundaries.Add(new(
            cpu,
            address,
            stack,
            token,
            [.. breakpoints],
            _trapToken == token,
            _basicToken == token,
            _pascalToken == token));
    }

    /// <summary>
    ///  Finds the boundary an interrupt was taken at that a CPU is back at. A boundary the CPU has come back past
    ///  elsewhere is forgotten.
    /// </summary>
    /// <param name="cpu">The CPU, between instructions.</param>
    /// <param name="address">Its program counter.</param>
    /// <returns>The boundary's index, or -1 when the CPU is not back at one: inside a handler, or elsewhere.</returns>
    private int FindMet(IDebugTarget cpu, ushort address)
    {
        int? stack = null;
        for (int index = _metBoundaries.Count - 1; index >= 0; index--)
        {
            MetBoundary met = _metBoundaries[index];
            if (!ReferenceEquals(met.Cpu, cpu)) { continue; }

            // Stacks grow down, wrapping within their width, as a 6502's does within page one. Deeper than the
            // boundary's stack is inside the handler of the interrupt taken there. Far above it, the CPU is on
            // another stack, as a handler's own, or back past this boundary at an outer one: this one is kept.
            stack ??= cpu.Frame.StackPointer;
            int mask = cpu.StackMask;
            int below = (met.Stack - stack.Value) & mask;
            int above = (stack.Value - met.Stack) & mask;
            if (below != 0 && below <= mask >> 1) { return -1; }
            if (above > UnwoundStack) { continue; }
            if (met.Address == address) { return index; }

            // Back at the boundary's stack, or just above it, but elsewhere: the handler returned elsewhere.
            _metBoundaries.RemoveAt(index);
        }

        return -1;
    }
}
