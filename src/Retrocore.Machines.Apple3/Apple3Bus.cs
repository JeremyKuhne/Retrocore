// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's memory and devices: banked RAM, the boot ROM, the I/O page, extended addressing and the two
///  system VIAs whose ports are the environment, zero-page and bank registers.
/// </summary>
/// <remarks>
///  <para>
///   RAM is a whole number of 32K banks. The last is the system bank, seen at <c>$0000-$1FFF</c> and
///   <c>$A000-$FFFF</c>; the bank register (VIA 1 port A) picks the one at <c>$2000-$9FFF</c>. The zero-page register
///   (VIA 0 port B) moves zero page to any page, and the stack with it, to the page above with its low bit flipped.
///  </para>
///  <para>
///   Extended addressing: while zero page is one of pages <c>$18-$1F</c>, a zero-page read outside an opcode fetch
///   latches the "X-byte" at the same address XOR <c>$0C00</c>. If its bit 7 is set, every access above
///   <c>$00FF</c> until the next SYNC goes to the 64K the X-byte's low nibble names, ignoring I/O and ROM.
///   <c>(zp),Y</c> reads its pointer's high byte last, so the X-byte that counts sits beside the high byte, where
///   SOS keeps it.
///  </para>
///  <para>
///   Bank numbers are three bits on Apple's boards, and four with 512K. The all-ones number (7, or 15) is special,
///   for the bank register and an X-byte alike: system RAM where it always is, with bank 0 at <c>$2000-$9FFF</c>.
///   SOS's X-byte <c>$8F</c> is this view. Other numbers wrap at the number of switchable banks, and in extended
///   addressing the last bank's partner above <c>$8000</c> is bank 0.
///  </para>
///  <para>
///   The decoding follows the Apple III Service Reference Manual: its RAM decode PROM equations (pages 2.23-2.26)
///   and the 128K board's layout (2.19). MAME's <c>apple3</c> driver maps bank 7 to bank 2 instead. On 128K, what
///   values 3-6 select depends on which of the manual's two RAS PROMs is fitted; here they wrap to banks 0-2.
///  </para>
///  <para>
///   Slots 1-4 take cards (<see cref="IApple3Card"/>): their I/O at <c>$C090-$C0CF</c>, their ROM pages at
///   <c>$C100-$C4FF</c> and the expansion ROM at <c>$C800-$CFFF</c> answer while the environment enables I/O, as in
///   MAME. A card can inhibit reads at <c>$F000-$FFFF</c>, and a card's DMA (<see cref="DmaRead"/>) sees memory as the
///   6502 does. Slot interrupts are not wired yet.
///  </para>
/// </remarks>
public sealed class Apple3Bus : IOpcodeFetchBus
{
    /// <summary>
    ///  Environment register bit 7: the CPU runs at 1 MHz rather than 2.
    /// </summary>
    public const byte SlowSpeed = 0x80;

    /// <summary>
    ///  Environment register bit 6: the I/O page and slot space answer at <c>$C000-$CFFF</c>.
    /// </summary>
    public const byte IoEnable = 0x40;

    /// <summary>
    ///  Environment register bit 5: video is on.
    /// </summary>
    public const byte VideoEnable = 0x20;

    /// <summary>
    ///  Environment register bit 4: the RESET key may interrupt or reset.
    /// </summary>
    public const byte NmiEnable = 0x10;

    /// <summary>
    ///  Environment register bit 3: RAM at <c>$C000-$FFFF</c> in the system bank is read-only.
    /// </summary>
    public const byte WriteProtect = 0x08;

    /// <summary>
    ///  Environment register bit 2: the stack is page 1 of the system bank, wherever zero page is.
    /// </summary>
    public const byte PrimaryStack = 0x04;

    /// <summary>
    ///  Environment register bit 0: the boot ROM answers reads at <c>$F000-$FFFF</c>.
    /// </summary>
    public const byte RomEnable = 0x01;

    // VIA 1 port A bit 6: the VIAs answer at $FFD0-$FFEF (cleared to trap into Apple II mode).
    private const byte ViasVisible = 0x40;

    // The Apple III's 14.318181 MHz master clock, in thousandths of a dot, the bus's unit of time.
    private const int ViaPeriod = 14_000;                // 14M / 14
    private const int PaddlePeriod = 15_072;             // the analog ramp's 950 kHz
    private const int BeepPeriod = 7_159_090;            // $C040's 2 kHz
    // The symbols typed with SHIFT on the III's keyboard.
    private const string ShiftedSymbols = "!@#$%^&*()_+{}|:\"<>?~";

    private const int KeyInterval = 286_363_620;         // 20 ms between queued keys

    private readonly byte[] _ram;
    private readonly byte[] _rom;
    private readonly int _switchableBanks;
    private readonly int _bankMask;
    private readonly int _system;
    private readonly Queue<(byte Code, bool Shifted)> _keys = new();

