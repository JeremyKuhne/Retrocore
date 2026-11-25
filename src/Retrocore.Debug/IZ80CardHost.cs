// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

/// <summary>
///  A machine that takes a Z80 card, such as the Apple II with the Z80 SoftCard or the Apple III with the SoftCard ///,
///  as the Z80's view (<see cref="SoftCardDebugTarget"/>) sees it.
/// </summary>
internal interface IZ80CardHost : IDebugTarget
{
    /// <summary>
    ///  Gets the Z80 card in the machine now, or null.
    /// </summary>
    Z80Card? InstalledZ80Card { get; }

    /// <summary>
    ///  Gets whether the next <see cref="StepTState"/> starts one of the machine's cycles, in which the 6502 runs if the
    ///  Z80 has given the bus back.
    /// </summary>
    bool StartsCycle { get; }

    /// <summary>
    ///  Gets whether the last step ran a 6502 cycle, which it does beside the Z80 while the Z80 finishes its instruction
    ///  after giving the bus back.
    /// </summary>
    bool Stepped { get; }

    /// <summary>
    ///  Advances by one of the Z80's T-states while it runs, else by a cycle, for the Z80's view.
    /// </summary>
    void StepTState();
}
