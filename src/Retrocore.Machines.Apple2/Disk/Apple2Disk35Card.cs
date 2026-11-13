// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A 3.5-inch disk controller that answers as Apple's Apple II 3.5 Disk Controller Card does: a SmartPort with two
///  SuperDrives, which take 400K and 800K Apple disks and 720K and 1440K MFM disks, called through the card's own
///  firmware (<see cref="Disk35Rom"/>).
/// </summary>
/// <remarks>
///  <para>
///   The firmware writes the stack pointer to the card's port, and the card runs the call at once. It reads the
///   caller's status, saved at $0101 plus the stack pointer, to tell a boot (overflow) from a SmartPort call (carry)
///   and a ProDOS call. A SmartPort call's command and parameter list follow its JSR, and the card moves the return
///   address past them. It reads and writes the caller's buffers through the bus, as Apple's firmware copies them, so
///   they go through whatever memory map the caller set.
///  </para>
///  <para>
///   Apple's host firmware (<c>Roms/Disk35/Disk35Host.asm</c>) decides what callers see, and the card follows it: each
///   command's parameter count, the units ProDOS's unit numbers stand for, the errors ProDOS calls return, and the
///   boot's checks. Apple's card's 65C02 does the rest (<c>Disk35Card.asm</c>), and the card follows it for the status
///   it returns and the errors it gives.
///  </para>
/// </remarks>
public sealed class Apple2Disk35Card
{
    // SmartPort's commands, less the extended bit, which is bit 6.
    private const int StatusCommand = 0;
    private const int ReadBlockCommand = 1;
    private const int WriteBlockCommand = 2;
    private const int FormatCommand = 3;
    private const int ControlCommand = 4;
    private const int InitCommand = 5;
    private const int OpenCommand = 6;
    private const int CloseCommand = 7;
    private const int ReadCommand = 8;
    private const int WriteCommand = 9;
    private const int SetFormatCommand = 0x0A;
    private const int ExtendedBit = 0x40;

    // The errors.
    private const byte NoError = 0;
    private const byte BadCommand = 0x01;
    private const byte BadParameterCount = 0x04;
    private const byte BadUnit = 0x11;
    private const byte BadControl = 0x21;
    private const byte BadControlParameter = 0x22;
    private const byte IOError = 0x27;
    private const byte NoDrive = 0x28;
    private const byte NoWrite = 0x2B;
    private const byte BadBlock = 0x2D;
    private const byte DiskSwitched = 0x2E;
    private const byte Offline = 0x2F;
    private const byte BadInterleave = 0x32;

    private const ushort StackPage = 0x0100;
    private const ushort BootBuffer = 0x0800;
    private const ushort MessageLine = 0x0488;
    private const int BlockSize = 512;

    // The tagged block READ and WRITE move: 12 tag bytes, then the 512 bytes of data.
    private const int TaggedBlockSize = 12 + BlockSize;

    private readonly Apple2Bus _bus;
    private readonly Apple2Disk35Drive[] _drives;

    // What the last call returns.
    private byte _a;
    private byte _x;
    private byte _y;

    /// <summary>
    ///  Creates the bus's 3.5 controller, out of any slot until <see cref="Apple2Bus.InstallDisk35"/> puts it in one.
    /// </summary>
    /// <param name="bus">The bus whose memory the card reads and writes.</param>
    internal Apple2Disk35Card(Apple2Bus bus)
    {
        _bus = bus;
        _drives = [new(this, drive: 1), new(this, drive: 2)];
    }

    /// <summary>
    ///  Gets the slot the card is in, or 0 when it is out.
    /// </summary>
    public int Slot { get; internal set; }

    /// <summary>
    ///  Gets the card's two drives, SmartPort units 1 and 2.
    /// </summary>
    public IReadOnlyList<Apple2Disk35Drive> Drives => _drives;

    /// <summary>
    ///  Gets the bus's cycle count, for the drives' activity.
    /// </summary>
    internal ulong CycleCount => _bus.CycleCount;