    private int _zeroPageBase;
    private int _stackBase;
    private int _bankBase;
    private byte _extendedBank;
    private bool _sync;

    private int _viaTime;
    private int _paddleTime;
    private int _beepTime;
    private int _beepToggles;

    private int _driveSelect;
    private bool _externalDrive;

    private byte _key;
    private bool _keyShifted;
    private int _keyDelay;
    private byte _strobe;
    private int _analogSelect;
    private bool _rampActive;
    private int _paddleCharge;

    // The slots' cards, by slot (index 0 unused); the installed ones, asked about inhibited reads; and the slot whose
    // expansion ROM answers at $C800, or 0.
    private readonly IApple3Card?[] _slots = new IApple3Card?[5];
    private IApple3Card[] _inhibitors = [];
    private int _expansionSlot;

    /// <summary>
    ///  Constructs a bus.
    /// </summary>
    /// <param name="roms">The firmware.</param>
    /// <param name="ramKilobytes">128, 256 or 512.</param>
    public Apple3Bus(Apple3Roms roms, int ramKilobytes = 256)
    {
        ArgumentNullException.ThrowIfNull(roms);
        if (ramKilobytes is not (128 or 256 or 512))
        {
            throw new ArgumentOutOfRangeException(nameof(ramKilobytes), "The Apple III has 128K, 256K or 512K.");
        }

        // What DRAM holds at power-on is happenstance; all ones, as MAME has it, keeps the two in step where the
        // ROM reads memory it never wrote, such as the last boot drive at $038A.
        _ram = new byte[ramKilobytes * 1024];
        _ram.AsSpan().Fill(0xFF);
        _rom = roms.Boot.ToArray();
        _switchableBanks = (_ram.Length / 0x8000) - 1;
        _bankMask = ramKilobytes == 512 ? 0x0F : 0x07;
        _system = _ram.Length - 0x8000;
        Disk = new(drives: 4);
        Disk.SetFirmware(roms.Disk);
        PowerOn();
    }

    /// <summary>
    ///  Gets VIA 0 (the "D" VIA): port A is the environment register, port B the zero-page register.
    /// </summary>
    public Via6522 Via0 { get; } = new();

    /// <summary>
    ///  Gets VIA 1 (the "E" VIA): port A selects the bank and reports interrupts, port B drives the DAC.
    /// </summary>
    public Via6522 Via1 { get; } = new();

    /// <summary>
    ///  Gets the built-in disk controller at <c>$C0E0</c>: drive 1 is the built-in drive (.D1), 2-4 the external ones.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>$C0EA</c> selects the built-in drive and <c>$C0EB</c> an external one, which <c>$C0D0-$C0D3</c> number:
    ///   bit 0 at <c>$C0D0/1</c>, bit 1 at <c>$C0D2/3</c>. Number 0 reaches the built-in drive, as MAME has it.
    ///  </para>
    /// </remarks>
    public DiskIIController Disk { get; }

    /// <summary>
    ///  Gets the clock at <c>$C070</c>.
    /// </summary>
    public Mm58167 Clock { get; } = new();

    /// <summary>
    ///  Gets the sound: the speaker (or bell) and VIA 1's 6-bit DAC, mixed at the VIAs' 1.02 MHz.
    /// </summary>
    public Apple2Audio Audio { get; } = new();

    /// <summary>
    ///  Gets the smooth-scroll offset, 0-7: VA, VB and VC, set at <c>$C0E0-$C0E5</c> alongside the disk's phases.
    /// </summary>
    public int ScrollOffset { get; private set; }

    /// <summary>
    ///  Gets the built-in serial port at <c>$C0F0</c>.
    /// </summary>
    public Acia6551 Acia { get; } = new();

    /// <summary>
    ///  Gets RAM, the system bank last.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets the boot ROM's image, whether or not it is mapped in.
    /// </summary>
    public ReadOnlySpan<byte> Rom => _rom;

    /// <summary>
    ///  Gets the RAM size in kilobytes.
    /// </summary>
    public int RamKilobytes => _ram.Length / 1024;

    /// <summary>
    ///  Gets the environment register, VIA 0's port A.
    /// </summary>
    public byte Environment { get; private set; }

    /// <summary>
    ///  Gets the zero-page register, VIA 0's port B.
    /// </summary>
    public byte ZeroPage { get; private set; }

    /// <summary>
    ///  Gets the bank register, VIA 1's port A.
    /// </summary>
    public byte BankRegister { get; private set; }

    /// <summary>
    ///  Gets the extended addressing latch: 0, or the X-byte (bit 7 set) in force until the next SYNC.
    /// </summary>
    public byte ExtendedBank => (byte)((_extendedBank & 0x80) != 0 ? _extendedBank : 0);

