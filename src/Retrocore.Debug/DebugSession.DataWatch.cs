// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A data breakpoint's watch on memory or I/O ports.
    /// </summary>
    /// <param name="Start">The first address or port.</param>
    /// <param name="Length">The bytes or ports watched.</param>
    /// <param name="Port">Whether it watches I/O ports rather than memory.</param>
    /// <param name="Reads">Whether reads hit it.</param>
    /// <param name="Writes">Whether writes hit it.</param>
    /// <param name="Breakpoint">The breakpoint.</param>
    /// <param name="Bank">
    ///  The memory bank it watches, matching an access only when the memory map sends it there; null for any access
    ///  to the addresses.
    /// </param>
    private sealed record DataWatch(
        int Start,
        int Length,
        bool Port,
        bool Reads,
        bool Writes,
        BreakpointState Breakpoint,
        DebugMemoryBank? Bank = null)
    {
        /// <summary>
        ///  Tests whether a bus cycle accesses what the watch watches. Opcode fetches are not data reads, and a
        ///  port below $100 matches whatever the CPU drives on the address bus's high byte.
        /// </summary>
        /// <param name="cycle">The cycle.</param>
        /// <param name="write">Whether the access is a write.</param>
        /// <returns>Whether it matches.</returns>
        internal bool Matches(in ProcessorCycle cycle, out bool write)
        {
            write = cycle.Operation is BusOperation.Write or BusOperation.IoWrite;
            bool kind = cycle.Operation switch
            {
                BusOperation.Read => !Port && !cycle.IsOpcodeFetch,
                BusOperation.Write => !Port,
                BusOperation.IoRead or BusOperation.IoWrite => Port,
                _ => false
            };

            if (!kind || cycle.IsStalled || !(write ? Writes : Reads)) { return false; }
            int address = Port && Start + Length <= 0x100 ? cycle.Address & 0xFF : cycle.Address;
            return address >= Start && address < Start + Length;
        }
    }
}
