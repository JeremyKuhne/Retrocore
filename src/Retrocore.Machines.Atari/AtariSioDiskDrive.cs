// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Atari;

/// <summary>
///  A disk drive on the serial bus that answers the 810's commands from a disk image at the command level: Status,
///  Read, Put, Write and Format, and the 1050's enhanced-density and the common double-density disks too.
/// </summary>
/// <remarks>
///  <para>
///   It isn't the 810's own 6507, controller and mechanism (<see cref="Atari810"/> is). A command takes a fixed time:
///   about 2 ms for a status, 8 ms for a sector (a short seek and half a turn would be longer), and a quarter of a
///   second to format. The status frame is the 810's (Altirra Hardware Reference Manual, 10.2): the drive status,
///   the inverted controller status, the format timeout <c>$E0</c> and a zero.
///  </para>
/// </remarks>
public sealed class AtariSioDiskDrive : AtariDiskDrive, IAtariSioDevice
{
    private const int StatusCycles = 3_600;
    private const int SectorCycles = 14_000;
    private const int FormatCycles = 450_000;
    private const int MotorCycles = 3 * 1_789_773;

    private readonly AtariBus _bus;
    private byte _driveStatus;
    private byte _controllerStatus = 0xFF;
    private long _lastAccess = long.MinValue;
    private int _lastSector = 1;
    private bool _lastWrite;

    /// <summary>
    ///  Constructs a drive.
    /// </summary>
    /// <param name="bus">The machine's bus, for the clock.</param>
    /// <param name="number">The drive number, 1-4: <c>D1:</c> to <c>D4:</c>.</param>
    internal AtariSioDiskDrive(AtariBus bus, int number) : base(number, "Serial bus, at the command level")
    {
        _bus = bus;
    }

    /// <inheritdoc/>
    public byte DeviceId => (byte)(0x30 + Number);

    /// <inheritdoc/>
    public override DeviceActivity Activity => !Busy ? DeviceActivity.Idle : _lastWrite ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public override DiskHead Head => new(Motor, Busy, (_lastSector - 1) / SectorsPerTrack, 0, ((_lastSector - 1) % SectorsPerTrack) + 1);

    // Enhanced density puts 26 sectors on a track; single and double density, 18.
    private int SectorsPerTrack => Disk?.SectorCount == 1040 ? 26 : 18;

    private bool Motor => _bus.Cycles - _lastAccess < MotorCycles;

    private bool Busy => _bus.Cycles - _lastAccess < SectorCycles * 4;

    /// <inheritdoc/>
    int? IAtariSioDevice.Accept(byte command, ushort aux)
    {
        _driveStatus &= unchecked((byte)~0x01);
        switch (command)
        {
            case 0x53:
            case 0x21:
                return 0;
            case 0x52:
                return ValidSector(aux) ? 0 : Fail();
            case 0x50:
            case 0x57:
                return Disk is { } disk && ValidSector(aux) ? disk.SizeOf(aux) : Fail();
            default:
                return Fail();
        }

        int? Fail()
        {
            _driveStatus |= 0x01;
            return null;
        }
    }

    /// <inheritdoc/>
    (bool Success, byte[] Data, int Cycles) IAtariSioDevice.Execute(byte command, ushort aux, ReadOnlySpan<byte> data, long cycle)
    {
        _lastAccess = cycle;
        switch (command)
        {
            case 0x53:
                return (true, [Status(), Controller(), 0xE0, 0x00], StatusCycles);
            case 0x52 when Disk is { } disk:
            {
                _lastSector = aux;
                _lastWrite = false;
                byte[] sector = new byte[disk.SizeOf(aux)];
                disk.ReadSector(aux, sector);
                _controllerStatus = 0xFF;
                return (true, sector, SectorCycles);
            }

            case 0x50 or 0x57 when Disk is { } disk:
            {
                _lastSector = aux;
                _lastWrite = true;
                if (disk.IsWriteProtected)
                {
                    _driveStatus |= 0x08;
                    _controllerStatus = 0xBF;
                    return (false, [], SectorCycles);
                }

                disk.WriteSector(aux, data);
                _driveStatus &= unchecked((byte)~0x08);
                _controllerStatus = 0xFF;
                return (true, [], command == 0x57 ? SectorCycles * 2 : SectorCycles);
            }

            default:
            {
                // Format: every sector cleared, and a bad sector list of none.
                byte[] list = new byte[Disk?.SectorSize ?? 128];
                list.AsSpan().Fill(0xFF);
                if (Disk is not { } formatted || formatted.IsWriteProtected)
                {
                    _controllerStatus = Disk is null ? (byte)0x7F : (byte)0xBF;
                    return (false, list, FormatCycles);
                }

                formatted.Format();
                _controllerStatus = 0xFF;
                return (true, list, FormatCycles);
            }
        }
    }

    // The drive status: bit 7 enhanced density, 5 double density, 4 the motor, 3 a write to a protected disk, 0 a bad
    // command frame.
    private byte Status()
    {
        int status = _driveStatus;
        if (Motor) { status |= 0x10; }
        if (Disk?.SectorSize == 256) { status |= 0x20; }
        if (Disk?.SectorCount == 1040) { status |= 0x80; }
        return (byte)status;
    }

    // The 1771's status, inverted: bit 7 low for no disk (not ready), bit 6 low for a write-protected disk.
    private byte Controller()
    {
        int status = _controllerStatus;
        if (Disk is null) { status &= 0x7F; }
        if (Disk?.IsWriteProtected == true) { status &= 0xBF; }
        return (byte)status;
    }

    private bool ValidSector(int sector) => Disk is { } disk && sector >= 1 && sector <= disk.SectorCount;
}
