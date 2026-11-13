// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A mouse card: the pointer's position within its bounds, its one button, and the interrupts it raises, answering
///  the calls of Apple's AppleMouse II firmware through the card's own firmware (<see cref="MouseRom"/>).
/// </summary>
/// <remarks>
///  <para>
///   The host moves the mouse with <see cref="Move"/> and presses its button with <see cref="Button"/>. The card
///   follows them only while a program has turned it on (mode bit 0). Programs see the position, the button and
///   whether it moved through the firmware's routines, which copy them into the text screen's holes for the slot.
///  </para>
///  <para>
///   As on the AppleMouse II, interrupts come at the start of vertical blanking: every time with mode bit 3, and when
///   the mouse has moved or its button changed since the last one with bits 1 and 2. The line stays asserted until
///   SERVEMOUSE acknowledges it.
///  </para>
/// </remarks>
public sealed class Apple2MouseCard
{
    // The commands the firmware writes to the command port (Mouse.rom.asm numbers them the same).
    private const int SetMouse = 1;
    private const int ServeMouse = 2;
    private const int ReadMouse = 3;
    private const int ClearMouse = 4;
    private const int PosMouse = 5;
    private const int ClampMouse = 6;
    private const int HomeMouse = 7;
    private const int InitMouse = 8;
    private const int Basic = 9;
    private const int BasicInput = 10;
    private const int BasicOutput = 11;

    // The command's upper bits tell the firmware how it found the slot.
    private const int CommandMask = 0x3F;

    // BASIC's line, as Apple's firmware writes it into the input buffer: "+XXXXX,+YYYYY,+BB" and a return.
    private const ushort InputBuffer = 0x0200;
    private const byte LineLength = 0x11;
    private const byte Return = 0x8D;
    private const ushort MSLOT = 0x07F8;

    // The mode bit BASIC sets, besides bit 0.
    private const byte BasicMode = 0x80;

    // The screen holes, each at its base plus the slot.
    private const ushort XLow = 0x0478;
    private const ushort YLow = 0x04F8;
    private const ushort XHigh = 0x0578;
    private const ushort YHigh = 0x05F8;
    private const ushort StatusHole = 0x0778;
    private const ushort ModeHole = 0x07F8;

    private const int DefaultMaximum = 1023;

    private readonly Apple2Bus _bus;
    private int _minimumX;
    private int _maximumX = DefaultMaximum;
    private int _minimumY;
    private int _maximumY = DefaultMaximum;
    private bool _button;
    private bool _buttonAtRead;
    private bool _movedSinceRead;
    private bool _movedSinceInterrupt;
    private bool _buttonChangedSinceInterrupt;
    private byte _interrupts;

    // The ports: the caller's A and X going in, and the A, X and carry going back.
    private byte _value;
    private byte _x;
    private bool _carry;

    /// <summary>
    ///  Creates the bus's mouse card, out of any slot until <see cref="Apple2Bus.InstallMouse"/> puts it in one.
    /// </summary>
    /// <param name="bus">The bus whose screen holes and keyboard the card reads and writes.</param>
    internal Apple2MouseCard(Apple2Bus bus) => _bus = bus;

    /// <summary>
    ///  Gets the slot the card is in, or 0 when it is out.
    /// </summary>
    public int Slot { get; internal set; }

    /// <summary>
    ///  Gets the mode a program set: bit 0 on, bits 1, 2 and 3 interrupt on movement, the button and vertical blanking.
    /// </summary>
    public byte Mode { get; private set; }

    /// <summary>
    ///  Gets whether a program has turned the mouse on, so that it follows <see cref="Move"/>.
    /// </summary>
    public bool IsOn => (Mode & 1) != 0;

    /// <summary>
    ///  Gets the horizontal position.
    /// </summary>
    public int X { get; private set; }

    /// <summary>
    ///  Gets the vertical position.
    /// </summary>
    public int Y { get; private set; }

    /// <summary>
    ///  Gets or sets whether the button is down.
    /// </summary>
    public bool Button
    {
        get => _button;
        set
        {
            if (value != _button) { _buttonChangedSinceInterrupt = true; }
            _button = value;
        }
    }

    /// <summary>
    ///  Gets whether the card holds its interrupt line asserted, until SERVEMOUSE takes it.
    /// </summary>
    public bool InterruptRequested => _interrupts != 0;