    /// <summary>
    ///  Gets the video soft switches set through <c>$C050-$C057</c>, one bit per pair.
    /// </summary>
    public byte VideoSwitches { get; private set; }

    /// <summary>
    ///  Gets whether <c>$C0D9</c> turned on smooth scrolling.
    /// </summary>
    public bool SmoothScroll { get; private set; }

    /// <summary>
    ///  Gets whether <c>$C0DB</c> enabled loading character RAM.
    /// </summary>
    public bool CharacterWrite { get; private set; }

    /// <summary>
    ///  Gets the speaker's level, toggled by <c>$C030</c> and by the <c>$C040</c> beep.
    /// </summary>
    public bool Speaker { get; private set; }

    /// <summary>
    ///  Gets the joysticks' positions, 0-255, centered at 127: the first's X and Y, then the second's.
    /// </summary>
    public byte[] Joysticks { get; } = [127, 127, 127, 127];

    /// <summary>
    ///  Gets or sets the joystick buttons held: bit 0 the first stick's button (<c>$C060</c>), bit 1 the second's
    ///  (<c>$C062</c>), bits 2 and 3 the other switch inputs (<c>$C061</c>, <c>$C063</c>).
    /// </summary>
    public int Buttons { get; set; }

    /// <summary>
    ///  Gets or sets the modifier keys held.
    /// </summary>
    public Apple3Modifiers Modifiers { get; set; }

    /// <summary>
    ///  Gets the combined interrupt request of the VIAs.
    /// </summary>
    public bool InterruptRequested => Via0.InterruptRequested || Via1.InterruptRequested;

    /// <summary>
    ///  Gets whether the processor runs at 1 MHz, as the environment register asks.
    /// </summary>
    public bool IsSlow => (Environment & SlowSpeed) != 0;

    /// <summary>
    ///  Puts the bus in its power-on state: both VIAs reset, so every register reads all ones, mapping the ROM and
    ///  I/O in at 1 MHz.
    /// </summary>
    public void PowerOn()
    {
        Via0.Reset();
        Via1.Reset();
        Via1.PortAInput = 0xFF;
        Via1.PortBInput = 0xFF;
        Acia.Reset();
        UpdateRegisters();
        ResetDevices();
    }

    /// <summary>
    ///  Resets what a RESET does without touching the VIAs or RAM: the extended latch, the keyboard strobe and the disk.
    /// </summary>
    public void ResetDevices()
    {
        _extendedBank = 0;
        _sync = false;
        _strobe = 0;
        _beepToggles = 0;
        _rampActive = false;
        _driveSelect = 0;
        _externalDrive = false;
        _expansionSlot = 0;
        Disk.Reset();
        foreach (IApple3Card? card in _slots) { card?.Reset(); }
    }

    /// <summary>
    ///  Gets the card in a slot, or null.
    /// </summary>
    /// <param name="slot">The slot, 1 to 4.</param>
    /// <returns>The card.</returns>
    public IApple3Card? Card(int slot) => slot is >= 1 and <= 4 ? _slots[slot] : null;

    /// <summary>
    ///  Gets the SoftCard ///, or null when none is installed.
    /// </summary>
    public SoftCard3? SoftCard { get; private set; }

    /// <summary>
    ///  Gets a count that changes whenever a card goes in or comes out.
    /// </summary>
    public int CardChanges { get; private set; }

    /// <summary>
    ///  Puts a card in its slot.
    /// </summary>
    /// <param name="card">The card.</param>
    /// <exception cref="InvalidOperationException">
    ///  The slot is not 1 to 4 or has a card, or the card is a second SoftCard ///.
    /// </exception>
    public void InstallCard(IApple3Card card)
    {
        ArgumentNullException.ThrowIfNull(card);
        if (card.Slot is < 1 or > 4 || _slots[card.Slot] is not null)
        {
            throw new InvalidOperationException($"Slot {card.Slot} is not free.");
        }

        if (card is SoftCard3 softCard)
        {
            if (SoftCard is not null) { throw new InvalidOperationException("A SoftCard /// is already installed."); }
            SoftCard = softCard;
        }

        _slots[card.Slot] = card;
        CardsChanged();
    }

    /// <summary>
    ///  Puts a SoftCard /// in a free slot, off.
    /// </summary>
    /// <param name="slot">The slot, 1 to 4.</param>
    /// <param name="prom">The card's 256-byte address mapping PROM.</param>
    /// <returns>The card.</returns>
    /// <exception cref="InvalidOperationException">
    ///  The slot is not free, or a SoftCard /// is already installed.
    /// </exception>
    public SoftCard3 InstallSoftCard(int slot, ReadOnlySpan<byte> prom)
    {
        SoftCard3 card = new(this, slot, prom);
        InstallCard(card);
        return card;
    }

