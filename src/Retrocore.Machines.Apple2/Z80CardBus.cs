// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A Z80 card's view of its host's bus, through the card's address translation.
/// </summary>
public sealed class Z80CardBus : IProcessorBus, IIoBus
{
    private readonly Z80Card _card;

    /// <summary>
    ///  Constructs the card's bus.
    /// </summary>
    /// <param name="card">The card.</param>
    internal Z80CardBus(Z80Card card) => _card = card;

    /// <inheritdoc/>
    public byte Read(ushort address) => _card.HostRead(_card.Translate(address));

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => _card.HostWrite(_card.Translate(address), value);

    /// <inheritdoc/>
    public byte In(ushort port) => _card.In(port);

    /// <inheritdoc/>
    public void Out(ushort port, byte value) => _card.Out(port, value);
}
