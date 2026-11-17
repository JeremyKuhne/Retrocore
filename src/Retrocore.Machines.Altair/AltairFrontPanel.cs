// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  The Altair's front panel: 16 switches, and the EXAMINE and DEPOSIT controls an operator keyed programs in with
///  while the machine was stopped.
/// </summary>
/// <remarks>
///  <para>
///   EXAMINE shows the byte at the address the switches set; EXAMINE NEXT the byte after the one shown. DEPOSIT stores
///   the low 8 switches at the address shown; DEPOSIT NEXT moves on and stores there. RUN, STOP, SINGLE STEP and RESET
///   are the machine's and the debugger's.
///  </para>
/// </remarks>
public sealed class AltairFrontPanel
{
    private readonly AltairBus _bus;

    /// <summary>
    ///  Connects the panel to the bus.
    /// </summary>
    /// <param name="bus">The bus.</param>
    internal AltairFrontPanel(AltairBus bus) => _bus = bus;

    /// <summary>
    ///  Gets or sets the 16 address and data switches; a set bit is a switch up.
    /// </summary>
    public ushort Switches { get; set; }

    /// <summary>
    ///  Gets the sense switches, the high 8 switches, which <c>IN $FF</c> reads.
    /// </summary>
    public byte SenseSwitches => (byte)(Switches >> 8);

    /// <summary>
    ///  Gets the address the panel shows, as its address lights do while the machine is stopped.
    /// </summary>
    public ushort Address { get; private set; }

    /// <summary>
    ///  Gets the byte at <see cref="Address"/>, as the data lights show it.
    /// </summary>
    public byte Data => _bus.Peek(Address);

    /// <summary>
    ///  EXAMINE: shows the byte at the address the switches set.
    /// </summary>
    public void Examine() => Address = Switches;

    /// <summary>
    ///  EXAMINE NEXT: shows the next byte.
    /// </summary>
    public void ExamineNext() => Address++;

    /// <summary>
    ///  DEPOSIT: stores the low 8 switches at the address shown. RAM takes it; elsewhere it is lost.
    /// </summary>
    public void Deposit() => _bus.Write(Address, (byte)Switches);

    /// <summary>
    ///  DEPOSIT NEXT: moves to the next address and stores the low 8 switches there.
    /// </summary>
    public void DepositNext()
    {
        Address++;
        Deposit();
    }
}