    /// <summary>
    ///  Gets the parameter count each SmartPort command needs, $00 to $0B, as Apple's host firmware checks it.
    /// </summary>
    private static ReadOnlySpan<byte> ParameterCounts => [3, 3, 3, 1, 3, 1, 1, 1, 4, 4, 3, 3];

    /// <summary>
    ///  Gets what a failed boot writes on the screen, as Apple's firmware does.
    /// </summary>
    private static ReadOnlySpan<byte> UnableToBoot => "UNABLE TO BOOT"u8;

    /// <summary>
    ///  Gets the name unit 0's status code 1 gives, as Apple's card's.
    /// </summary>
    private static ReadOnlySpan<byte> ControllerName => "APPLE UNIVERSAL 3.5 CONTROLLER"u8;

    /// <summary>
    ///  Gets the slot times 16, as ProDOS's unit numbers and the boot's X give it.
    /// </summary>
    private byte Slot16 => (byte)(Slot << 4);

    /// <summary>
    ///  Resets the card. The drives keep their disks.
    /// </summary>
    public void Reset()
    {
        _a = _x = _y = 0;
        foreach (Apple2Disk35Drive drive in _drives) { drive.Reset(); }
    }

    /// <summary>
    ///  Reads a port: the A, X or Y the last call returns, or, at <c>+3</c>, the message a failed boot shows.
    /// </summary>
    /// <param name="offset">The port, the low four bits of the address.</param>
    /// <param name="floatingBus">What an unused port reads.</param>
    /// <param name="sideEffects">Whether the read is the processor's, which may write the message.</param>
    /// <returns>The byte.</returns>
    internal byte ReadPort(int offset, byte floatingBus, bool sideEffects)
    {
        switch (offset)
        {
            case 0:
                return _a;
            case 1:
                return _x;
            case 2:
                return _y;
            case 3:
                if (sideEffects) { ShowUnableToBoot(); }
                return floatingBus;
            default:
                return floatingBus;
        }
    }

    /// <summary>
    ///  Writes a port: the stack pointer, written to <c>+0</c>, runs the call.
    /// </summary>
    /// <param name="offset">The port, the low four bits of the address.</param>
    /// <param name="value">The byte.</param>
    internal void WritePort(int offset, byte value)
    {
        if (offset == 0) { Run(value); }
    }

    /// <summary>
    ///  Runs the call whose caller's status is just above the stack pointer.
    /// </summary>
    /// <param name="stackPointer">The stack pointer as the firmware wrote it.</param>
    private void Run(byte stackPointer)
    {
        byte flags = _bus.Peek((ushort)(StackPage + (byte)(stackPointer + 1)));
        _x = _y = 0;
        if ((flags & 0x40) != 0)
        {
            Boot();
        }
        else if ((flags & 0x01) != 0)
        {
            _a = SmartPort((byte)(stackPointer + 2));
        }
        else
        {
            _a = ProDOS();
        }
    }

    /// <summary>
    ///  Reads block 0 of the first drive into $0800 and sets ProDOS's page zero as for that read, as Apple's firmware
    ///  boots. A = 0 and X = the slot times 16 for a boot block (one that starts with $01 and a nonzero byte), and Y =
    ///  $Cn either way.
    /// </summary>
    private void Boot()
    {
        _x = Slot16;
        _y = (byte)(0xC0 | Slot);
        if (_drives[0].Disk is not { } disk)
        {
            _a = Offline;
            return;
        }

        Span<byte> block = stackalloc byte[BlockSize];
        _drives[0].Touch(0, write: false);
        disk.ReadBlock(0, block);
        WriteMemory(BootBuffer, block);
        _bus.Write(0x42, 1);
        _bus.Write(0x43, Slot16);
        _bus.Write(0x44, BootBuffer & 0xFF);
        _bus.Write(0x45, BootBuffer >> 8);
        _bus.Write(0x46, 0);
        _bus.Write(0x47, 0);
        _a = block[0] == 0x01 && block[1] != 0 ? NoError : IOError;
    }

