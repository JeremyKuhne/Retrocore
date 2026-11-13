// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  An Apple II's memory, language card, read-sensitive switches, video, keyboard and slots.
/// </summary>
/// <remarks>
///  <para>
///   The IIe adds the IIe's own switches at $C000-$C00F (written) and $C011-$C01F (read), auxiliary memory, the
///   built-in $C100-$CFFF firmware with its slot 3 80-column firmware, and double hi-res. On the II Plus those
///   addresses are the keyboard's, the language card is a card in slot 0, and slot 3 takes a card like the others.
///  </para>
/// </remarks>
public sealed class Apple2Bus : IProcessorBus
{
    private const byte ControlC = 3;
    private readonly Apple2Roms _roms;
    private readonly bool _iie;

    // The first address past the board's RAM: $C000 with 48 KiB, the IIe's always.
    private ushort _ramTop = 0xC000;

    // The slot 0 firmware card's 12 KiB for $D000-$FFFF, and whether it answers there instead of the board's ROM.
    private byte[]? _firmwareCard;
    private bool _firmwareCardActive;
    private readonly byte[] _main = new byte[65536];
    private readonly byte[] _auxiliary = new byte[65536];
    private readonly byte[] _mainBank1 = new byte[4096];
    private readonly byte[] _auxiliaryBank1 = new byte[4096];
    private readonly byte[] _slot7 = new byte[256];
    private readonly Queue<byte> _keys = new();
    private readonly IBlockDevice? _disk;
    private bool _prewrite;
    private bool _internalC8;
    private byte _keyboard;

    // The game port's push buttons, read at $C061-$C063: the Open Apple and Closed Apple keys are buttons 0 and 1.
    private readonly bool[] _buttons = new bool[3];

    // The buttons down at the last reset, which read as down until the reset handler has had time to read them.
    private readonly bool[] _heldAtReset = new bool[3];
    private ulong _resetHoldEnd;
    private byte _diskError;
    private uint? _lastBlock;
    private bool _lastBlockWrite;
    private bool _blockWritten;
    private ulong _lastBlockCycle;

    // The Disk II card in each slot, by slot number; slot six's is DiskII. A card answers only once it has firmware.
    private readonly DiskIIController?[] _diskCards = new DiskIIController?[8];

    // The installed cards other than slot six's, which tick with it every cycle.
    private DiskIIController[] _otherCards = [];

    // The Z80 SoftCard, in any free slot.
    private SoftCard? _softCard;

    /// <summary>
    ///  Constructs a IIe's bus with externally supplied firmware and an optional slot-seven disk.
    /// </summary>
    /// <param name="roms">The firmware.</param>
    /// <param name="disk">The block device, or null for an empty slot.</param>
    public Apple2Bus(Apple2Roms roms, IBlockDevice? disk = null)
        : this(Apple2Model.IIeEnhanced, roms, disk)
    {
    }

