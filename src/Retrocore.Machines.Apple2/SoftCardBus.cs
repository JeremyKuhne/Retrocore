// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The SoftCard's Z80's view of the Apple's bus, through the card's address translation. Nothing decodes I/O.
/// </summary>
public sealed class SoftCardBus : IProcessorBus, IIoBus
{
    private readonly Apple2Bus _host;
    private readonly SoftCard _card;

    /// <summary>
    ///  Constructs the card's bus.
    /// </summary>
    /// <param name="host">The Apple's bus.</param>
    /// <param name="card">The card, for its translation.</param>
    internal SoftCardBus(Apple2Bus host, SoftCard card)
    {
        _host = host;
        _card = card;
    }

    /// <inheritdoc/>
    public byte Read(ushort address) => _host.Read(_card.Translate(address));

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => _host.Write(_card.Translate(address), value);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The card does not decode IORQ, so nothing drives the data bus.
    ///  </para>
    /// </remarks>
    public byte In(ushort port) => 0xFF;

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
    }
}