    /// <summary>
    ///  Writes UNABLE TO BOOT on the text screen's line 9, as Apple's firmware does.
    /// </summary>
    private void ShowUnableToBoot()
    {
        for (int i = 0; i < UnableToBoot.Length; i++)
        {
            _bus.Write((ushort)(MessageLine + i), (byte)(UnableToBoot[i] | 0x80));
        }
    }

    /// <summary>
    ///  Runs a SmartPort call, whose command and list follow the JSR whose return address is on the stack, and moves
    ///  that return address past them.
    /// </summary>
    /// <param name="returnOffset">Where on the stack page the return address is.</param>
    /// <returns>The error.</returns>
    private byte SmartPort(byte returnOffset)
    {
        ushort returnLow = (ushort)(StackPage + returnOffset);
        ushort returnHigh = (ushort)(StackPage + (byte)(returnOffset + 1));
        ushort caller = (ushort)(_bus.Peek(returnLow) | (_bus.Peek(returnHigh) << 8));
        byte command = _bus.Peek((ushort)(caller + 1));
        ushort list = Word((ushort)(caller + 2));
        bool extended = (command & ExtendedBit) != 0;
        ushort resume = (ushort)(caller + (extended ? 5 : 3));
        _bus.Write(returnLow, (byte)resume);
        _bus.Write(returnHigh, (byte)(resume >> 8));

        int code = command & ~ExtendedBit;
        if (code >= ParameterCounts.Length) { return BadCommand; }
        if (_bus.Peek(list) != ParameterCounts[code]) { return BadParameterCount; }

        SmartPortList call = new(_bus, list, extended);
        return code switch
        {
            StatusCommand => Status(call),
            ReadBlockCommand => Moved(Transfer(call.Unit, call.Block, call.Buffer, write: false, extended), BlockSize),
            WriteBlockCommand => Moved(Transfer(call.Unit, call.Block, call.Buffer, write: true, extended), BlockSize),
            FormatCommand => call.Unit == 0 ? BadCommand : FormatUnit(call.Unit, extended),
            ControlCommand => Control(call),
            InitCommand => Initialize(),
            OpenCommand or CloseCommand => BadCommand,
            ReadCommand or WriteCommand => TaggedBlock(call, write: code == WriteCommand),
            SetFormatCommand => SetFormat(call),
            _ => BadControl
        };
    }

    /// <summary>
    ///  Runs a ProDOS call, with its parameters in $42-$47, turned into SmartPort's as Apple's host firmware turns them
    ///  (PRODOSLIST), and its errors into ProDOS's (MAPERROR).
    /// </summary>
    /// <returns>The error: 0, $2B, $28, $2F, or $27 for any other.</returns>
    private byte ProDOS()
    {
        byte command = _bus.Peek(0x42);
        if (command > 3) { return BadCommand; }
        int unit = UnitFor(_bus.Peek(0x43));
        ushort buffer = Word(0x44);
        uint block = Word(0x46);
        byte error = command switch
        {
            0 => ProDOSStatus(unit),
            1 => Transfer(unit, block, buffer, write: false, extended: false),
            2 => Transfer(unit, block, buffer, write: true, extended: false),
            _ => FormatUnit(unit, extended: false)
        };

        return error switch
        {
            NoError or NoWrite or NoDrive or Offline => error,
            BadUnit => NoDrive,
            _ => IOError
        };
    }

