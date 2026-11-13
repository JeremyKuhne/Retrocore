// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.Z80;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Microsoft's Z-80 SoftCard: a Z80 that borrows the Apple's bus by DMA while the 6502 waits.
/// </summary>
/// <remarks>
///  <para>
///   A write anywhere in the card's <c>$Cn00-$CnFF</c> hands the bus over; the 6502 writes it to start the Z80, and
///   the Z80 writes it, at <c>$En00</c> in its own addresses, to give the bus back. Reads do nothing. The card has no
///   ROM or RAM: CP/M's 6502 boot loads the Z80's code into the Apple's memory and switches.
///  </para>
///  <para>
///   The Z80's clock is built from the Apple's and locked to it, two T-states to each Apple cycle, with one memory
///   access to each machine cycle and no wait states. During the refresh half of each opcode fetch the card lets
///   the waiting 6502 make one read, which it discards, so its dynamic registers keep their state.
///  </para>
///  <para>
///   The Z80 is held in WAIT while the 6502 runs and resumes where it stopped; it is not reset by a switch. The
///   Apple's RESET turns the card off, and the Z80 starts from zero at the first switch after it.
///  </para>
/// </remarks>
public sealed class SoftCard
{
    // The Apple page each Z80 4K page reads: $0-$A shift up by $1000, $B-$D reach the high ROM or language card,
    // $E the I/O page and $F the zero page.
    private static ReadOnlySpan<byte> Pages => [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xD, 0xE, 0xF, 0xC, 0x0];

    private readonly Apple2Bus _host;
    private bool _resetPending = true;

    // Whether the Z80 finished its last instruction after giving the bus back, so WAIT holds it at the next one's
    // opcode fetch rather than in the middle of an instruction.
    private bool _drained;

    /// <summary>
    ///  Constructs a card, off, with its Z80 to start from zero at the first switch.
    /// </summary>
    /// <param name="host">The Apple's bus.</param>
    /// <param name="slot">The slot.</param>
    internal SoftCard(Apple2Bus host, int slot)
    {
        _host = host;
        Slot = slot;
        Processor = new(new SoftCardBus(host, this));
        Processor.Signals = Z80Signals.Wait;
    }

    /// <summary>
    ///  Gets the slot the card is in.
    /// </summary>
    public int Slot { get; }

    /// <summary>
    ///  Gets the card's Z80.
    /// </summary>
    public Z80Processor<SoftCardBus> Processor { get; }

    /// <summary>
    ///  Gets whether the Z80 has the bus, with the 6502 held.
    /// </summary>
    public bool OwnsBus { get; private set; }

    /// <summary>
    ///  Gets whether the Z80 is running: while it has the bus, and after it gives the bus back until its next
    ///  access, which WAIT holds.
    /// </summary>
    public bool Running { get; private set; }

    /// <summary>
    ///  Gets or sets whether Z80 addresses are translated, as DIP switch S1-1 off makes them. With it on, the Z80
    ///  sees the Apple's addresses unchanged.
    /// </summary>
    public bool Translates { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the waiting 6502 reads once in each opcode fetch's refresh, as the card lets it. MAME
    ///  and AppleWin leave the read out; turn it off to run in step with them.
    /// </summary>
    public bool RefreshesHost { get; set; } = true;

    /// <summary>
    ///  Gets or sets what to call each time the Z80 reaches an instruction boundary, such as a debugger's check for
    ///  a breakpoint at the next instruction.
    /// </summary>
    public Action<SoftCard>? InstructionBoundary { get; set; }

    /// <summary>
    ///  Gets the Apple address a Z80 address reaches.
    /// </summary>
    /// <param name="address">The Z80 address.</param>
    /// <returns>The Apple address.</returns>
    public ushort Translate(ushort address) =>
        Translates ? (ushort)((Pages[address >> 12] << 12) | (address & 0x0FFF)) : address;

    /// <summary>
    ///  Reads what the Z80 would see at an address, without side effects.
    /// </summary>
    /// <param name="address">The Z80 address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address) => _host.Peek(Translate(address));

    /// <summary>
    ///  Gives the Z80 the bus, as a 6502 write to the card's page does, unless it has it; a debugger starting a Z80
    ///  program uses it.
    /// </summary>
    public void TakeBus()
    {
        if (!OwnsBus) { Switch(); }
    }

    /// <summary>
    ///  Hands the bus over, for a write to <c>$Cn00-$CnFF</c> from either processor.
    /// </summary>
    internal void Switch()
    {
        if (OwnsBus)
        {
            // The Z80 finishes its write and any internal T-states, then waits at its next access.
            OwnsBus = false;
            _drained = false;
            Processor.Signals |= Z80Signals.Wait;
            return;
        }

        if (_resetPending)
        {
            Processor.Reset();
            _resetPending = false;
        }

        OwnsBus = true;
        Running = true;
        Processor.Signals &= ~Z80Signals.Wait;
    }

    /// <summary>
    ///  Answers the Apple's RESET: the card turns off, and the Z80 starts again from zero at the next switch.
    /// </summary>
    internal void Reset()
    {
        OwnsBus = false;
        Running = false;
        _drained = false;
        _resetPending = true;
        Processor.Signals |= Z80Signals.Wait;
    }

    /// <summary>
    ///  Gets whether WAIT holds the Z80 at the opcode fetch of its next instruction, with the 6502 running: its PC is
    ///  that instruction's address, and nothing of it has run.
    /// </summary>
    public bool WaitingAtInstruction => !Running && _drained;

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
    ///  Runs the Z80 for one T-state, half an Apple cycle, if it is running.
    /// </summary>
    /// <param name="heldAddress">The address the waiting 6502 reads in a refresh: its next opcode's.</param>
    public void StepTState(ushort heldAddress)
    {
        if (!Running) { return; }
        Processor.StepCycle();
        if (RefreshesHost && OwnsBus && Processor.FetchedOpcode) { _host.Read(heldAddress); }
        if (!OwnsBus)
        {
            _drained |= Processor.IsInstructionBoundary;
            if (Processor.IsWaiting) { Running = false; }
        }

        if (InstructionBoundary is { } boundary && Processor.IsInstructionBoundary) { boundary(this); }
    }
}