    /// <summary>
    ///  Takes the card out of a slot. If it is the SoftCard ///, the 6502 gets the bus back.
    /// </summary>
    /// <param name="slot">The slot, 1 to 4.</param>
    /// <exception cref="InvalidOperationException">The slot has no card.</exception>
    public void RemoveCard(int slot)
    {
        if (Card(slot) is not { } card) { throw new InvalidOperationException($"Slot {slot} has no card."); }
        if (ReferenceEquals(card, SoftCard)) { SoftCard = null; }
        _slots[slot] = null;
        if (_expansionSlot == slot) { _expansionSlot = 0; }
        CardsChanged();
    }

    /// <summary>
    ///  Reads for a card's DMA: what the 6502 would read at the address, through the bank and zero-page registers
    ///  but without extended addressing, which only the 6502's own instructions start.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The value.</returns>
    public byte DmaRead(ushort address)
    {
        byte extended = _extendedBank;
        bool sync = _sync;
        _extendedBank = 0;
        _sync = true;
        byte value = Read(address);
        _extendedBank = extended;
        _sync = sync;
        return value;
    }

    /// <summary>
    ///  Writes for a card's DMA, as the 6502 would write at the address, without extended addressing.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <param name="value">The value.</param>
    public void DmaWrite(ushort address, byte value)
    {
        byte extended = _extendedBank;
        _extendedBank = 0;
        Write(address, value);
        _extendedBank = extended;
    }

    private void CardsChanged()
    {
        _inhibitors = [.. _slots.OfType<IApple3Card>()];
        CardChanges++;
    }

    /// <summary>
    ///  Queues a key, delivered once the program clears the strobe of the last one.
    /// </summary>
    /// <param name="code">
    ///  The code: ASCII, with escape, tab, space and the arrow keys (control-H, -U, -J and -K) becoming the III's own
    ///  codes, which set bit 7; or a code with bit 7 already set, such as <c>$B0-$B9</c> for the keypad's digits.
    /// </param>
    /// <remarks>
    ///  <para>
    ///   The III's keyboard sends letters as capitals and reports SHIFT at <c>$C008</c>, from which SOS makes
    ///   lowercase, and SOS also reads SHIFT to tell a symbol from the digit or mark on the same key. So a capital
    ///   letter or a shifted symbol goes with SHIFT held while it is the current key, and a small letter as its
    ///   capital without.
    ///  </para>
    /// </remarks>
    public void QueueKey(byte code)
    {
        bool shifted = code is >= (byte)'A' and <= (byte)'Z' || ShiftedSymbols.Contains((char)code);
        _keys.Enqueue((code switch
        {
            0x1B => 0x9B,
            0x09 => 0x89,
            0x20 => 0xA0,
            0x08 => 0x88,
            0x15 => 0x95,
            0x0A => 0x8A,
            0x0B => 0x8B,
            >= (byte)'a' and <= (byte)'z' => (byte)(code - 0x20),
            _ => code
        }, shifted));

        if (_strobe == 0 && _keyDelay == 0) { DeliverKey(); }
    }

    /// <summary>
    ///  Sets the screen-blank input (VIA 1 PB6), low while the beam draws a visible line.
    /// </summary>
    /// <param name="drawing">Whether the beam is in the visible part of a visible line.</param>
    public void SetDrawing(bool drawing) =>
        Via1.PortBInput = drawing ? (byte)(Via1.PortBInput & ~0x40) : (byte)(Via1.PortBInput | 0x40);

    /// <summary>
    ///  Sets the vertical blanking signal, wired to VIA 1's CB1 and CB2.
    /// </summary>
    /// <param name="blanking">Whether the beam is in vertical blanking.</param>
    public void SetVerticalBlank(bool blanking)
    {
        Via1.CB1 = blanking;
        Via1.CB2 = blanking;
    }

    /// <summary>
    ///  Advances the devices clocked from the master clock.
    /// </summary>
    /// <param name="units">The time passed, in thousandths of a 14.318 MHz dot.</param>
    public void Advance(int units)
    {
        _viaTime += units;
        while (_viaTime >= ViaPeriod)
        {
            _viaTime -= ViaPeriod;
            Via0.Tick();
            Via1.Tick();
            float dac = (Via1.PortBOutput & 0x3F) / 63f;
            Audio.Tick(Speaker, dac, dac);
        }

        _paddleTime += units;
        while (_paddleTime >= PaddlePeriod)
        {
            _paddleTime -= PaddlePeriod;
            TickPaddles();
        }

        if (_keyDelay > 0 && (_keyDelay -= units) <= 0)
        {
            _keyDelay = 0;
            if (_strobe == 0) { DeliverKey(); }
        }

        if (_beepToggles > 0)
        {
            _beepTime += units;
            while (_beepTime >= BeepPeriod && _beepToggles > 0)
            {
                _beepTime -= BeepPeriod;
                Speaker = !Speaker;
                _beepToggles--;
            }
        }

        // VIA 1 PA7 reads the combined interrupt line, active low.
        bool irq = InterruptRequested;
        byte portA = irq ? (byte)(Via1.PortAInput & ~0x80) : (byte)(Via1.PortAInput | 0x80);
        if (portA != Via1.PortAInput) { Via1.PortAInput = portA; }
    }

