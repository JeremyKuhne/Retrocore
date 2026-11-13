// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  The group an instruction falls in for the flags an unprefixed undocumented store immediate (<c>$87</c>,
///  <c>$8F</c>, <c>$C7</c>, <c>$CF</c>) sets right after it.
/// </summary>
/// <remarks>
///  <para>
///   The groups and their flags are from David Banks's
///   <see href="https://github.com/hoglet67/6809Decoder/wiki/Undocumented-6809-Behaviours#flags-for-unprefixed-store-immediate">Undocumented
///   6809 Behaviours</see>, tested on real chips.
///  </para>
/// </remarks>
internal enum M6809FlagGroup : byte
{
    /// <summary>
    ///  Every other instruction: N set, Z and V cleared.
    /// </summary>
    Default,

    /// <summary>
    ///  <c>BITA</c> and <c>CMPA</c>: Z set, N and V cleared.
    /// </summary>
    ZeroSet,

    /// <summary>
    ///  <c>LDA</c> and <c>LDD</c>: N and Z from A, V cleared.
    /// </summary>
    AccumulatorA,

    /// <summary>
    ///  The A arithmetic and logic: Z when A is <c>$FF</c>, N when A is positive, V cleared.
    /// </summary>
    AccumulatorAInverted,

    /// <summary>
    ///  The A read-modify-write group, <c>DAA</c> and <c>SUBD</c>: as a decrement of A.
    /// </summary>
    AccumulatorADecrement,

    /// <summary>
    ///  <c>SEX</c>: as a decrement of B.
    /// </summary>
    AccumulatorBDecrement,

    /// <summary>
    ///  The 16-bit compares, <c>XADDD</c> and <c>XADDU</c>, and <c>LEA</c>: as a decrement of a latched byte.
    /// </summary>
    LatchedDecrement
}
