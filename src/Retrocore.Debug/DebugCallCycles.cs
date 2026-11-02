// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Records the cycles of each calling source line's latest call (a 6502 <c>JSR</c>, a Z80 <c>CALL</c> or
///  <c>RST</c>), from the call through the return to the instruction after it.
/// </summary>
internal sealed class DebugCallCycles
{
    private const int MaximumPending = 256;

    private readonly List<((string Path, int Line) Line, ushort Return, int Stack, ulong Start)> _pending = [];
    private readonly Dictionary<(string Path, int Line), ulong> _last = [];

    /// <summary>
    ///  Gets each calling line's latest completed call's cycles.
    /// </summary>
    internal IReadOnlyDictionary<(string Path, int Line), ulong> Last => _last;

    /// <summary>
    ///  Forgets the recorded calls and any in progress.
    /// </summary>
    internal void Clear()
    {
        _pending.Clear();
        _last.Clear();
    }

    /// <summary>
    ///  Observes an instruction boundary, before the instruction at <paramref name="pc"/> runs.
    /// </summary>
    /// <param name="pc">The next instruction's address.</param>
    /// <param name="callLength">The next instruction's length when it is a call, or null.</param>
    /// <param name="stack">The stack pointer.</param>
    /// <param name="cycles">The cycles run so far.</param>
    /// <param name="line">The next instruction's source line, if any.</param>
    internal void Observe(ushort pc, int? callLength, int stack, ulong cycles, (string Path, int Line)? line)
    {
        // A call returns when the stack is back where the call found it and the PC is just after the call. A stack
        // popped past a call (a stack reset, or an exit that discards return addresses) abandons it uncounted.
        while (_pending.Count != 0)
        {
            ((string Path, int Line) caller, ushort returnAddress, int callStack, ulong start) = _pending[^1];
            if (stack < callStack) { break; }

            _pending.RemoveAt(_pending.Count - 1);
            if (stack == callStack && pc == returnAddress)
            {
                _last[caller] = cycles - start;
                break;
            }
        }

        if (callLength is { } length && line is { } source)
        {
            if (_pending.Count == MaximumPending) { _pending.RemoveAt(0); }
            _pending.Add((source, (ushort)(pc + length), stack, cycles));
        }
    }
}