    /// <summary>
    ///  Clocks the disk controller for one CPU cycle. Its sequencer runs from the same clocks as the CPU, two steps to
    ///  a 1 MHz cycle and one to a 2 MHz cycle, which keeps the CPU's writes in step with it, as SOS's disk driver,
    ///  run at 1 MHz, needs.
    /// </summary>
    /// <param name="slow">Whether the cycle was a 1 MHz one.</param>
    public void TickDisk(bool slow)
    {
        if (slow)
        {
            Disk.Tick();
        }
        else
        {
            Disk.HalfTick();
        }
    }

    /// <inheritdoc/>
    public byte ReadOpcode(ushort address)
    {
        _extendedBank = 0;
        _sync = true;
        byte value = Read(address);
        _sync = false;
        return value;
    }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if ((_extendedBank & 0x80) != 0 && address >= 0x100)
        {
            return _ram[ExtendedOffset(address)];
        }

        switch (address)
        {
            case < 0x100:
                byte value = _ram[_zeroPageBase + address];
                if (!_sync && ZeroPage is >= 0x18 and <= 0x1F)
                {
                    _extendedBank = (byte)(_ram[_system + (((ZeroPage << 8) | address) ^ 0x0C00)] & 0x8F);
                }

                return value;
            case < 0x200:
                return _ram[_stackBase + (address & 0xFF)];
            case < 0x2000:
                return _ram[_system + address];
            case < 0xA000:
                return _ram[_bankBase + address - 0x2000];
            case < 0xC000:
                return _ram[_system + address - 0x8000];
            case < 0xC100:
                return (Environment & IoEnable) != 0 ? ReadIo((byte)address) : _ram[_system + address - 0x8000];
            case < 0xC500:
                return (Environment & IoEnable) != 0 ? ReadSlotRom(address) : _ram[_system + address - 0x8000];
            case < 0xC800:
                return _ram[_system + address - 0x8000];
            case < 0xD000:
                return (Environment & IoEnable) != 0 ? ReadExpansionRom(address) : _ram[_system + address - 0x8000];
            case < 0xF000:
                return _ram[_system + address - 0x8000];
            case >= 0xF000 when _inhibitors.Length != 0 && Inhibitor(address) is { } inhibitor:
                return inhibitor.ReadInhibited(address);
            case >= 0xFFC0 and < 0xFFD0:
                return _ram[_system + address - 0x8000];
            case >= 0xFFD0 and < 0xFFF0 when (BankRegister & ViasVisible) != 0:
                return (address < 0xFFE0 ? Via0 : Via1).Read((byte)address);
            default:
                return (Environment & RomEnable) != 0 ? _rom[address - 0xF000] : _ram[_system + address - 0x8000];
        }
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if ((_extendedBank & 0x80) != 0 && address >= 0x100)
        {
            _ram[ExtendedOffset(address)] = value;
            return;
        }

