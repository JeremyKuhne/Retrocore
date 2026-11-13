// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Microsoft's Z-80 SoftCard: a Z80 that borrows the Apple's bus by DMA while the 6502 waits.
/// </summary>
/// <remarks>
///  <para>
///   A write anywhere in the card's <c>$Cn00-$CnFF</c> hands the bus over; the 6502 writes it to start the Z80, and
///   the Z80 writes it, at <c>$En00</c> in its own addresses, to give the bus back. Reads do nothing. The card has no
///   ROM or RAM: CP/M's 6502 boot loads the Z80's code into the Apple's memory and switches. Nothing decodes the
///   Z80's I/O.
///  </para>
///  <para>
///   The Z80's clock is built from the Apple's and locked to it, two T-states to each Apple cycle, with one memory
///   access to each machine cycle and no wait states. During the refresh half of each opcode fetch the card lets
///   the waiting 6502 make one read, which it discards, so its dynamic registers keep their state. MAME and
///   AppleWin leave the read out; turn <see cref="Z80Card.RefreshesHost"/> off to run in step with them.
///  </para>
///  <para>
///   The Apple's RESET turns the card off, and the Z80 starts from zero at the first switch after it.
///  </para>
/// </remarks>
public sealed class SoftCard : Z80Card
{
    // The Apple page each Z80 4K page reads: $0-$A shift up by $1000, $B-$D reach the high ROM or language card,
    // $E the I/O page and $F the zero page.
    private static ReadOnlySpan<byte> Pages => [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xD, 0xE, 0xF, 0xC, 0x0];

    private readonly Apple2Bus _host;
    private bool _resetPending = true;

    /// <summary>
    ///  Constructs a card, off, with its Z80 to start from zero at the first switch.
    /// </summary>
    /// <param name="host">The Apple's bus.</param>
    /// <param name="slot">The slot.</param>
    internal SoftCard(Apple2Bus host, int slot)
        : base(slot, refreshesHost: true) => _host = host;

    /// <summary>
    ///  Gets or sets whether Z80 addresses are translated, as DIP switch S1-1 off makes them. With it on, the Z80
    ///  sees the Apple's addresses unchanged.
    /// </summary>
    public bool Translates { get; set; } = true;

    /// <inheritdoc/>
    public override ushort Translate(ushort address) =>
        Translates ? (ushort)((Pages[address >> 12] << 12) | (address & 0x0FFF)) : address;

    /// <inheritdoc/>
    public override byte Peek(ushort address) => _host.Peek(Translate(address));

    /// <summary>
    ///  Runs the Z80 for one Apple cycle: two T-states.
    /// </summary>
    /// <param name="heldAddress">The address the waiting 6502 reads in a refresh: its next opcode's.</param>
    public void StepAppleCycle(ushort heldAddress)
    {
        StepTState(heldAddress);
        StepTState(heldAddress);
    }

    /// <summary>
    ///  Hands the bus over, for a write to <c>$Cn00-$CnFF</c> from either processor.
    /// </summary>
    internal void Switch()
    {
        if (OwnsBus)
        {
            Stop();
            return;
        }

        Start(_resetPending);
        _resetPending = false;
    }

    /// <summary>
    ///  Answers the Apple's RESET: the card turns off, and the Z80 starts again from zero at the next switch.
    /// </summary>
    internal void Reset()
    {
        Halt();
        _resetPending = true;
    }

    /// <inheritdoc/>
    protected internal override byte HostRead(ushort address) => _host.Read(address);

    /// <inheritdoc/>
    protected internal override void HostWrite(ushort address, byte value) => _host.Write(address, value);
}
