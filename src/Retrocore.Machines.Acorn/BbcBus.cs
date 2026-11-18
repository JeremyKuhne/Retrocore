// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The BBC Micro's memory map and I/O.
/// </summary>
/// <remarks>
///  <para>
///   RAM is <c>$0000-$7FFF</c> (a Model A's 16K answers twice), the paged ROM ROMSEL selects is <c>$8000-$BFFF</c>,
///   and the MOS fills <c>$C000-$FFFF</c> but for the I/O pages: FRED (<c>$FC00</c>) and JIM (<c>$FD00</c>) on the 1
///   MHz bus, which with nothing fitted read <c>$FF</c>, and SHEILA (<c>$FE00</c>). In SHEILA: <c>$FE00</c> the 6845,
///   <c>$FE08</c> the 6850 ACIA, <c>$FE10</c> the serial ULA, <c>$FE18</c> the Econet station number (which a read
///   also takes Econet's interrupts off with), <c>$FE20</c> the video ULA, <c>$FE30</c> ROMSEL, <c>$FE40</c> the
///   system VIA, <c>$FE60</c> the user VIA, <c>$FE80</c> the 8271, <c>$FEA0</c> the Econet ADLC, <c>$FEC0</c> the
///   ADC and <c>$FEE0</c> the Tube. Each repeats through its block. What nothing answers in SHEILA reads
///   <c>$FE</c>, and the 8271's absent controller <c>$FF</c>, as in MAME.
///  </para>
///  <para>
///   The CPU runs at 2 MHz, but FRED, JIM and SHEILA's 6845, ACIA, serial ULA, station number, VIAs and ADC run on
///   the 1 MHz clock. An access to them stretches the CPU's cycle until it ends with a 1 MHz cycle: two or three 2
///   MHz cycles, by the phase it starts in.
///  </para>
///  <para>
///   The system VIA's port A is the slow data bus to the keyboard and the sound chip; port B's bits 0-2 address the
///   addressable latch and bit 3 is the bit to store, bits 4-5 read the fire buttons and 6-7 the absent speech
///   chip, high. The latch's bits: 0 the sound chip's write enable (low writes), 1 and 2 the speech chip's, 3 the
///   keyboard's (low: the CPU reads keys), 4 and 5 the screen wrap C0 and C1, 6 and 7 the CAPS LOCK and SHIFT LOCK
///   lights. CA1 is the 6845's vertical sync, CA2 the keyboard, CB1 the ADC's end of conversion, CB2 the light pen.
///  </para>
/// </remarks>
public sealed class BbcBus : IProcessorBus
{
    private readonly byte[] _ram;
    private readonly byte[] _mos;
    private readonly byte[]?[] _sockets = new byte[BbcRoms.Sockets][];
    private readonly bool _modelB;
    private long _cycles;
    private byte _romSelect;
    private byte _latch;
    private bool _verticalSync;
    private bool _lightPenStrobe = true;

    /// <summary>
    ///  Creates the bus at power-on.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="model">The model.</param>
    /// <param name="diskInterface">Whether the 8271 disk interface is fitted.</param>
    internal BbcBus(BbcRoms roms, BbcModel model, bool diskInterface)
    {
        _modelB = model == BbcModel.ModelB;
        if (diskInterface)
        {
            DiskController = new Intel8271();
            Drives = [new(DiskController, 0), new(DiskController, 1)];
        }
        else
        {
            Drives = [];
        }

        _ram = new byte[_modelB ? 0x8000 : 0x4000];

        // What RAM holds at power-on is happenstance; it comes up all ones, as MAME's does, so the two run in step
        // until the MOS clears it.
        _ram.AsSpan().Fill(0xFF);
        _mos = roms.Mos.ToArray();
        for (int socket = 0; socket < BbcRoms.Sockets; socket++)
        {
            ReadOnlySpan<byte> rom = roms.Socket(socket);
            _sockets[socket] = rom.IsEmpty ? null : rom.ToArray();
        }

        Video = new(_ram, roms.Characters);
        UserVia = _modelB ? new Via6522() : null;
        Analogue = _modelB ? new BbcAnalogue() : null;
        SerialUla = new(Acia, Cassette);
        UpdateSlowBus(write: false);
        UpdateInputs();
    }

    /// <summary>
    ///  Gets RAM: 32K, or the Model A's 16K.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets the MOS, at <c>$C000</c>.
    /// </summary>
    public ReadOnlySpan<byte> MosRom => _mos;