        switch (address)
        {
            case < 0x100:
                _ram[_zeroPageBase + address] = value;
                return;
            case < 0x200:
                _ram[_stackBase + (address & 0xFF)] = value;
                return;
            case < 0x2000:
                _ram[_system + address] = value;
                return;
            case < 0xA000:
                _ram[_bankBase + address - 0x2000] = value;
                return;
            case < 0xC000:
                _ram[_system + address - 0x8000] = value;
                return;
            case < 0xC100 when (Environment & IoEnable) != 0:
                WriteIo((byte)address, value);
                return;
            case < 0xC500 when (Environment & IoEnable) != 0:
                SelectExpansion(address);
                return;
            case >= 0xC800 and < 0xD000 when (Environment & IoEnable) != 0:
                if (address == 0xCFFF) { _expansionSlot = 0; }
                return;
            case >= 0xFFD0 and < 0xFFF0 when (BankRegister & ViasVisible) != 0:
                (address < 0xFFE0 ? Via0 : Via1).Write((byte)address, value);
                UpdateRegisters();
                return;
            default:
                if ((Environment & WriteProtect) == 0)
                {
                    _ram[_system + address - 0x8000] = value;
                }

                return;
        }
    }

    /// <summary>
    ///  Reads what the CPU would see at an address, without side effects and without extended addressing.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address) => ReadArea(address) switch
    {
        Apple3MemoryArea.Io => PeekIo((byte)address),
        Apple3MemoryArea.Vias => (address < 0xFFE0 ? Via0 : Via1).Peek((byte)address),
        Apple3MemoryArea.Rom => _rom[address - 0xF000],
        Apple3MemoryArea.None => 0xFF,
        _ => _ram[RamOffset(address)]
    };

    /// <summary>
    ///  Gets what backs a CPU address, without extended addressing.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The area.</returns>
    public Apple3MemoryArea ReadArea(ushort address)
    {
        bool io = (Environment & IoEnable) != 0;
        return address switch
        {
            < 0x100 => AreaOf(_zeroPageBase),
            < 0x200 => AreaOf(_stackBase),
            >= 0x2000 and < 0xA000 => AreaOf(_bankBase),
            < 0xC100 and >= 0xC000 when io => Apple3MemoryArea.Io,
            (< 0xC500 and >= 0xC100) or (>= 0xC800 and < 0xD000) when io => Apple3MemoryArea.None,
            >= 0xFFC0 and < 0xFFD0 => Apple3MemoryArea.SystemBank,
            >= 0xFFD0 and < 0xFFF0 when (BankRegister & ViasVisible) != 0 => Apple3MemoryArea.Vias,
            >= 0xF000 when (Environment & RomEnable) != 0 => Apple3MemoryArea.Rom,
            _ => Apple3MemoryArea.SystemBank
        };
    }

    /// <summary>
    ///  Gets the offset in <see cref="Ram"/> that a CPU address reads, when RAM backs it.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The offset.</returns>
    public int RamOffset(ushort address) => address switch
    {
        < 0x100 => _zeroPageBase + address,
        < 0x200 => _stackBase + (address & 0xFF),
        < 0x2000 => _system + address,
        < 0xA000 => _bankBase + address - 0x2000,
        _ => _system + address - 0x8000
    };

    /// <summary>
    ///  Gets the number of switchable banks: 3 with 128K, 7 with 256K, 15 with 512K.
    /// </summary>
    public int SwitchableBanks => _switchableBanks;

    /// <summary>
    ///  Gets the offset in <see cref="Ram"/> of the stack page in use, wherever the zero-page register and the
    ///  environment put it.
    /// </summary>
    public int StackOffset => _stackBase;

    /// <summary>
    ///  Gets the offset in <see cref="Ram"/> of an address seen through an X-byte.
    /// </summary>
    /// <param name="xByte">The X-byte, <c>$80-$8F</c>.</param>
    /// <param name="address">The address, <c>$0100</c> or above.</param>
    /// <returns>The offset.</returns>
    public int ExtendedOffset(byte xByte, ushort address)
    {
        int bank = xByte & _bankMask;
        if (bank == _bankMask)
        {
            // The all-ones bank (SOS's $8F) is the system bank as the CPU sees it, including the RAM under the
            // VIAs, with bank 0 at $2000.
            return address switch
            {
                < 0x2000 => _system + address,
                < 0xA000 => address - 0x2000,
                _ => _system + address - 0x8000
            };
        }

        // Bank N below $8000 and N + 1 above, the last switchable bank's partner wrapping to bank 0.
        bank %= _switchableBanks;
        return address < 0x8000
            ? (bank * 0x8000) + address
            : ((bank + 1) % _switchableBanks * 0x8000) + address - 0x8000;
    }

    private int ExtendedOffset(ushort address) => ExtendedOffset(_extendedBank, address);

    /// <summary>
    ///  Gets the memory area a bank register value switches in at <c>$2000-$9FFF</c>.
    /// </summary>
    /// <param name="bank">The bank register's value; its low bits are the bank.</param>
    /// <returns>The bank's area.</returns>
    public Apple3MemoryArea BankArea(byte bank) => AreaOf(BankOffset(bank));

    /// <summary>
    ///  Reads a byte at <c>$2000-$9FFF</c> in a bank, whichever bank is switched in.
    /// </summary>
    /// <param name="bank">The bank register value that switches the bank in.</param>
    /// <param name="address">The address, <c>$2000-$9FFF</c>.</param>
    /// <returns>The byte.</returns>
    public byte PeekBank(byte bank, ushort address)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(address, (ushort)0x2000);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(address, (ushort)0x9FFF);
        return _ram[BankOffset(bank) + address - 0x2000];
    }

    private Apple3MemoryArea AreaOf(int offset) =>
        offset >= _system ? Apple3MemoryArea.SystemBank : Apple3MemoryArea.Bank0 + (offset / 0x8000);

    // The offset in RAM of the bank the bank register names at $2000. The all-ones bank is bank 0 there, alongside
    // the system RAM; other numbers wrap at the number of switchable banks.
    private int BankOffset(int bank)
    {
        bank &= _bankMask;
        return bank == _bankMask ? 0 : bank % _switchableBanks * 0x8000;
    }

    /// <summary>
    ///  Gets whether the machine is in Apple II emulation mode: VIA 1 port A bit 6, the mode trap, is low, so the VIAs no
    ///  longer answer at <c>$FFD0-$FFEF</c> and nothing but a power cycle can change the environment again.
    /// </summary>
    public bool AppleIIMode => (BankRegister & ViasVisible) == 0;

    private void UpdateRegisters()
    {
        Environment = Via0.PortAOutput;
        ZeroPage = Via0.PortBOutput;
        BankRegister = Via1.PortAOutput;
        _bankBase = BankOffset(BankRegister);
        _zeroPageBase = PageOffset(ZeroPage);
        _stackBase = (Environment & PrimaryStack) != 0 ? _system + 0x100 : PageOffset((byte)(ZeroPage ^ 1));
    }

    // Where a 64K page lands: the system bank below $2000 and from $A000, the switchable bank between.
    private int PageOffset(byte page) => page switch
    {
        < 0x20 => _system + (page << 8),
        >= 0xA0 => _system + (page << 8) - 0x8000,
        _ => _bankBase + (page << 8) - 0x2000
    };

    private void DeliverKey()
    {
        if (!_keys.TryDequeue(out (byte Code, bool Shifted) key)) { return; }
        _key = key.Code;
        _keyShifted = key.Shifted;
        _strobe = 0x80;

        // The encoder's data-ready line, on VIA 1's CA2.
        Via1.CA2 = true;
        Via1.CA2 = false;
    }

    private byte KeyModifiers()
    {
        int value = 0x7C | (_key & 0x80) | (_strobe != 0 ? 1 : 0);
        if ((Modifiers & Apple3Modifiers.Shift) != 0 || (_keyShifted && _strobe != 0)) { value |= 0x02; }
        if ((Modifiers & Apple3Modifiers.Control) != 0) { value &= ~0x04; }
        if ((Modifiers & Apple3Modifiers.AlphaLock) != 0) { value &= ~0x08; }
        if ((Modifiers & Apple3Modifiers.OpenApple) != 0) { value &= ~0x10; }
        if ((Modifiers & Apple3Modifiers.SolidApple) != 0) { value &= ~0x20; }
        return (byte)value;
    }

    // The card that inhibits a read at an address, if any.
    private IApple3Card? Inhibitor(ushort address)
    {
        foreach (IApple3Card card in _inhibitors)
        {
            if (card.InhibitsRead(address)) { return card; }
        }

        return null;
    }

    // A read of a slot's ROM page selects its expansion ROM.
    private byte ReadSlotRom(ushort address)
    {
        SelectExpansion(address);
        return _slots[(address >> 8) & 7] is { } card ? card.ReadRom(address & 0xFF) : (byte)0xFF;
    }

    private void SelectExpansion(ushort address)
    {
        int slot = (address >> 8) & 7;
        if (_slots[slot] is { HasExpansionRom: true }) { _expansionSlot = slot; }
    }

    // $CFFF deselects every card's expansion ROM.
    private byte ReadExpansionRom(ushort address)
    {
        byte value = _slots[_expansionSlot] is { } card ? card.ReadExpansionRom(address - 0xC800) : (byte)0xFF;
        if (address == 0xCFFF) { _expansionSlot = 0; }
        return value;
    }

    private byte ReadIo(byte offset)
    {
        switch (offset)
        {
            case >= 0x90 and < 0xD0:
                return _slots[(offset >> 4) - 8] is { } card ? card.ReadIo(offset & 0x0F) : (byte)0xFF;
            case < 0x08:
                return (byte)((_key & 0x7F) | _strobe);
            case < 0x10:
                return KeyModifiers();
            case < 0x20:
                ClearStrobe();
                return 0xFF;
            case >= 0xE0 and < 0xF0:
                byte latch = Disk.Read((byte)(offset & 0x0F), floatingBus: 0);
                DiskSwitch(offset);
                return latch;
            case >= 0x58 and < 0x60:
                Paddle(offset);
                return 0xFF;
            case >= 0x70 and < 0x80:
                return Clock.Read(ZeroPage);
            default:
                Switch(offset);
                return PeekIo(offset);
        }
    }

    private void WriteIo(byte offset, byte value)
    {
        switch (offset)
        {
            case >= 0x90 and < 0xD0:
                _slots[(offset >> 4) - 8]?.WriteIo(offset & 0x0F, value);
                break;
            case >= 0x10 and < 0x20:
                ClearStrobe();
                break;
            case >= 0xE0 and < 0xF0:
                Disk.Write((byte)(offset & 0x0F), value);
                DiskSwitch(offset);
                break;
            case >= 0x70 and < 0x80:
                Clock.Write(ZeroPage, value);
                break;
            case >= 0x58 and < 0x60:
                Paddle(offset);
                break;
            case >= 0xF0 and < 0xF4:
                Acia.Write(offset, value);
                break;
            default:
                Switch(offset);
                break;
        }
    }

    // The switches a read or a write throws alike.
    private void Switch(byte offset)
    {
        switch (offset)
        {
            case >= 0x30 and < 0x40:
                Speaker = !Speaker;
                break;
            case >= 0x40 and < 0x4E:
                _beepToggles = 200;
                break;
            case >= 0x50 and < 0x58:
                int bit = 1 << ((offset - 0x50) >> 1);
                VideoSwitches = (offset & 1) != 0 ? (byte)(VideoSwitches | bit) : (byte)(VideoSwitches & ~bit);
                break;
            case >= 0xD0 and < 0xD4:
                int select = 1 << ((offset >> 1) & 1);
                _driveSelect = (offset & 1) != 0 ? _driveSelect | select : _driveSelect & ~select;
                SelectDrive();
                break;
            case 0xD8 or 0xD9:
                SmoothScroll = (offset & 1) != 0;
                break;
            case 0xDA or 0xDB:
                CharacterWrite = (offset & 1) != 0;
                break;
        }
    }

    // $C0E0-$C0E5 also set the smooth-scroll offset; $C0EA and $C0EB pick the built-in or an external drive.
    private void DiskSwitch(byte offset)
    {
        switch (offset)
        {
            case < 0xE6:
                int bit = 1 << ((offset - 0xE0) >> 1);
                ScrollOffset = (offset & 1) != 0 ? ScrollOffset | bit : ScrollOffset & ~bit;
                break;
            case 0xEA or 0xEB:
                _externalDrive = offset == 0xEB;
                SelectDrive();
                break;
        }
    }

    private void SelectDrive() => Disk.SelectDrive(_externalDrive ? _driveSelect + 1 : 1);

    private byte PeekIo(byte offset) => offset switch
    {
        < 0x08 => (byte)((_key & 0x7F) | _strobe),
        < 0x10 => KeyModifiers(),
        0x60 or 0x68 => (Buttons & 1) != 0 ? (byte)0x80 : (byte)0,
        0x61 or 0x69 => (Buttons & 4) != 0 ? (byte)0x80 : (byte)0,
        0x62 or 0x6A => (Buttons & 2) != 0 ? (byte)0x80 : (byte)0,
        0x63 or 0x6B => (Buttons & 8) != 0 ? (byte)0x80 : (byte)0,
        0x64 or 0x65 or 0x6C or 0x6D => 0x80,                                   // no slot interrupt
        0x66 or 0x6E => _rampActive ? (byte)0x80 : (byte)0x00,
        >= 0x70 and < 0x80 => Clock.Read(ZeroPage),
        >= 0x90 and < 0xD0 => _slots[(offset >> 4) - 8] is { } card ? card.PeekIo(offset & 0x0F) : (byte)0xFF,
        >= 0xD0 and < 0xD8 => 0x00,
        >= 0xE0 and < 0xF0 => Disk.Peek((byte)(offset & 0x0F), floatingBus: 0),
        >= 0xF0 and < 0xF4 => Acia.Read(offset),
        _ => 0xFF
    };

    private void ClearStrobe()
    {
        _strobe = 0;

        // The next queued key comes a typist's beat later, not at once: SOS's console driver takes keys on VIA 1's
        // interrupt, and a key arriving inside its handler would have its flag cleared with the last one's.
        if (_keys.Count != 0 && _keyDelay == 0) { _keyDelay = KeyInterval; }
    }

    // The analog inputs: $C05C discharges the timing capacitor, $C05D starts the ramp, $C066 reads it running.
    private void Paddle(byte offset)
    {
        switch (offset)
        {
            case 0x58 or 0x59 or 0x5A or 0x5B or 0x5E or 0x5F:
                // Pairs select the analog input's bits 0, 2 and 1; odd addresses set them.
                int bit = offset switch { < 0x5A => 1, < 0x5C => 4, _ => 2 };
                _analogSelect = (offset & 1) != 0 ? _analogSelect | bit : _analogSelect & ~bit;
                break;
            case 0x5C:
                _rampActive = false;
                _paddleCharge = 0;
                _paddleTime = 0;
                break;
            case 0x5D:
                // The selected input's position charges the timing capacitor, as MAME models it: the first stick's X,
                // its Y upside down, then the second's.
                int position = _analogSelect switch
                {
                    1 => Joysticks[0],
                    2 => 255 - Joysticks[1],
                    4 => Joysticks[2],
                    5 => 255 - Joysticks[3],
                    _ => 127
                };

                if (_paddleCharge > 82) { _paddleCharge += (position * 7) - 100; }
                _paddleTime = 0;
                _rampActive = true;
                break;
        }
    }

    private void TickPaddles()
    {
        if (!_rampActive)
        {
            _paddleCharge++;
        }
        else if (--_paddleCharge <= 0)
        {
            _rampActive = false;
        }
    }
}