    /// <summary>
    ///  Gets the SmartPort unit a ProDOS unit number stands for, as Apple's host firmware maps it: 1 or 2 for this
    ///  slot, by the drive bit; 3 or 4 for slot 2, where ProDOS puts a SmartPort's third and fourth units; 5 or 6 for
    ///  any other slot; 0 for slot 0.
    /// </summary>
    /// <param name="unitNumber">ProDOS's unit number: the drive in bit 7, the slot in bits 4-6.</param>
    /// <returns>The SmartPort unit.</returns>
    private int UnitFor(byte unitNumber)
    {
        int slot = (unitNumber >> 4) & 7;
        if (slot == 0) { return 0; }
        int first = slot == Slot ? 1 : slot == 2 ? 3 : 5;
        return first + (unitNumber >> 7);
    }

    /// <summary>
    ///  ProDOS's status: the block count in X and Y, and $2B for a write-protected disk.
    /// </summary>
    /// <param name="unit">The SmartPort unit.</param>
    /// <returns>The error.</returns>
    private byte ProDOSStatus(int unit)
    {
        byte error = DriveFor(unit, extended: false, out Apple2Disk35Drive? drive);
        if (error != NoError || drive?.Disk is not { } disk) { return error; }
        _x = (byte)disk.BlockCount;
        _y = (byte)(disk.BlockCount >> 8);
        return disk.IsReadOnly ? NoWrite : NoError;
    }

    /// <summary>
    ///  Finds a unit's drive with a disk in it. An extended call's first after a disk change gets $2E, as Apple's card
    ///  gives it; a standard call just takes the new disk.
    /// </summary>
    /// <param name="unit">The SmartPort unit.</param>
    /// <param name="extended">Whether the call is an extended one.</param>
    /// <param name="drive">The drive, when there is one.</param>
    /// <returns>0; $11 for no such drive; $2E for a changed disk; $2F for no disk.</returns>
    private byte DriveFor(int unit, bool extended, out Apple2Disk35Drive? drive)
    {
        drive = unit >= 1 && unit <= _drives.Length ? _drives[unit - 1] : null;
        if (drive is null) { return BadUnit; }
        if (drive.Disk is null) { return Offline; }
        return drive.TakeSwitched() && extended ? DiskSwitched : NoError;
    }

    /// <summary>
    ///  Reads or writes a block between a disk and the caller's memory.
    /// </summary>
    /// <param name="unit">The SmartPort unit.</param>
    /// <param name="block">The block.</param>
    /// <param name="buffer">The caller's 512 bytes.</param>
    /// <param name="write">Whether to write the block rather than read it.</param>
    /// <param name="extended">Whether the call is an extended one.</param>
    /// <returns>The error.</returns>
    private byte Transfer(int unit, uint block, ushort buffer, bool write, bool extended)
    {
        byte error = DriveFor(unit, extended, out Apple2Disk35Drive? drive);
        if (error != NoError || drive?.Disk is not { } disk) { return error; }
        if (block >= disk.BlockCount) { return BadBlock; }
        if (write && disk.IsReadOnly) { return NoWrite; }
        drive.Touch(block, write);
        Span<byte> bytes = stackalloc byte[BlockSize];
        if (write)
        {
            ReadMemory(buffer, bytes);
            disk.WriteBlock(block, bytes);
            drive.Changed = true;
        }
        else
        {
            disk.ReadBlock(block, bytes);
            WriteMemory(buffer, bytes);
        }

        return NoError;
    }