    /// <summary>
    ///  Gets the ROM in a paged ROM socket.
    /// </summary>
    /// <param name="socket">The socket, 0-3.</param>
    /// <returns>The 16K ROM, or empty for an empty socket.</returns>
    public ReadOnlySpan<byte> SocketRom(int socket) => _sockets[socket];

    /// <summary>
    ///  Gets the system VIA, at <c>$FE40</c>.
    /// </summary>
    public Via6522 SystemVia { get; } = new();

    /// <summary>
    ///  Gets the user VIA, at <c>$FE60</c>: the printer and user ports. The Model A has none.
    /// </summary>
    public Via6522? UserVia { get; }

    /// <summary>
    ///  Gets the 6850 ACIA, at <c>$FE08</c>, for the cassette and RS-423.
    /// </summary>
    public Acia6850 Acia { get; } = new();

    /// <summary>
    ///  Gets the video: the 6845 and the video ULA.
    /// </summary>
    public BbcVideo Video { get; }

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public BbcKeyboard Keyboard { get; } = new();

    /// <summary>
    ///  Gets the sound.
    /// </summary>
    public BbcAudio Audio { get; } = new();

    /// <summary>
    ///  Gets the analogue port. The Model A has none.
    /// </summary>
    public BbcAnalogue? Analogue { get; }

    /// <summary>
    ///  Gets or sets the Econet station number, read at <c>$FE18</c>.
    /// </summary>
    public byte StationNumber { get; set; } = 0xFE;

    /// <summary>
    ///  Gets the paged ROM ROMSEL selects: the last value written to <c>$FE30</c>, bits 0-3.
    /// </summary>
    public int RomSelect => _romSelect;

    /// <summary>
    ///  Gets the socket the paged ROM area shows: ROMSEL's low two bits.
    /// </summary>
    public int Socket => _romSelect & 3;

    /// <summary>
    ///  Gets the addressable latch's eight bits.
    /// </summary>
    public byte Latch => _latch;

    /// <summary>
    ///  Gets the serial ULA, at <c>$FE10</c>: the cassette and RS-423 clocks and modem, and the motor relay.
    /// </summary>
    public BbcSerialUla SerialUla { get; }

    /// <summary>
    ///  Gets the cassette recorder.
    /// </summary>
    public BbcCassette Cassette { get; } = new();

    /// <summary>
    ///  Gets the disk interface's 8271, at <c>$FE80</c>, or null when none is fitted.
    /// </summary>
    public Intel8271? DiskController { get; }

    /// <summary>
    ///  Gets the disk interface's drives: none, or drives 0 and 1.
    /// </summary>
    public IReadOnlyList<BbcFloppyDrive> Drives { get; }

    /// <summary>
    ///  Gets whether NMI is asserted: the 8271's interrupt output, which in non-DMA mode also carries data requests.
    /// </summary>
    public bool NonMaskableInterrupt => DiskController?.InterruptOutput == true;

    /// <summary>
    ///  Gets the 2 MHz cycles since power-on, stretched cycles included.
    /// </summary>
    public long Cycles => _cycles;

    /// <summary>
    ///  Gets whether a chip asserts IRQ.
    /// </summary>
    public bool InterruptRequested =>
        SystemVia.InterruptRequested || (UserVia?.InterruptRequested ?? false) || Acia.Interrupt;

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        switch (address >> 12)
        {
            case < 8:
                return _ram[address & (_ram.Length - 1)];
            case < 0xC:
                return _sockets[_romSelect & 3] is { } rom ? rom[address & 0x3FFF] : (byte)0xFF;
        }