    /// <summary>
    ///  Constructs a model's bus with externally supplied firmware and an optional slot-seven disk.
    /// </summary>
    /// <param name="model">The model, whose hardware the bus has.</param>
    /// <param name="roms">The firmware.</param>
    /// <param name="disk">The block device, or null for an empty slot.</param>
    public Apple2Bus(Apple2Model model, Apple2Roms roms, IBlockDevice? disk = null)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Model = model;
        _iie = model.IsIIe();
        LanguageCardInstalled = _iie;
        _roms = roms;
        _disk = disk;
        Video = new(this, roms);
        _diskCards[6] = DiskII;
        ResetSwitches();
        if (disk is not null) { CreateSlot7Rom(); }
    }

    /// <summary>
    ///  Gets the model whose hardware the bus has.
    /// </summary>
    public Apple2Model Model { get; }

    /// <summary>
    ///  Gets soft-switch state.
    /// </summary>
    public Apple2Switches Switches { get; private set; }

    /// <summary>
    ///  Gets the NTSC scanner and graphics renderer.
    /// </summary>
    public Apple2Video Video { get; }

    /// <summary>
    ///  Gets the slot-six floppy controller; card firmware is supplied separately by the caller.
    /// </summary>
    public DiskIIController DiskII { get; } = new();

    /// <summary>
    ///  Gets how many times a card has been put in or taken out, so a list of the machine's devices knows to change.
    /// </summary>
    public int CardChanges { get; private set; }

    /// <summary>
    ///  Gets the Disk II card in a slot.
    /// </summary>
    /// <param name="slot">The slot, 1 to 7.</param>
    /// <returns>The card, or null when the slot has none.</returns>
    /// <exception cref="ArgumentOutOfRangeException">There is no such slot.</exception>
    public DiskIIController? DiskIIIn(int slot)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(slot, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(slot, 7);
        return Card(slot);
    }

    /// <summary>
    ///  Gets whether a slot is free for a Disk II card or the Mockingboard: slots 1, 2, 5 and 6, 4 without the
    ///  Mockingboard, and 7 without the block device. Slot 3 is free on the II Plus; on the IIe its space is the
    ///  80-column firmware's.
    /// </summary>
    /// <param name="slot">The slot, 1 to 7.</param>
    /// <returns>Whether a card can go in.</returns>
    public bool IsSlotFree(int slot) => _softCard?.Slot != slot && slot switch
    {
        1 or 2 or 5 or 6 => Card(slot) is null,
        3 => !_iie && Card(3) is null,
        4 => !MockingboardInstalled && Card(4) is null,
        7 => _disk is null && Card(7) is null,
        _ => false
    };

    /// <summary>
    ///  Puts a Disk II card in a free slot. It answers at once: at $C080 plus 16 times the slot, and its boot ROM at
    ///  $Cn00, so <c>PR#</c> boots it, and the firmware's startup scan finds it after a reset.
    /// </summary>
    /// <param name="slot">The slot: 1 to 7, though 3 only on the II Plus.</param>
    /// <param name="firmware">The card's boot ROM and sequencer.</param>
    /// <returns>The card.</returns>
    /// <exception cref="InvalidOperationException">The slot is not free.</exception>
    public DiskIIController InstallDiskII(int slot, DiskIIFirmware firmware)
    {
        ArgumentNullException.ThrowIfNull(firmware);
        if (slot is < 1 or > 7 || !IsSlotFree(slot))
        {
            throw new InvalidOperationException($"Slot {slot} is not free for a card.");
        }

        DiskIIController card = slot == 6 ? DiskII : new();
        card.SetFirmware(firmware);
        _diskCards[slot] = card;
        CardsChanged();
        return card;
    }

    /// <summary>
    ///  Takes the Disk II card out of a slot, ejecting its disks.
    /// </summary>
    /// <param name="slot">The slot.</param>
    /// <exception cref="InvalidOperationException">The slot has no Disk II card.</exception>
    public void RemoveDiskII(int slot)
    {
        DiskIIController card = (slot is >= 1 and <= 7 ? Card(slot) : null)
            ?? throw new InvalidOperationException($"Slot {slot} has no Disk II card.");

        card.RemoveFirmware();
        if (slot != 6) { _diskCards[slot] = null; }
        CardsChanged();
    }

    // The SoftCard when an address is in its $Cn00-$CnFF page and the IIe's firmware is not answering there.
    private SoftCard? SoftCardPage(ushort address) =>
        _softCard is { } card && address >> 8 == 0xC0 + card.Slot && !InternalRom(address) ? card : null;

    private DiskIIController? Card(int slot) => _diskCards[slot] is { IsInstalled: true } card ? card : null;

    private void CardsChanged()
    {
        List<DiskIIController> others = [];
        for (int slot = 1; slot <= 7; slot++)
        {
            if (slot != 6 && Card(slot) is { } card) { others.Add(card); }
        }

        _otherCards = [.. others];
        CardChanges++;
    }

    /// <summary>
    ///  Gets the two-VIA/two-AY Mockingboard, which answers in slot 4 while <see cref="MockingboardInstalled"/>.
    /// </summary>
    public Mockingboard Mockingboard { get; } = new();

    /// <summary>
    ///  Gets whether the Mockingboard is in slot 4. It is out until <see cref="InstallMockingboard"/> puts it in.
    /// </summary>
    public bool MockingboardInstalled { get; private set; }

    /// <summary>
    ///  Puts the Mockingboard in slot 4, reset. It answers at once at $C400-$C4FF.
    /// </summary>
    /// <exception cref="InvalidOperationException">Slot 4 is not free.</exception>
    public void InstallMockingboard()
    {
        if (!IsSlotFree(4)) { throw new InvalidOperationException("Slot 4 is not free for a card."); }
        Mockingboard.Reset();
        MockingboardInstalled = true;
        CardChanges++;
    }

    /// <summary>
    ///  Takes the Mockingboard out of slot 4, silencing it and dropping its interrupt.
    /// </summary>
    /// <exception cref="InvalidOperationException">Slot 4 has no Mockingboard.</exception>
    public void RemoveMockingboard()
    {
        if (!MockingboardInstalled) { throw new InvalidOperationException("Slot 4 has no Mockingboard."); }
        MockingboardInstalled = false;
        Mockingboard.Reset();
        CardChanges++;
    }

    /// <summary>
    ///  Gets the Z80 SoftCard, or null when none is installed.
    /// </summary>
    public SoftCard? SoftCard => _softCard;

    /// <summary>
    ///  Puts a Z80 SoftCard in a free slot, off, with its Z80 to start from zero at the first switch.
    /// </summary>
    /// <param name="slot">The slot: 1 to 7, though 3 only on the II Plus.</param>
    /// <returns>The card.</returns>
    /// <exception cref="InvalidOperationException">
    ///  The slot is not free, or a SoftCard is already installed.
    /// </exception>
    public SoftCard InstallSoftCard(int slot)
    {
        if (_softCard is not null || slot is < 1 or > 7 || !IsSlotFree(slot))
        {
            throw new InvalidOperationException($"Slot {slot} is not free for a SoftCard.");
        }

        _softCard = new(this, slot);
        CardChanges++;
        return _softCard;
    }

    /// <summary>
    ///  Takes the SoftCard out. The 6502 gets the bus back if the Z80 had it.
    /// </summary>
    /// <exception cref="InvalidOperationException">No SoftCard is installed.</exception>
    public void RemoveSoftCard()
    {
        if (_softCard is null) { throw new InvalidOperationException("No SoftCard is installed."); }
        _softCard = null;
        CardChanges++;
    }

    /// <summary>
    ///  Gets cycle-stamped stereo speaker/Mockingboard resampling. A caller-owned sink enables output.
    /// </summary>
    public Apple2Audio Audio { get; } = new();

    /// <summary>
    ///  Gets whether the language card's 16 KiB is there: built into the IIe, a card in slot 0 of the II Plus.
    ///  Without it, $D000-$FFFF is always ROM and $C080-$C08F do nothing.
    /// </summary>
    public bool LanguageCardInstalled { get; private set; }

    /// <summary>
    ///  Gets or sets how much RAM a II or II Plus's board has at $0000-$BFFF: 16, 32 or 48 KiB. Past it, reads see
    ///  the floating bus and writes go nowhere. The IIe always has 48 KiB.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">The size is not 16, 32 or 48, or is not 48 on a IIe.</exception>
    public int RamKilobytes
    {
        get => _ramTop / 1024;
        set
        {
            if (value is not (16 or 32 or 48) || (_iie && value != 48))
            {
                throw new ArgumentOutOfRangeException(nameof(value), "The II and II Plus have 16, 32 or 48 KiB; the IIe 48.");
            }

            _ramTop = (ushort)(value * 1024);
        }
    }

    /// <summary>
    ///  Gets whether slot 0 of a II or II Plus is empty, free for the language card or a firmware card.
    /// </summary>
    public bool IsSlot0Free => !_iie && !LanguageCardInstalled && _firmwareCard is null;

    /// <summary>
    ///  Gets whether slot 0 has a firmware card: the other model's BASIC and Monitor, AppleSoft on a II and Integer
    ///  BASIC on a II Plus, in 12 KiB of ROM that answers at $D000-$FFFF in place of the board's.
    /// </summary>
    public bool FirmwareCardInstalled => _firmwareCard is not null;

    /// <summary>
    ///  Gets whether the firmware card's ROM answers at $D000-$FFFF. Any access to $C080 (or another even address
    ///  up to $C08E) selects it, and to $C081 (or another odd one) the board's ROM, as DOS 3.3 does to find a BASIC.
    /// </summary>
    public bool FirmwareCardActive => _firmwareCard is not null && _firmwareCardActive;

    /// <summary>
    ///  Puts a firmware card in a II or II Plus's slot 0.
    /// </summary>
    /// <param name="rom">The card's 12 KiB of ROM for $D000-$FFFF.</param>
    /// <param name="active">
    ///  Whether its ROM answers at power-on and reset, as the card's switch is set: up for the card's BASIC.
    /// </param>
    /// <exception cref="InvalidOperationException">Slot 0 is not free.</exception>
    /// <exception cref="ArgumentException">The ROM is not 12 KiB.</exception>
    public void InstallFirmwareCard(ReadOnlySpan<byte> rom, bool active = true)
    {
        if (!IsSlot0Free) { throw new InvalidOperationException("Slot 0 is not free for a card."); }
        if (rom.Length != 0x3000) { throw new ArgumentException("A firmware card holds 12 KiB.", nameof(rom)); }
        _firmwareCard = rom.ToArray();
        _firmwareCardActive = active;
        FirmwareCardSwitchUp = active;
        CardChanges++;
    }

    /// <summary>
    ///  Takes the firmware card out of slot 0, so $D000-$FFFF reads the board's ROM again.
    /// </summary>
    /// <exception cref="InvalidOperationException">Slot 0 has no firmware card.</exception>
    public void RemoveFirmwareCard()
    {
        if (_firmwareCard is null) { throw new InvalidOperationException("Slot 0 has no firmware card."); }
        _firmwareCard = null;
        CardChanges++;
    }

    // The firmware card's switch: whether its ROM answers after a reset.
    private bool FirmwareCardSwitchUp { get; set; }

    /// <summary>
    ///  Puts a language card in a II or II Plus's slot 0, reading ROM and write-protected as at power-on.
    /// </summary>
    /// <exception cref="InvalidOperationException">Slot 0 is not free, or the language card is built in.</exception>
    public void InstallLanguageCard()
    {
        if (!IsSlot0Free) { throw new InvalidOperationException("Slot 0 is not free for a card."); }
        LanguageCardInstalled = true;
        ResetLanguageCard();
        CardChanges++;
    }

    /// <summary>
    ///  Takes the language card out of a II or II Plus's slot 0, so $D000-$FFFF reads the ROM again.
    /// </summary>
    /// <exception cref="InvalidOperationException">There is no language card, or it is the IIe's own.</exception>
    public void RemoveLanguageCard()
    {
        if (_iie) { throw new InvalidOperationException("The IIe's language card is built in."); }
        if (!LanguageCardInstalled) { throw new InvalidOperationException("Slot 0 has no language card."); }
        LanguageCardInstalled = false;
        ResetLanguageCard();
        CardChanges++;
    }

    /// <summary>
    ///  Gets whether language-card reads select RAM.
    /// </summary>
    public bool LanguageCardRead { get; private set; }

    /// <summary>
    ///  Gets whether language-card writes are enabled.
    /// </summary>
    public bool LanguageCardWrite { get; private set; }

    /// <summary>
    ///  Gets whether language-card bank two is selected.
    /// </summary>
    public bool LanguageCardBank2 { get; private set; }

    /// <summary>
    ///  Gets the number of elapsed machine clock cycles.
    /// </summary>
    public ulong CycleCount { get; private set; }

    /// <summary>
    ///  Gets the scanline within the 262-line NTSC frame.
    /// </summary>
    public int Scanline => (int)(CycleCount / 65 % 262);

    /// <summary>
    ///  Gets the column clock within the 65-cycle scanline.
    /// </summary>
    public int ColumnClock => (int)(CycleCount % 65);

    /// <summary>
    ///  Gets main RAM without memory-map side effects.
    /// </summary>
    public ReadOnlySpan<byte> MainMemory => _main;

    /// <summary>
    ///  Gets auxiliary RAM without memory-map side effects.
    /// </summary>
    public ReadOnlySpan<byte> AuxiliaryMemory => _auxiliary;

    /// <summary>
    ///  Copies a physical 64 KiB RAM bank without changing mapping or language-card latches.
    ///  Layout is low 48 KiB, D000 bank one, D000 bank two, and the shared E000-FFFF area.
    /// </summary>
    /// <param name="auxiliary">Whether to copy auxiliary RAM.</param>
    /// <param name="destination">Exactly 65536 destination bytes.</param>
    public void CopyPhysicalRam(bool auxiliary, Span<byte> destination)
    {
        if (destination.Length != 65536)
        {
            throw new ArgumentException("A 64 KiB destination is required.", nameof(destination));
        }

        ReadOnlySpan<byte> memory = auxiliary ? _auxiliary : _main;
        memory[..0xC000].CopyTo(destination);
        (auxiliary ? _auxiliaryBank1 : _mainBank1).CopyTo(destination[0xC000..0xD000]);
        memory[0xD000..0xE000].CopyTo(destination[0xD000..0xE000]);
        memory[0xE000..].CopyTo(destination[0xE000..]);
    }

    /// <summary>
    ///  Gets the speaker toggle state.
    /// </summary>
    public bool Speaker { get; private set; }

    /// <summary>
    ///  Resets memory-map controls without erasing RAM.
    /// </summary>
    public void ResetSwitches()
    {
        Switches = Apple2Switches.Text;
        ResetLanguageCard();
        _internalC8 = false;
    }

    private void ResetLanguageCard()
    {
        _firmwareCardActive = FirmwareCardSwitchUp;
        LanguageCardRead = false;
        LanguageCardWrite = false;
        LanguageCardBank2 = true;
        _prewrite = false;
    }

    /// <summary>
    ///  Captures the current video fetch if necessary, then advances the device clock by one cycle.
    ///  Apple2Machine captures before the CPU access; direct bus callers should do the same for raster timing.
    /// </summary>
    public void Tick()
    {
        Video.ScanCycle();
        DiskII.Tick();
        foreach (DiskIIController card in _otherCards) { card.Tick(); }
        if (MockingboardInstalled) { Mockingboard.Tick(); }
        Audio.Tick(Speaker, Mockingboard);
        CycleCount++;
    }

    /// <summary>
    ///  Resets peripheral control state without removing media or clearing machine RAM.
    /// </summary>
    public void ResetDevices()
    {
        DiskII.Reset();
        foreach (DiskIIController card in _otherCards) { card.Reset(); }
        Mockingboard.Reset();
        _softCard?.Reset();
        Audio.Reset();
        Speaker = false;
    }

    /// <summary>
    ///  Gets the game port's paddles and the controller buttons that join the keyboard's.
    /// </summary>
    public Apple2GamePort GamePort { get; } = new();

    /// <summary>
    ///  Presses or releases a game-port push button. The keyboard's Open Apple key is button 0 and its Closed
    ///  Apple key button 1; button 2 is the game port's third input.
    /// </summary>
    /// <param name="button">0, 1 or 2.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void SetButton(int button, bool pressed)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(button);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(button, 2);
        _buttons[button] = pressed;
    }

    /// <summary>
    ///  Gets how long the buttons down at a reset stay down: a tenth of a second of the machine's time.
    /// </summary>
    public const ulong ResetHoldCycles = 102_273;

    /// <summary>
    ///  Keeps the buttons that are down now down for <see cref="ResetHoldCycles"/> more cycles, however soon they are
    ///  released.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The IIe's reset handler reads Open Apple and Closed Apple to choose a restart or the self-test, some time
    ///   after it starts. Real fingers are still on the keys then; a debugger that stops at the handler's first
    ///   instruction lets them go first. The hold counts the machine's cycles, so time stopped does not use it up.
    ///  </para>
    /// </remarks>
    public void HoldButtonsThroughReset()
    {
        _buttons.CopyTo(_heldAtReset, 0);
        _resetHoldEnd = CycleCount + ResetHoldCycles;
    }

    /// <summary>
    ///  Queues a seven-bit keyboard character.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Keys wait in order until the program takes each one, so typed text arrives whole. CONTROL-C does not wait:
    ///   BASIC and the Monitor look for it in the latch without taking other keys, so it replaces the latched key
    ///   and the queue, as a key pressed on the real keyboard replaces the one latched.
    ///  </para>
    ///  <para>
    ///   The II Plus's keyboard has no lowercase, so a lowercase letter arrives as its capital.
    ///  </para>
    /// </remarks>
    /// <param name="character">The character code.</param>
    public void QueueKey(byte character)
    {
        if (character > 127) { throw new ArgumentOutOfRangeException(nameof(character)); }
        if (!_iie && character is >= (byte)'a' and <= (byte)'z') { character -= 32; }
        if (character == ControlC)
        {
            _keys.Clear();
            _keyboard = ControlC | 128;
            return;
        }

        _keys.Enqueue(character);
        LatchKey();
    }

    /// <summary>
    ///  Gets how many typed keys the program has not taken yet: those queued, and one latched with its strobe set.
    /// </summary>
    public int KeysWaiting => _keys.Count + ((_keyboard & 128) != 0 ? 1 : 0);

    /// <summary>
    ///  Gets the firmware the bus was built with.
    /// </summary>
    public Apple2Roms Roms => _roms;

    /// <summary>
    ///  Reads logical memory without triggering soft switches or consuming keyboard input.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The mapped byte.</returns>
    public byte Peek(ushort address) => ReadCore(address, sideEffects: false);

    /// <summary>
    ///  Gets the storage a read of an address uses under the current memory map, without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The memory area that supplies the byte <see cref="Peek"/> returns.</returns>
    public Apple2MemoryArea ReadArea(ushort address)
    {
        if (address < 0xC000)
        {
            if (address >= _ramTop) { return Apple2MemoryArea.None; }
            return ReferenceEquals(Ram(address, write: false), _auxiliary) ? Apple2MemoryArea.AuxiliaryRam : Apple2MemoryArea.MainRam;
        }

        if (address < 0xC100) { return Apple2MemoryArea.Io; }
        if (address >= 0xD000)
        {
            return LanguageCardRead ? LanguageCardArea(address) : Apple2MemoryArea.SystemRom;
        }

        if (InternalRom(address)) { return Apple2MemoryArea.SystemRom; }
        if (address >= 0xC800) { return Apple2MemoryArea.None; }
        int slot = (address >> 8) & 7;
        bool driven = slot switch
        {
            4 => MockingboardInstalled || Card(4) is not null,
            7 => _disk is not null || Card(7) is not null,
            _ => Card(slot) is not null
        };

        return driven ? Apple2MemoryArea.Slot1Rom + (slot - 1) : Apple2MemoryArea.None;
    }

    /// <summary>
    ///  Gets the storage a write to an address reaches under the current memory map, without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>
    ///  The memory area the byte goes to: <see cref="Apple2MemoryArea.None"/> where a write changes nothing, such as
    ///  ROM with the language card's RAM write-protected.
    /// </returns>
    public Apple2MemoryArea WriteArea(ushort address)
    {
        if (address < 0xC000)
        {
            if (address >= _ramTop) { return Apple2MemoryArea.None; }
            return ReferenceEquals(Ram(address, write: true), _auxiliary) ? Apple2MemoryArea.AuxiliaryRam : Apple2MemoryArea.MainRam;
        }

        if (address < 0xC100) { return Apple2MemoryArea.Io; }
        if (address >= 0xD000) { return LanguageCardWrite ? LanguageCardArea(address) : Apple2MemoryArea.None; }
        return address is >= 0xC400 and < 0xC500 && MockingboardInstalled && !InternalRom(address)
            ? Apple2MemoryArea.Slot4Rom
            : Apple2MemoryArea.None;
    }

    /// <summary>
    ///  Reads one memory area's storage directly, whatever the memory map.
    /// </summary>
    /// <param name="area">
    ///  The area: main or auxiliary RAM at $0000-$BFFF, language-card RAM at $D000-$FFFF (bank one at
    ///  $D000-$DFFF), the system ROM at $C100-$FFFF, or slot six's or seven's ROM when the slot has one.
    /// </param>
    /// <param name="address">The CPU address the byte answers at when the area is mapped.</param>
    /// <param name="value">The byte.</param>
    /// <returns>Whether the area holds a byte at that address.</returns>
    public bool PeekArea(Apple2MemoryArea area, ushort address, out byte value)
    {
        if (area == Apple2MemoryArea.SystemRom)
        {
            bool system = address >= (_iie ? 0xC100 : 0xD000);
            value = system ? SystemRom(address) : (byte)0;
            return system;
        }

        // A slot's ROM page: its Disk II card's boot ROM, or slot seven's block device firmware.
        if (area is >= Apple2MemoryArea.Slot1Rom and <= Apple2MemoryArea.Slot7Rom and not Apple2MemoryArea.Slot4Rom)
        {
            int slot = area - Apple2MemoryArea.Slot1Rom + 1;
            bool page = address >> 8 == (0xC0 | slot);
            if (page && Card(slot) is { BootRom.Length: 256 } card)
            {
                value = card.BootRom[address & 255];
                return true;
            }

            if (page && slot == 7 && _disk is not null)
            {
                value = _slot7[address & 255];
                return true;
            }

            value = 0;
            return false;
        }

        if (Storage(area, address) is not { } storage)
        {
            value = 0;
            return false;
        }

        value = storage.Memory[storage.Offset];
        return true;
    }

    /// <summary>
    ///  Writes one RAM area's storage directly, whatever the memory map.
    /// </summary>
    /// <param name="area">The RAM area, as <see cref="PeekArea"/> takes it.</param>
    /// <param name="address">The CPU address the byte answers at when the area is mapped.</param>
    /// <param name="value">The byte.</param>
    /// <returns>Whether the area is RAM holding a byte at that address.</returns>
    public bool PokeArea(Apple2MemoryArea area, ushort address, byte value)
    {
        if (Storage(area, address) is not { } storage) { return false; }
        storage.Memory[storage.Offset] = value;
        return true;
    }

    /// <summary>
    ///  Writes physical main or auxiliary RAM, bypassing I/O and ROM mapping.
    /// </summary>
    /// <param name="auxiliary">Whether to write auxiliary RAM.</param>
    /// <param name="address">The RAM address.</param>
    /// <param name="value">The byte.</param>
    public void SetRam(bool auxiliary, ushort address, byte value) => (auxiliary ? _auxiliary : _main)[address] = value;

    // The array and index that hold a RAM area's byte at a CPU address, or null where the area has none.
    private (byte[] Memory, int Offset)? Storage(Apple2MemoryArea area, ushort address) => area switch
    {
        Apple2MemoryArea.MainRam when address < 0xC000 => (_main, address),
        Apple2MemoryArea.AuxiliaryRam when address < 0xC000 => (_auxiliary, address),
        Apple2MemoryArea.MainLanguageCard when address >= 0xD000 => (_main, address),
        Apple2MemoryArea.AuxiliaryLanguageCard when address >= 0xD000 => (_auxiliary, address),
        Apple2MemoryArea.MainLanguageCardBank1 when address is >= 0xD000 and < 0xE000 => (_mainBank1, address - 0xD000),
        Apple2MemoryArea.AuxiliaryLanguageCardBank1 when address is >= 0xD000 and < 0xE000 => (_auxiliaryBank1, address - 0xD000),
        _ => null
    };

    // The language-card RAM an address at $D000-$FFFF uses under the current bank and zero-page switches.
    private Apple2MemoryArea LanguageCardArea(ushort address)
    {
        bool auxiliary = Has(Apple2Switches.AltZeroPage);
        bool bank1 = address < 0xE000 && !LanguageCardBank2;
        return (auxiliary, bank1) switch
        {
            (false, false) => Apple2MemoryArea.MainLanguageCard,
            (false, true) => Apple2MemoryArea.MainLanguageCardBank1,
            (true, false) => Apple2MemoryArea.AuxiliaryLanguageCard,
            (true, true) => Apple2MemoryArea.AuxiliaryLanguageCardBank1
        };
    }

    /// <inheritdoc/>
    public byte Read(ushort address) => ReadCore(address, sideEffects: true);

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address < 0xC000)
        {
            if (address < _ramTop) { Ram(address, write: true)[address] = value; }
        }
        else if (address is >= 0xC090 and < 0xC100 && Card((address >> 4) & 7) is { } card)
        {
            card.Write((byte)(address & 15), value);
        }
        else if (address < 0xC100)
        {
            AccessSwitch(address, write: true);
        }
        else if (SoftCardPage(address) is { } softCard)
        {
            softCard.Switch();
        }
        else if (address is >= 0xC400 and < 0xC500 && MockingboardInstalled && !InternalRom(address))
        {
            Mockingboard.Write((byte)address, value);
        }
        else if (address == 0xCFFF && _iie)
        {
            _internalC8 = false;
        }
        else if (address >= 0xD000 && LanguageCardWrite)
        {
            HighRam(address)[HighOffset(address)] = value;
        }
    }

    private byte ReadCore(ushort address, bool sideEffects)
    {
        if (address < 0xC000) { return address < _ramTop ? Ram(address, write: false)[address] : FloatingBus(); }
        if (address < 0xC100)
        {
            if (address >= 0xC090 && Card((address >> 4) & 7) is { } card)
            {
                return sideEffects ? card.Read((byte)(address & 15), FloatingBus())
                    : card.Peek((byte)(address & 15), FloatingBus());
            }

            if (sideEffects) { AccessSwitch(address, write: false); }
            if (address < 0xC010) { return _keyboard; }

            // The II Plus clears the keyboard strobe at $C010-$C01F and puts nothing on the bus; the IIe answers
            // with the latched key and a switch's state in bit 7.
            if (!_iie && address <= 0xC01F) { return FloatingBus(); }
            if (address == 0xC010)
            {
                return (byte)(_keyboard & 127);
            }

            if (address is >= 0xC011 and <= 0xC01F)
            {
                return (byte)((_keyboard & 127) | (Status(address) ? 128 : 0));
            }

            // A button reads in bit 7, held by the keyboard's Apple keys or a controller; the other bits are
            // whatever the bus last carried.
            if (address is >= 0xC061 and <= 0xC063)
            {
                int button = address - 0xC061;
                bool held = _heldAtReset[button] && CycleCount < _resetHoldEnd;
                return (byte)((FloatingBus() & 127) | (_buttons[button] || held || GamePort.Button(button) ? 128 : 0));
            }

            // A paddle's timer reads the same way: bit 7 stays high until it times out.
            if (address is >= 0xC064 and <= 0xC067)
            {
                return (byte)((FloatingBus() & 127) | (GamePort.Timing(address - 0xC064, CycleCount) ? 128 : 0));
            }

            if (address == 0xC0F0 && _disk is not null)
            {
                if (sideEffects) { DiskCommand(); }
                return _diskError;
            }

            return address == 0xC0F1 && _disk is not null
                ? (byte)_disk.BlockCount
                : address == 0xC0F2 && _disk is not null ? (byte)(_disk.BlockCount >> 8) : FloatingBus();
        }

        if (address >= 0xD000)
        {
            return LanguageCardRead ? HighRam(address)[HighOffset(address)] : SystemRom(address);
        }

        bool internalRom = InternalRom(address);
        if (sideEffects && _iie && address is >= 0xC300 and < 0xC400 && !Has(Apple2Switches.SlotC3Rom))
        {
            _internalC8 = true;
        }

        byte result;
        if (internalRom)
        {
            result = _roms.System[address - 0xC000];
        }
        else if (address is >= 0xC400 and < 0xC500 && MockingboardInstalled)
        {
            result = sideEffects ? Mockingboard.Read((byte)address) : Mockingboard.Peek((byte)address);
        }
        else if (address < 0xC800 && Card((address >> 8) & 7) is { } card)
        {
            result = card.BootRom[address & 255];
        }
        else
        {
            result = address is >= 0xC700 and < 0xC800 && _disk is not null ? _slot7[address & 255] : (byte)0xFF;
        }

        if (sideEffects && address == 0xCFFF) { _internalC8 = false; }
        return result;
    }

    // The ROM byte at $D000-$FFFF, or at $C100-$CFFF on the IIe: the firmware card's while it answers, else the
    // board's.
    private byte SystemRom(ushort address) => _firmwareCardActive && _firmwareCard is { } card && address >= 0xD000
        ? card[address - 0xD000]
        : _roms.System[address - 0xC000];

    // Whether $C100-$CFFF reads the IIe's built-in firmware: all of it with INTCXROM, slot 3's page unless
    // SLOTC3ROM, and $C800-$CFFF once slot 3's page has been read. The II Plus has none.
    private bool InternalRom(ushort address) => _iie
        && (Has(Apple2Switches.InternalCxRom)
            || (address is >= 0xC300 and < 0xC400 && !Has(Apple2Switches.SlotC3Rom))
            || (address >= 0xC800 && _internalC8));

    private byte[] Ram(ushort address, bool write)
    {
        bool auxiliary = address < 0x200 ? Has(Apple2Switches.AltZeroPage) : Has(write ? Apple2Switches.RamWrite : Apple2Switches.RamRead);
        if (Has(Apple2Switches.Store80)
            && (address is >= 0x400 and < 0x800 || (Has(Apple2Switches.HiRes) && address is >= 0x2000 and < 0x4000)))
        {
            auxiliary = Has(Apple2Switches.Page2);
        }

        return auxiliary ? _auxiliary : _main;
    }

    private byte[] HighRam(ushort address) => address < 0xE000 && !LanguageCardBank2
        ? Has(Apple2Switches.AltZeroPage) ? _auxiliaryBank1 : _mainBank1
        : Has(Apple2Switches.AltZeroPage) ? _auxiliary : _main;
    private int HighOffset(ushort address) => address < 0xE000 && !LanguageCardBank2 ? address - 0xD000 : address;
    private bool Has(Apple2Switches flag) => (Switches & flag) != 0;
    private bool Status(ushort address) => address switch
    {
        0xC011 => LanguageCardBank2, 0xC012 => LanguageCardRead,
        0xC013 => Has(Apple2Switches.RamRead), 0xC014 => Has(Apple2Switches.RamWrite),
        0xC015 => Has(Apple2Switches.InternalCxRom), 0xC016 => Has(Apple2Switches.AltZeroPage),
        0xC017 => Has(Apple2Switches.SlotC3Rom), 0xC018 => Has(Apple2Switches.Store80),
        0xC019 => Scanline < 192, 0xC01A => Has(Apple2Switches.Text),
        0xC01B => Has(Apple2Switches.Mixed), 0xC01C => Has(Apple2Switches.Page2),
        0xC01D => Has(Apple2Switches.HiRes), 0xC01E => Has(Apple2Switches.AlternateCharacters),
        0xC01F => Has(Apple2Switches.Column80), _ => false
    };

    private void AccessSwitch(ushort address, bool write)
    {
        if (address is >= 0xC080 and <= 0xC08F)
        {
            if (_firmwareCard is not null) { _firmwareCardActive = (address & 1) == 0; }
            if (!LanguageCardInstalled) { return; }
            bool odd = (address & 1) != 0;
            if (!odd)
            {
                LanguageCardWrite = false;
                _prewrite = false;
            }
            else if (write)
            {
                _prewrite = false;
            }
            else
            {
                if (_prewrite) { LanguageCardWrite = true; }
                _prewrite = true;
            }

            LanguageCardBank2 = (address & 8) == 0;
            LanguageCardRead = (address & 3) is 0 or 3;
            return;
        }

        if (address == 0xC010 || ((write || !_iie) && address is >= 0xC011 and <= 0xC01F))
        {
            _keyboard &= 127;
            LatchKey();
            return;
        }

        if (address is >= 0xC030 and <= 0xC03F)
        {
            Speaker = !Speaker;
            return;
        }

        // PTRIG: any access to $C070-$C07F starts the four paddle timers.
        if (address is >= 0xC070 and <= 0xC07F)
        {
            GamePort.Trigger(CycleCount);
            return;
        }

        // The rest are the IIe's own switches, but for the display's four pairs.
        if (!_iie && address is < 0xC050 or > 0xC057) { return; }
        Apple2Switches flag = address switch
        {
            0xC000 or 0xC001 when write => Apple2Switches.Store80,
            0xC002 or 0xC003 when write => Apple2Switches.RamRead,
            0xC004 or 0xC005 when write => Apple2Switches.RamWrite,
            0xC006 or 0xC007 when write => Apple2Switches.InternalCxRom,
            0xC008 or 0xC009 when write => Apple2Switches.AltZeroPage,
            0xC00A or 0xC00B when write => Apple2Switches.SlotC3Rom,
            0xC00C or 0xC00D when write => Apple2Switches.Column80,
            0xC00E or 0xC00F when write => Apple2Switches.AlternateCharacters,
            0xC050 or 0xC051 => Apple2Switches.Text, 0xC052 or 0xC053 => Apple2Switches.Mixed,
            0xC054 or 0xC055 => Apple2Switches.Page2, 0xC056 or 0xC057 => Apple2Switches.HiRes,
            0xC05E or 0xC05F => Apple2Switches.DoubleHiRes,
            _ => Apple2Switches.None
        };

        bool enabled = flag == Apple2Switches.DoubleHiRes ? (address & 1) == 0 : (address & 1) != 0;
        Switches = enabled ? Switches | flag : Switches & ~flag;
    }

    private void LatchKey()
    {
        if ((_keyboard & 128) == 0 && _keys.Count != 0) { _keyboard = (byte)(_keys.Dequeue() | 128); }
    }

    private byte FloatingBus() => Video.FloatingBus;

    /// <summary>
    ///  Gets the displayed text-page byte without altering the CPU memory map.
    /// </summary>
    /// <param name="row">The text row, from zero through 23.</param>
    /// <param name="column">The displayed column.</param>
    /// <returns>The character byte.</returns>
    public byte TextByte(int row, int column)
    {
        int columns = Has(Apple2Switches.Column80) ? 80 : 40;
        return row is < 0 or >= 24
            ? throw new ArgumentOutOfRangeException(nameof(row))
            : column < 0 || column >= columns
                ? throw new ArgumentOutOfRangeException(nameof(column))
                : (columns == 80 && (column & 1) == 0 ? _auxiliary : _main)[TextAddress(row, columns == 80 ? column / 2 : column)];
    }

    /// <summary>
    ///  Renders 40/80-column text from the supplied character ROM, including inverse and flashing cells.
    ///  Each output byte is a monochrome pixel; graphics-only rows remain blank in mixed mode.
    /// </summary>
    /// <returns>A 280/560 by 192 pixel image in scanline order.</returns>
    public byte[] RenderTextBitmap()
    {
        int columns = Has(Apple2Switches.Column80) ? 80 : 40;
        int width = columns * 7;
        byte[] pixels = new byte[width * 192];
        bool phase = (CycleCount / (65 * 4203)) % 2 != 0;
        for (int row = 0; row < 24; row++)
        {
            if (!Has(Apple2Switches.Text) && (!Has(Apple2Switches.Mixed) || row < 20)) { continue; }
            for (int column = 0; column < columns; column++)
            {
                int code = TextByte(row, column);
                if (code is >= 0x40 and < 0x80 && !Has(Apple2Switches.AlternateCharacters))
                {
                    code = (code & 0x3F) | (phase ? 0 : 0x80);
                }

                for (int scanline = 0; scanline < 8; scanline++)
                {
                    byte glyph = _roms.Characters[code * 8 + scanline];
                    for (int bit = 0; bit < 7; bit++)
                    {
                        pixels[(row * 8 + scanline) * width + column * 7 + bit] = (byte)(((glyph >> bit) & 1) ^ 1);
                    }
                }
            }
        }

        return pixels;
    }

    private int TextAddress(int row, int column)
    {
        int page = Has(Apple2Switches.Page2) && !Has(Apple2Switches.Store80) ? 0x800 : 0x400;
        return page + (row & 7) * 128 + (row >> 3) * 40 + column;
    }

    /// <summary>
    ///  Gets the slot 7 block device, or null when slot 7 is empty.
    /// </summary>
    internal IBlockDevice? BlockDevice => _disk;

    /// <summary>
    ///  Gets the slot 7 device's last block command: the block, whether it wrote, and the cycle it ran.
    /// </summary>
    internal (uint? Block, bool Write, ulong Cycle) LastBlockAccess => (_lastBlock, _lastBlockWrite, _lastBlockCycle);

    /// <summary>
    ///  Gets whether a block command has written to the slot 7 device.
    /// </summary>
    internal bool BlockWritten => _blockWritten;

    private void DiskCommand()
    {
        uint block = (uint)(Peek(0x46) | (Peek(0x47) << 8));
        ushort buffer = (ushort)(Peek(0x44) | (Peek(0x45) << 8));
        byte command = Peek(0x42);
        _diskError = 0;
        if (_disk is null)
        {
            _diskError = 0x28;
            return;
        }

        if (command == 0) { return; }
        if (command is not (1 or 2))
        {
            _diskError = 1;
            return;
        }

        if (block >= _disk.BlockCount)
        {
            _diskError = 0x27;
            return;
        }

        if (command == 2 && _disk.IsReadOnly)
        {
            _diskError = 0x2B;
            return;
        }

        _lastBlock = block;
        _lastBlockWrite = command == 2;
        _lastBlockCycle = CycleCount;
        _blockWritten |= command == 2;
        Span<byte> bytes = stackalloc byte[512];
        if (command == 1)
        {
            _disk.ReadBlock(block, bytes);
            for (int i = 0; i < bytes.Length; i++) { Write((ushort)(buffer + i), bytes[i]); }
        }
        else
        {
            for (int i = 0; i < bytes.Length; i++) { bytes[i] = Peek((ushort)(buffer + i)); }
            _disk.WriteBlock(block, bytes);
        }
    }

    private void CreateSlot7Rom()
    {
        Slot7Rom.Bytes.CopyTo(_slot7);
        if (_disk is { IsReadOnly: false })
        {
            _slot7[Slot7Rom.DeviceInfo - Slot7Rom.Origin] |= (byte)Slot7Rom.WriteCapabilityMask;
        }
    }
}