    /// <summary>
    ///  Moves the mouse, keeping it within the bounds a program set. Nothing moves while the mouse is off.
    /// </summary>
    /// <param name="dx">How far right, or left when negative.</param>
    /// <param name="dy">How far down, or up when negative.</param>
    public void Move(int dx, int dy)
    {
        if (!IsOn) { return; }
        int x = Math.Clamp(X + dx, _minimumX, Math.Max(_minimumX, _maximumX));
        int y = Math.Clamp(Y + dy, _minimumY, Math.Max(_minimumY, _maximumY));
        if (x == X && y == Y) { return; }
        X = x;
        Y = y;
        _movedSinceRead = true;
        _movedSinceInterrupt = true;
    }

    /// <summary>
    ///  Turns the mouse off and puts it at 0, 0 with bounds of 0 to 1023, as the card's reset does.
    /// </summary>
    public void Reset()
    {
        Mode = 0;
        X = Y = 0;
        _minimumX = _minimumY = 0;
        _maximumX = _maximumY = DefaultMaximum;
        _buttonAtRead = _movedSinceRead = _movedSinceInterrupt = _buttonChangedSinceInterrupt = false;
        _interrupts = 0;
    }

    /// <summary>
    ///  Raises the interrupts the mode asks for at the start of vertical blanking.
    /// </summary>
    internal void VerticalBlank()
    {
        if (!IsOn) { return; }
        byte sources = 0;
        if ((Mode & 8) != 0) { sources |= 8; }
        if ((Mode & 2) != 0 && _movedSinceInterrupt) { sources |= 2; }
        if ((Mode & 4) != 0 && _buttonChangedSinceInterrupt) { sources |= 4; }
        _movedSinceInterrupt = _buttonChangedSinceInterrupt = false;
        _interrupts |= sources;
    }

    /// <summary>
    ///  Reads a port, which changes nothing.
    /// </summary>
    /// <param name="offset">The port, the low four bits of the address.</param>
    /// <param name="floatingBus">What an unused port reads.</param>
    /// <returns>The carry, A or X the last command returned.</returns>
    internal byte Read(int offset, byte floatingBus) => offset switch
    {
        0 => _carry ? (byte)1 : (byte)0,
        1 => _value,
        2 => _x,
        _ => floatingBus
    };

    /// <summary>
    ///  Writes a port: the caller's A or X, or a command, which runs at once.
    /// </summary>
    /// <param name="offset">The port, the low four bits of the address.</param>
    /// <param name="value">The byte.</param>
    internal void Write(int offset, byte value)
    {
        switch (offset)
        {
            case 0: Run(value);
                break;
            case 1: _value = value;
                break;
            case 2: _x = value;
                break;
        }
    }

    // Runs a command with the caller's A and X in the ports. The A and X go back as they came unless it sets them.
    private void Run(int command)
    {
        _carry = false;
        switch (command & CommandMask)
        {
            case SetMouse: _carry = !SetMode(_value);
                break;
            case ServeMouse:
                // As Apple's firmware does, the status hole's cause bits always take the answer, none included, so
                // a handler polling them never sees the last interrupt's cause again.
                _carry = _interrupts == 0;
                Hole(StatusHole, (byte)((Peek(StatusHole) & ~0x0E) | _interrupts));
                _interrupts = 0;
                break;
            case ReadMouse:
                // Apple's firmware asks its microcontroller only while the mouse is on.
                if (IsOn) { CopyToHoles(); }
                break;
            case ClearMouse:
                X = Y = 0;
                WriteZeroPosition();
                break;
            case PosMouse:
                X = (short)(Peek(XLow) | (Peek(XHigh) << 8));
                Y = (short)(Peek(YLow) | (Peek(YHigh) << 8));
                break;
            case ClampMouse:
                int minimum = (short)(_bus.Peek(XLow) | (_bus.Peek(XHigh) << 8));
                int maximum = (short)(_bus.Peek(YLow) | (_bus.Peek(YHigh) << 8));
                if (_value == 0)
                {
                    (_minimumX, _maximumX) = (minimum, maximum);
                    X = Math.Clamp(X, minimum, Math.Max(minimum, maximum));
                }
                else
                {
                    (_minimumY, _maximumY) = (minimum, maximum);
                    Y = Math.Clamp(Y, minimum, Math.Max(minimum, maximum));
                }

                break;
            case HomeMouse:
                X = _minimumX;
                Y = _minimumY;
                break;
            case InitMouse:
                bool button = _button;
                Reset();
                _button = _buttonAtRead = button;
                WritePosition();
                Hole(StatusHole, 0);
                Hole(ModeHole, 0);
                break;
            case Basic:
                if (BasicHook()) { Input(); }
                else { Output(); }
                break;
            case BasicInput: Input();
                break;
            case BasicOutput: Output();
                break;
        }
    }