    /// <summary>
    ///  READ and WRITE: a tagged block, its 12 tag bytes and then its data, of 400K and 800K Apple disks only, as
    ///  Apple's card moves them. The count must be 524, and the block is where READ and WRITE elsewhere take an
    ///  address. This card keeps no tags: they read as zero and writing them changes nothing.
    /// </summary>
    /// <param name="call">The parameter list: the count, then the block.</param>
    /// <param name="write">Whether to write the block rather than read it.</param>
    /// <returns>The error.</returns>
    private byte TaggedBlock(SmartPortList call, bool write)
    {
        if (call.Unit == 0) { return BadUnit; }
        if ((call.Parameter(0) | (call.Parameter(1) << 8)) != TaggedBlockSize) { return BadControlParameter; }
        byte error = DriveFor(call.Unit, call.Extended, out Apple2Disk35Drive? drive);
        if (error != NoError || drive?.Disk is not { } disk) { return error; }
        if (disk.IsMfm) { return IOError; }
        uint block = (uint)(call.Parameter(2) | (call.Parameter(3) << 8));
        if (block >= disk.BlockCount) { return BadBlock; }
        if (write && disk.IsReadOnly) { return NoWrite; }
        drive.Touch(block, write);
        Span<byte> bytes = stackalloc byte[TaggedBlockSize];
        if (write)
        {
            ReadMemory(call.Buffer, bytes);
            disk.WriteBlock(block, bytes[12..]);
            drive.Changed = true;
        }
        else
        {
            bytes[..12].Clear();
            disk.ReadBlock(block, bytes[12..]);
            WriteMemory(call.Buffer, bytes);
        }

        return Moved(NoError, TaggedBlockSize);
    }

    /// <summary>
    ///  Command $0A, which chooses the next FORMAT's kind. Its parameter is a count of bytes in the buffer, of which
    ///  Apple's host firmware (COMMAND0A) passes up to four, the rest zero, and the card (SETFORMAT) takes the first as
    ///  the kind (0 for the disk's own, or an even kind below $0D), wants the second 0, and takes a third below $0D as
    ///  the interleave. This card checks them so and formats every disk as the kind it is.
    /// </summary>
    /// <param name="call">The parameter list: the buffer, then the count.</param>
    /// <returns>The error: $21 for what Apple's card refuses.</returns>
    private byte SetFormat(SmartPortList call)
    {
        Span<byte> payload = stackalloc byte[4];
        ReadMemory(call.Buffer, payload[..Math.Min(call.Parameter(0), payload.Length)]);
        byte kind = payload[0];
        if (payload[1] != 0 || kind >= 0x0D || (kind & 1) != 0) { return BadControl; }
        return kind != 0 && payload[2] >= 0x0D ? BadControl : NoError;
    }

    /// <summary>
    ///  Formats a unit's disk, leaving every block zero.
    /// </summary>
    /// <param name="unit">The SmartPort unit.</param>
    /// <param name="extended">Whether the call is an extended one.</param>
    /// <returns>The error.</returns>
    private byte FormatUnit(int unit, bool extended)
    {
        byte error = DriveFor(unit, extended, out Apple2Disk35Drive? drive);
        if (error != NoError || drive?.Disk is not { } disk) { return error; }
        if (disk.IsReadOnly) { return NoWrite; }
        drive.Touch(0, write: true);
        disk.Erase();
        drive.Changed = true;
        return NoError;
    }

    /// <summary>
    ///  INIT: resets the card, whatever the unit, as Apple's card restarts itself.
    /// </summary>
    /// <returns>No error.</returns>
    private byte Initialize()
    {
        Reset();
        return NoError;
    }

    /// <summary>
    ///  STATUS: the controller's for unit 0, else a drive's, written to the caller's buffer.
    /// </summary>
    /// <param name="call">The parameter list.</param>
    /// <returns>The error.</returns>
    private byte Status(SmartPortList call)
    {
        int code = call.Parameter(0);
        Span<byte> answer = stackalloc byte[32];
        int length;
        if (call.Unit == 0)
        {
            length = ControllerStatus(code, answer);
        }
        else
        {
            if (call.Unit > _drives.Length) { return BadUnit; }
            length = _drives[call.Unit - 1].Status(code, call.Extended, answer);
        }

        if (length < 0) { return BadControl; }
        WriteMemory(call.Buffer, answer[..length]);
        return Moved(NoError, length);
    }

