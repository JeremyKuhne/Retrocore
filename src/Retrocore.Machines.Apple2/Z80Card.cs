// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.Z80;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A slot card with a Z80 that borrows its host's bus by DMA while the 6502 waits, as Microsoft's SoftCards do.
/// </summary>
/// <remarks>
///  <para>
///   The Z80 is held in WAIT while the 6502 runs, and resumes where it stopped. When it gives the bus back it
///   finishes its instruction and waits at the next one's opcode fetch. The host's machine steps the card, one Z80
///   T-state at a time, and holds its 6502 at its next opcode fetch while the Z80 has the bus.
///  </para>
/// </remarks>
public abstract class Z80Card
{
    // Whether the Z80 finished its last instruction after giving the bus back, so WAIT holds it at the next one's
    // opcode fetch rather than in the middle of an instruction.
    private bool _drained;

    /// <summary>
    ///  Constructs a card, off, with its Z80 waiting.
    /// </summary>
    /// <param name="slot">The slot.</param>
    /// <param name="refreshesHost">Whether the waiting 6502 reads in each opcode fetch's refresh, at first.</param>
    protected Z80Card(int slot, bool refreshesHost)
    {
        Slot = slot;
        RefreshesHost = refreshesHost;
        Processor = new(new Z80CardBus(this));
        Processor.Signals = Z80Signals.Wait;
    }

    /// <summary>
    ///  Gets the slot the card is in.
    /// </summary>
    public int Slot { get; }

    /// <summary>
    ///  Gets the card's Z80.
    /// </summary>
    public Z80Processor<Z80CardBus> Processor { get; }

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
    ///  Gets or sets whether the waiting 6502 reads once in each opcode fetch's refresh.
    /// </summary>
    public bool RefreshesHost { get; set; }

    /// <summary>
    ///  Gets or sets what to call each time the Z80 reaches an instruction boundary, such as a debugger's check for
    ///  a breakpoint at the next instruction.
    /// </summary>
    public Action<Z80Card>? InstructionBoundary { get; set; }

    /// <summary>
    ///  Gets whether WAIT holds the Z80 at the opcode fetch of its next instruction, with the 6502 running: its PC is
    ///  that instruction's address, and nothing of it has run.
    /// </summary>
    public bool WaitingAtInstruction => !Running && _drained;

    /// <summary>
    ///  Gets the host address a Z80 address reaches.
    /// </summary>
    /// <param name="address">The Z80 address.</param>
    /// <returns>The host address.</returns>
    public abstract ushort Translate(ushort address);

    /// <summary>
    ///  Reads what the Z80 would see at an address, without side effects.
    /// </summary>
    /// <param name="address">The Z80 address.</param>
    /// <returns>The value.</returns>
    public abstract byte Peek(ushort address);

    /// <summary>
    ///  Gets how many times the Z80 has been reset or stopped by a reset, so a debugger knows to forget its calls.
    /// </summary>
    public int Resets { get; private set; }

    /// <summary>
    ///  Gives the Z80 the bus, as the 6502's switch does, unless it has it; a debugger starting a Z80 program uses
    ///  it. The Z80 goes on from where it is, and a reset the card has waiting for its next switch is spent.
    /// </summary>
    public virtual void TakeBus() => Start(reset: false);

    /// <summary>
    ///  Runs the Z80 for one T-state, if it is running.
    /// </summary>
    /// <param name="heldAddress">The address the waiting 6502 reads in a refresh: its next opcode's.</param>
    public void StepTState(ushort heldAddress)
    {
        if (!Running) { return; }
        Processor.StepCycle();
        // The 6502's read comes in the refresh T-state of each opcode fetch, the one after the opcode's read.
        if (RefreshesHost && OwnsBus && Processor.IsRefreshing) { HostRead(heldAddress); }
        if (!OwnsBus)
        {
            _drained |= Processor.IsInstructionBoundary;
            if (Processor.IsWaiting) { Running = false; }
        }

        if (InstructionBoundary is { } boundary && Processor.IsInstructionBoundary) { boundary(this); }
    }

    /// <summary>
    ///  Reads the host's bus for the Z80, at a host address, with side effects.
    /// </summary>
    /// <param name="address">The host address.</param>
    /// <returns>The value.</returns>
    protected internal abstract byte HostRead(ushort address);

    /// <summary>
    ///  Writes the host's bus for the Z80, at a host address.
    /// </summary>
    /// <param name="address">The host address.</param>
    /// <param name="value">The value.</param>
    protected internal abstract void HostWrite(ushort address, byte value);

    /// <summary>
    ///  Answers a Z80 <c>IN</c>.
    /// </summary>
    /// <param name="port">The port, with the high byte the Z80 puts on the bus.</param>
    /// <returns>The value; nothing drives the bus unless the card decodes the port.</returns>
    protected internal virtual byte In(ushort port) => 0xFF;

    /// <summary>
    ///  Answers a Z80 <c>OUT</c>; nothing decodes it unless the card does.
    /// </summary>
    /// <param name="port">The port, with the high byte the Z80 puts on the bus.</param>
    /// <param name="value">The value.</param>
    protected internal virtual void Out(ushort port, byte value)
    {
    }

    /// <summary>
    ///  Gives the Z80 the bus, unless it has it.
    /// </summary>
    /// <param name="reset">
    ///  Whether the Z80 starts from zero, abandoning the instruction it waited at; the reset is an instruction boundary
    ///  for <see cref="InstructionBoundary"/>.
    /// </param>
    protected void Start(bool reset)
    {
        if (OwnsBus) { return; }
        OwnsBus = true;
        Running = true;
        Processor.Signals &= ~Z80Signals.Wait;
        if (reset)
        {
            Processor.Reset();
            Resets++;
            InstructionBoundary?.Invoke(this);
        }
    }

    /// <summary>
    ///  Gives the 6502 the bus back, if the Z80 has it. The Z80 finishes its instruction, then waits at its next
    ///  access.
    /// </summary>
    protected void Stop()
    {
        if (!OwnsBus) { return; }
        OwnsBus = false;
        _drained = false;
        Processor.Signals |= Z80Signals.Wait;
    }

    /// <summary>
    ///  Stops the Z80 at once, wherever it is, as the host's RESET does.
    /// </summary>
    protected void Halt()
    {
        Resets++;
        OwnsBus = false;
        Running = false;
        _drained = false;
        Processor.Signals |= Z80Signals.Wait;
    }
}