        if (address is < 0xFC00 or >= 0xFF00) { return _mos[address & 0x3FFF]; }
        if (IsSlow(address)) { Stretch(); }
        return address < 0xFE00 ? (byte)0xFF : ReadSheila(address);
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address < 0x8000)
        {
            _ram[address & (_ram.Length - 1)] = value;
            return;
        }

        if (address is < 0xFC00 or >= 0xFF00) { return; }
        if (IsSlow(address)) { Stretch(); }
        if (address >= 0xFE00) { WriteSheila(address, value); }
    }

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address)
    {
        switch (address >> 12)
        {
            case < 8:
                return _ram[address & (_ram.Length - 1)];
            case < 0xC:
                return _sockets[_romSelect & 3] is { } rom ? rom[address & 0x3FFF] : (byte)0xFF;
        }

        if (address is < 0xFC00 or >= 0xFF00) { return _mos[address & 0x3FFF]; }
        if (address < 0xFE00) { return 0xFF; }
        int offset = address & 0xFF;
        return (offset >> 5) switch
        {
            0 => (offset & 0x18) switch
            {
                0 => Video.Crtc.Read(offset),
                8 => Acia.Peek(offset & 1),
                0x10 => 0,
                _ => StationNumber
            },
            2 => PeekSystemVia(offset),
            3 => UserVia?.Peek((byte)(offset & 0x0F)) ?? 0xFE,
            4 => DiskController is { } fdc ? (offset & 4) == 0 ? fdc.Peek(offset) : fdc.PeekData() : (byte)(_modelB ? 0xFF : 0xFE),
            6 => Analogue?.Read(offset & 3) ?? 0xFE,
            _ => 0xFE
        };
    }

    /// <summary>
    ///  Gets what backs an address now: for the paged ROMs, the socket ROMSEL selects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public BbcMemoryArea Area(ushort address) => address switch
    {
        < 0x8000 => BbcMemoryArea.Ram,
        < 0xC000 => BbcMemoryArea.PagedRom0 + Socket,
        < 0xFC00 or >= 0xFF00 => BbcMemoryArea.Mos,
        < 0xFE00 => BbcMemoryArea.OneMegahertzBus,
        _ => BbcMemoryArea.Sheila
    };

    /// <summary>
    ///  Copies bytes into RAM, for loading a program.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="bytes">The bytes.</param>
    /// <exception cref="ArgumentException">The bytes run past RAM.</exception>
    public void Load(ushort address, ReadOnlySpan<byte> bytes)
    {
        if (address + bytes.Length > _ram.Length)
        {
            throw new ArgumentException("The bytes run past RAM.", nameof(bytes));
        }

        bytes.CopyTo(_ram.AsSpan(address));
    }

    /// <summary>
    ///  Resets what BREAK reaches: the user VIA (the system VIA keeps its state, so the MOS can tell BREAK from
    ///  power-on).
    /// </summary>
    internal void ResetOnBreak()
    {
        UserVia?.Reset();
        DiskController?.Reset();
        UpdateInputs();
    }

    /// <summary>
    ///  Advances the devices one 2 MHz cycle.
    /// </summary>
    internal void Tick()
    {
        _cycles++;
        bool slow = (_cycles & 1) == 0;
        if (Video.Tick(slow))
        {
            bool vertical = Video.Crtc.VerticalSync;
            if (vertical != _verticalSync)
            {
                _verticalSync = vertical;
                SystemVia.CA1 = vertical;
            }
        }

        if (slow)
        {
            SystemVia.Tick();
            UserVia?.Tick();
            UpdateLightPenStrobe();
            Keyboard.Tick();
            bool key = Keyboard.Interrupt;
            if (SystemVia.CA2 != key) { SystemVia.CA2 = key; }
            if (Analogue is { } analogue)
            {
                analogue.Tick();
                if (SystemVia.CB1 != analogue.EndOfConversion) { SystemVia.CB1 = analogue.EndOfConversion; }
            }
        }

        SerialUla.Tick();
        DiskController?.Tick();
        if ((_cycles & (BbcTiming.CyclesPerSoundStep - 1)) == 0) { Audio.Chip.Tick(); }
        Audio.Tick();
    }

    // FRED, JIM, and SHEILA's 6845, ACIA, serial ULA and station number ($FE00-$FE1F), VIAs ($FE40-$FE7F) and ADC
    // ($FEC0-$FEDF) are on the 1 MHz clock.
    private static bool IsSlow(ushort address) =>
        address < 0xFE00 || (address & 0xE0) is 0x00 or 0x40 or 0x60 or 0xC0;

    // Holds the CPU until its access can end with a 1 MHz cycle: the cycle after this one ends one if this cycle
    // starts on the 1 MHz clock's phase, else the one after that.
    private void Stretch()
    {
        int extra = (_cycles & 1) == 0 ? 1 : 2;
        for (int cycle = 0; cycle < extra; cycle++) { Tick(); }
    }

    private byte ReadSheila(ushort address)
    {
        int offset = address & 0xFF;
        switch (offset >> 5)
        {
            case 0:
                switch (offset & 0x18)
                {
                    case 0:
                        return Video.Crtc.Read(offset);
                    case 8:
                        return Acia.Read(offset & 1);
                    case 0x10:
                        return SerialUla.Read();
                    default:
                        return StationNumber;
                }

            case 2:
                return ReadVia(SystemVia, offset);
            case 3:
                return UserVia is { } user ? ReadVia(user, offset) : (byte)0xFE;
            case 4:
                if (DiskController is not { } fdc) { return (byte)(_modelB ? 0xFF : 0xFE); }
                return (offset & 4) == 0 ? fdc.Read(offset) : fdc.ReadData();
            case 6:
                return Analogue?.Read(offset & 3) ?? 0xFE;
            default:
                return 0xFE;
        }
    }

    private void WriteSheila(ushort address, byte value)
    {
        int offset = address & 0xFF;
        switch (offset >> 5)
        {
            case 0:
                switch (offset & 0x18)
                {
                    case 0:
                        Video.Crtc.Write(offset, value);
                        break;
                    case 8:
                        Acia.Write(offset & 1, value);
                        if ((offset & 1) == 0) { SerialUla.UpdateCharacterTime(); }
                        break;
                    case 0x10:
                        SerialUla.Write(value);
                        break;
                }

                break;
            case 1:
                if ((offset & 0x10) == 0) { Video.Write(offset, value); }
                else { _romSelect = (byte)(value & 0x0F); }
                break;
            case 2:
                WriteSystemVia(offset, value);
                break;
            case 3:
                UserVia?.Write((byte)(offset & 0x0F), value);
                break;
            case 4:
                if (DiskController is not { } fdc) { break; }
                if ((offset & 4) == 0) { fdc.Write(offset, value); }
                else { fdc.WriteData(value); }
                break;
            case 6:
                Analogue?.Write(offset & 3, value);
                break;
        }
    }

    private byte ReadVia(Via6522 via, int offset)
    {
        UpdateInputs();
        return via.Read((byte)(offset & 0x0F));
    }

    // The system VIA as a CPU read would see it, its input pins brought up to date, without acknowledging anything.
    private byte PeekSystemVia(int offset)
    {
        UpdateInputPins();
        return SystemVia.Peek((byte)(offset & 0x0F));
    }

    private void WriteSystemVia(int offset, byte value)
    {
        int register = offset & 0x0F;
        SystemVia.Write((byte)register, value);
        if (register is 0 or 2)
        {
            // The addressable latch stores port B's bit 3 at the bit port B's bits 0-2 address.
            byte portB = SystemVia.PortBOutput;
            int bit = portB & 7;
            _latch = (portB & 8) != 0 ? (byte)(_latch | (1 << bit)) : (byte)(_latch & ~(1 << bit));
            Keyboard.CpuReads = (_latch & 8) == 0;
            Keyboard.CapsLock = (_latch & 0x40) == 0;
            Video.ScreenWrap = (_latch >> 4) & 3;
        }

        if (register is 0 or 1 or 2 or 3 or 15) { UpdateSlowBus(write: true); }
        UpdateLightPenStrobe();
    }

    // The system VIA's CB2 output is the 6845's light pen strobe: a rising edge latches the address being drawn.
    private void UpdateLightPenStrobe()
    {
        bool strobe = SystemVia.CB2Output;
        if (strobe && !_lightPenStrobe) { Video.Crtc.StrobeLightPen(); }
        _lightPenStrobe = strobe;
    }

    // The slow data bus: what the VIA drives, which the sound chip takes while its write enable is low, and onto which
    // the keyboard puts its bit 7 while the CPU reads it.
    private void UpdateSlowBus(bool write)
    {
        byte bus = SystemVia.PortAOutput;
        if (write && (_latch & 1) == 0) { Audio.Chip.Write(bus); }
        SystemVia.PortAInput = Keyboard.Read(bus);
        if (SystemVia.CA2 != Keyboard.Interrupt) { SystemVia.CA2 = Keyboard.Interrupt; }
    }

    // The levels the VIAs read from outside.
    private void UpdateInputs()
    {
        UpdateSlowBus(write: false);
        UpdateInputPins();
    }

    // The input pins' levels alone, for a peek: the keyboard's column on port A and the fire buttons on port B,
    // without the keyboard's CA2 edge, so looking changes no interrupt.
    private void UpdateInputPins()
    {
        SystemVia.PortAInput = Keyboard.Peek(SystemVia.PortAOutput);
        int buttons = Analogue?.Buttons ?? 0;
        SystemVia.PortBInput = (byte)(0xFF & ~((buttons & 3) << 4));
    }
}
