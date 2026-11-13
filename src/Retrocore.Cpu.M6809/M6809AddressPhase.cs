// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Effective-address resolution phase before a memory-addressed MC6809 operation executes.
/// </summary>
internal enum M6809AddressPhase : byte
{
    /// <summary>
    ///  Effective address is resolved (or instruction is not memory-addressed).
    /// </summary>
    Ready,

    /// <summary>
    ///  Fetch direct-page low byte from <c>PC++</c>.
    /// </summary>
    DirectFetch,

    /// <summary>
    ///  Fetch extended address high byte from <c>PC++</c>.
    /// </summary>
    ExtendedHigh,

    /// <summary>
    ///  Fetch extended address low byte from <c>PC++</c>.
    /// </summary>
    ExtendedLow,

    /// <summary>
    ///  Fetch indexed postbyte from <c>PC++</c>.
    /// </summary>
    IndexedPostbyte,

    /// <summary>
    ///  Fetch 8-bit signed indexed offset from <c>PC++</c>.
    /// </summary>
    IndexedOffset8,

    /// <summary>
    ///  Fetch 16-bit indexed offset or pointer high byte from <c>PC++</c>.
    /// </summary>
    IndexedWordHigh,

    /// <summary>
    ///  Fetch 16-bit indexed offset or pointer low byte from <c>PC++</c>.
    /// </summary>
    IndexedWordLow,

    /// <summary>
    ///  Spend internal effective-address computation cycles before optional indirection or completion.
    /// </summary>
    InternalDelay,

    /// <summary>
    ///  Read indirect pointer high byte from <c>(Effective)</c>.
    /// </summary>
    IndirectHigh,

    /// <summary>
    ///  Read indirect pointer low byte from <c>(Effective + 1)</c>.
    /// </summary>
    IndirectLow,

    /// <summary>
    ///  Spend the single internal cycle after reading an indirect pointer.
    /// </summary>
    IndirectDelay
}
