// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Machines.Apple3;

/// <summary>
///  Microsoft's SoftCard ///: a Z80 that borrows the Apple III's bus by DMA while the 6502 waits.
/// </summary>
/// <remarks>
///  <para>
///   The card follows MAME's <c>softcard3</c>, which its authors describe as a best guess from the boot disk and
///   checks on real hardware:
///  </para>
///  <list type="bullet">
///   <item>
///    <description>
///     Its I/O addresses read <c>$50</c>, which the boot code looks for. Writing <c>$01</c> to one makes the Z80
///     start from zero at its next switch; writing <c>$10</c> lets the card answer reads of <c>$FFFC</c> and
///     <c>$FFFD</c> in place of the ROM or RAM.
///    </description>
///   </item>
///   <item>
///    <description>
///     A 6502 read of <c>$FFFC</c> then hands the bus to the Z80 and starts a supervision timer; a read of
///     <c>$FFFD</c> stops it. Both read <c>$FF</c>.
///    </description>
///   </item>
///   <item>
///    <description>
///     The Z80 gives the bus back with <c>OUT ($00),A</c>. If the timer, 200 ms (MAME's period, which it marks as
///     unchecked), runs out first, the card gives the bus back itself so the 6502 can serve SOS. Either way the
///     card forgets the reset and the <c>$FFFC</c> switch, which the 6502 sets again before the next one.
///    </description>
///   </item>
///   <item>
///    <description>
///     Z80 addresses go through the card's 256-byte mapping PROM, which gives the Apple page for each Z80 page, and
///     then through the 6502's view of memory, its bank and zero-page registers included.
///    </description>
///   </item>
///  </list>
///  <para>
///   The Z80 runs at twice the slots' 1.02 MHz. No source says whether the card lets the waiting 6502 refresh its
///   registers as the SoftCard does, so <see cref="Z80Card.RefreshesHost"/> starts off.
///  </para>
/// </remarks>
public sealed class SoftCard3 : Z80Card, IApple3Card
{
    /// <summary>
    ///  The length of a Z80 T-state, in the Apple III's unit of time, thousandths of a 14.318 MHz dot: seven dots, half
    ///  the slots' 1.02 MHz cycle.
    /// </summary>
    public const int TState = 7_000;

    // MAME's supervision timer: 5 Hz.
    private const long TimerPeriod = 2_863_636_364;

    private const byte Present = 0x50;
    private const byte ResetCommand = 0x01;
    private const byte InhibitCommand = 0x10;

    private readonly Apple3Bus _host;
    private readonly byte[] _prom;
    private bool _resetPending;
    private bool _inhibits;
    private long _timer;

    /// <summary>
    ///  Constructs a card, off.
    /// </summary>
    /// <param name="host">The Apple III's bus.</param>
    /// <param name="slot">The slot, 1 to 4.</param>
    /// <param name="prom">The 256-byte address mapping PROM.</param>
    /// <exception cref="ArgumentException">The PROM is not 256 bytes.</exception>
    internal SoftCard3(Apple3Bus host, int slot, ReadOnlySpan<byte> prom)
        : base(slot, refreshesHost: false)
    {
        if (prom.Length != 0x100) { throw new ArgumentException("The SoftCard /// PROM is 256 bytes.", nameof(prom)); }
        _host = host;
        _prom = prom.ToArray();
    }

    /// <summary>
    ///  Gets whether the supervision timer is running.
    /// </summary>
    public bool TimerRunning => _timer > 0;

    /// <inheritdoc/>
    public override ushort Translate(ushort address) => (ushort)((_prom[address >> 8] << 8) | (address & 0xFF));

    /// <inheritdoc/>
    public override byte Peek(ushort address) => _host.Peek(Translate(address));

    /// <inheritdoc/>
    public byte ReadIo(int offset) => Present;

    /// <inheritdoc/>
    public byte PeekIo(int offset) => Present;

    /// <inheritdoc/>
    public void WriteIo(int offset, byte value)
    {
        switch (value)
        {
            case ResetCommand:
                _resetPending = true;
                break;
            case InhibitCommand:
                _inhibits = true;
                break;
        }
    }

    /// <inheritdoc/>
    public bool InhibitsRead(ushort address) => _inhibits && address is 0xFFFC or 0xFFFD;

    /// <inheritdoc/>
    public byte ReadInhibited(ushort address)
    {
        if (address == 0xFFFC)
        {
            Start(_resetPending);
            _timer = TimerPeriod;
        }
        else
        {
            _timer = 0;
        }

        return 0xFF;
    }

    /// <inheritdoc/>
    void IApple3Card.Reset()
    {
        Halt();
        Forget();
    }

    /// <summary>
    ///  Runs the supervision timer.
    /// </summary>
    /// <param name="units">The time passed, in thousandths of a 14.318 MHz dot.</param>
    public void Advance(int units)
    {
        if (_timer <= 0 || (_timer -= units) > 0) { return; }
        Stop();
        Forget();
    }

    /// <inheritdoc/>
    protected internal override byte HostRead(ushort address) => _host.DmaRead(address);

    /// <inheritdoc/>
    protected internal override void HostWrite(ushort address, byte value) => _host.DmaWrite(address, value);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>OUT ($00)</c> gives the 6502 the bus back.
    ///  </para>
    /// </remarks>
    protected internal override void Out(ushort port, byte value)
    {
        if ((byte)port != 0) { return; }
        Stop();
        Forget();
    }

    // Clears the reset, the $FFFC switch and the timer, as giving the bus back does.
    private void Forget()
    {
        _resetPending = false;
        _inhibits = false;
        _timer = 0;
    }
}