    /// <summary>
    ///  Unit 0's status, as Apple's card gives it: code 0 the number of units, an interrupt byte of 0 and the bytes
    ///  $01, $00, $00, $01, $00, $00; code 1 the controller's name.
    /// </summary>
    /// <param name="code">The status code.</param>
    /// <param name="answer">Where to put it.</param>
    /// <returns>Its length, or -1 for a code the controller does not answer.</returns>
    private int ControllerStatus(int code, Span<byte> answer)
    {
        switch (code)
        {
            case 0:
                answer[..8].Clear();
                answer[0] = (byte)_drives.Length;
                answer[2] = 0x01;
                answer[5] = 0x01;
                return 8;
            case 1:
                answer[0] = (byte)ControllerName.Length;
                ControllerName.CopyTo(answer[1..]);
                return ControllerName.Length + 1;
            default:
                return -1;
        }
    }

    /// <summary>
    ///  CONTROL, whose list starts with its length, as Apple's card answers it. A drive takes 0 (forget the disk and
    ///  look again, which, as Apple's CTLRESET checks the disk, is $2F with no disk and takes a changed disk, with $2E
    ///  for an extended call) and 4 (eject); 9 (sides) and $0A (interleave), which take one byte, change nothing here. Codes $0C
    ///  to $13, which reach into the card's own 65C02, are taken and do nothing, but for $12, which would run code
    ///  there. Unit 0 takes only $0C and $0E-$13.
    /// </summary>
    /// <param name="call">The parameter list.</param>
    /// <returns>The error.</returns>
    private byte Control(SmartPortList call)
    {
        int code = call.Parameter(0);
        int length = _bus.Peek(call.Buffer) | (_bus.Peek((ushort)(call.Buffer + 1)) << 8);
        if (length >= 0x400) { return BadControlParameter; }
        if (call.Unit > _drives.Length) { return BadUnit; }
        if (code >= 0x14 || code == 0x12) { return BadControl; }
        if (call.Unit == 0) { return code is 0x0C or (>= 0x0E and <= 0x13) ? NoError : BadControl; }

        Apple2Disk35Drive drive = _drives[call.Unit - 1];
        switch (code)
        {
            case 0x00:
                drive.Reset();
                return DriveFor(call.Unit, call.Extended, out _);
            case 0x04:
                drive.EjectByProgram();
                return NoError;
            case 0x09:
                return length == 1 ? NoError : BadControlParameter;
            case 0x0A:
                if (length != 1) { return BadControlParameter; }
                return _bus.Peek((ushort)(call.Buffer + 2)) >= 13 ? BadInterleave : NoError;
            case >= 0x0C:
                return NoError;
            default:
                return BadControl;
        }
    }

    /// <summary>
    ///  Returns the count of bytes a successful call moved in X and Y.
    /// </summary>
    /// <param name="error">The call's error.</param>
    /// <param name="count">The bytes it moved when it succeeded.</param>
    /// <returns>The error.</returns>
    private byte Moved(byte error, int count)
    {
        if (error == NoError)
        {
            _x = (byte)count;
            _y = (byte)(count >> 8);
        }

        return error;
    }

    /// <summary>
    ///  Reads bytes from memory through the bus, as the caller's memory map has it.
    /// </summary>
    /// <param name="address">Where.</param>
    /// <param name="bytes">Where to put them.</param>
    private void ReadMemory(ushort address, Span<byte> bytes)
    {
        for (int i = 0; i < bytes.Length; i++) { bytes[i] = _bus.Peek((ushort)(address + i)); }
    }

    /// <summary>
    ///  Writes bytes to memory through the bus, as the caller's memory map has it.
    /// </summary>
    /// <param name="address">Where.</param>
    /// <param name="bytes">The bytes.</param>
    private void WriteMemory(ushort address, ReadOnlySpan<byte> bytes)
    {
        for (int i = 0; i < bytes.Length; i++) { _bus.Write((ushort)(address + i), bytes[i]); }
    }

    /// <summary>
    ///  Reads a little-endian word.
    /// </summary>
    /// <param name="address">Its low byte's address.</param>
    /// <returns>The word.</returns>
    private ushort Word(ushort address) => (ushort)(_bus.Peek(address) | (_bus.Peek((ushort)(address + 1)) << 8));
}