    private bool SetMode(byte mode)
    {
        if (mode > 0x0F) { return false; }
        Mode = mode;
        if (!IsOn) { _interrupts = 0; }
        Hole(ModeHole, mode);
        return true;
    }

    private void CopyToHoles()
    {
        WritePosition();
        Hole(StatusHole, (byte)((_button ? 0x80 : 0) | (_buttonAtRead ? 0x40 : 0) | (_movedSinceRead ? 0x20 : 0)));
        _buttonAtRead = _button;
        _movedSinceRead = false;
    }

    private void WriteZeroPosition()
    {
        Hole(XLow, 0);
        Hole(XHigh, 0);
        Hole(YLow, 0);
        Hole(YHigh, 0);
    }

    private void WritePosition()
    {
        Hole(XLow, (byte)X);
        Hole(XHigh, (byte)(X >> 8));
        Hole(YLow, (byte)Y);
        Hole(YHigh, (byte)(Y >> 8));
    }

    // Whether $Cn00 was reached through the input hook, as Apple's firmware decides: output when CSW points at the
    // card and has not been moved to $Cn07 yet, else input when KSW points at it, else output. PR#n and IN#n point a
    // hook at $Cn00; the card moves it to $Cn07 or $Cn05, so later characters go straight to their entry. DOS puts the
    // real hooks back in $36-$39 while it calls one, and keeps what the card changes.
    private bool BasicHook()
    {
        byte page = (byte)(0xC0 | Slot);
        if (_bus.Peek(0x37) == page && _bus.Peek(0x36) != 0x07)
        {
            _bus.Write(0x36, 0x07);
            return false;
        }

        if (_bus.Peek(0x39) != page) { return false; }
        _bus.Write(0x38, 0x05);
        return true;
    }

    // BASIC's input: writes "X,Y,B" into the input buffer and returns a return with X = the line's length, as GETLN
    // would, so INPUT reads three numbers and nothing is echoed. B is 1 for the button down and down at the last read,
    // 2 pressed since, 3 released since and 4 up, negative when a key is waiting. With the mouse off, the position
    // holes are cleared and the status is $C0, as on Apple's card.
    private void Input()
    {
        _bus.Write(MSLOT, (byte)(0xC0 | Slot));
        if (IsOn)
        {
            SetBasicMode(on: true);
            CopyToHoles();
        }
        else
        {
            WriteZeroPosition();
            Hole(StatusHole, 0xC0);
        }

        byte status = Peek(StatusHole);
        int button = ((status & 0x80) != 0, (status & 0x40) != 0) switch
        {
            (true, true) => 1,
            (true, false) => 2,
            (false, true) => 3,
            _ => 4
        };

        if (_bus.KeyStrobe) { button = -button; }
        int x = (short)(Peek(XLow) | (Peek(XHigh) << 8));
        int y = (short)(Peek(YLow) | (Peek(YHigh) << 8));
        string line = string.Create(CultureInfo.InvariantCulture, $"{Signed(x, 5)},{Signed(y, 5)},{Signed(button, 2)}");
        for (int i = 0; i < line.Length; i++) { _bus.Write((ushort)(InputBuffer + i), (byte)(line[i] | 0x80)); }
        _bus.Write(InputBuffer + LineLength, Return);
        _value = Return;
        _x = LineLength;
    }

    // BASIC's output: a return is ignored; any other character turns the mouse on with an odd code and off with an
    // even one, as CHR$(1) and CHR$(0) do, in BASIC mode. A is returned as it came.
    private void Output()
    {
        _bus.Write(MSLOT, (byte)(0xC0 | Slot));
        if (_value != Return) { SetBasicMode(on: (_value & 1) != 0); }
    }

    private void SetBasicMode(bool on)
    {
        Mode = (byte)(BasicMode | (on ? 1 : 0));
        _interrupts = 0;
        Hole(ModeHole, Mode);
    }

    private static string Signed(int value, int digits) =>
        (value < 0 ? "-" : "+") + Math.Abs(value).ToString(new string('0', digits), CultureInfo.InvariantCulture);

    private byte Peek(ushort hole) => _bus.Peek((ushort)(hole + Slot));

    private void Hole(ushort hole, byte value) => _bus.Write((ushort)(hole + Slot), value);
}
