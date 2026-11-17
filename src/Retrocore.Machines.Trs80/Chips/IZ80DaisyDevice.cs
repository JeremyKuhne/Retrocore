// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  A Z80 family peripheral on the interrupt daisy chain: it requests interrupts in mode 2, supplies its vector when
///  the Z80 acknowledges one, and holds off the devices after it in the chain until the routine returns with
///  <c>RETI</c>.
/// </summary>
internal interface IZ80DaisyDevice
{
    /// <summary>
    ///  Gets the vector of the device's highest-priority interrupt that no interrupt of its own being serviced
    ///  outranks, or null when it requests none.
    /// </summary>
    byte? PendingVector { get; }

    /// <summary>
    ///  Gets whether one of the device's interrupts is being serviced, which holds off later devices.
    /// </summary>
    bool InService { get; }

    /// <summary>
    ///  Acknowledges the interrupt <see cref="PendingVector"/> names: it is serviced until <c>RETI</c>.
    /// </summary>
    void Acknowledge();

    /// <summary>
    ///  Ends the service of the device's highest-priority interrupt being serviced, as <c>RETI</c> does.
    /// </summary>
    void ReturnFromInterrupt();
}
