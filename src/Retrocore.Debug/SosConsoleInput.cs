// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple3;

namespace Retrocore.Debug;

/// <summary>
///  Observes the keyboard route of a verified, relocated SOS console driver.
/// </summary>
internal sealed class SosConsoleInput
{
    private readonly Apple3DebugTarget _target;
    private readonly Apple3Bus _bus;
    private readonly Apple3MemoryArea _area;
    private readonly GuestInputPath _path;
    private readonly Func<bool> _active;
    private readonly ushort _wait;
    private readonly ushort _ack;
    private readonly ushort _admitted;
    private readonly ushort _driverEntry;
    private readonly ushort _irq;
    private readonly ushort _count;
    private readonly ushort _size;
    private readonly ushort _head;
    private readonly ushort _tail;
    private readonly ushort _reading;
    private readonly ushort _noWait;
    private readonly ushort _attention;
    private readonly ushort _open;
    private readonly ushort _dib;
    private readonly int _release;
    private readonly byte[] _code;
    private bool _cleared;

    private SosConsoleInput(Apple3DebugTarget target, AssemblyResult driver, ushort dib, byte bank, int release, Func<bool> active)
    {
        _target = target;
        _bus = target.Machine.Bus;
        _area = _bus.BankArea(bank);
        _active = active;
        _dib = dib;
        _release = release;
        _driverEntry = InputFirmware.Symbol(driver, "CNSLDH");
        _irq = InputFirmware.Symbol(driver, "KYBDMIH");
        _count = InputFirmware.Symbol(driver, "KEYCNT");
        _size = InputFirmware.Symbol(driver, "BUFSIZ");
        _head = InputFirmware.Symbol(driver, "BUFHEAD");
        _tail = InputFirmware.Symbol(driver, "BUFTAIL");
        _reading = InputFirmware.Symbol(driver, "READING");
        _noWait = InputFirmware.Symbol(driver, "NOWAIT");
        _attention = InputFirmware.Symbol(driver, "ATTNEVNT");
        _open = InputFirmware.Symbol(driver, "OPENFLG");

        ReadOnlySpan<byte> bytes = driver.Sections[0].Bytes.Span;
        int header = bytes[0] == 0xFF && bytes[1] == 0xFF ? 4 + (bytes[2] | (bytes[3] << 8)) : 0;
        int end = InputFirmware.Symbol(driver, "SCRNECHO");
        if (_irq < dib || end <= _irq || header + end - dib > bytes.Length)
        {
            _code = [];
        }
        else
        {
            _code = bytes.Slice(header + _irq - dib, end - _irq).ToArray();
            int wait = _code.AsSpan().IndexOf((ReadOnlySpan<byte>)[0xAD, (byte)_count, (byte)(_count >> 8), 0xF0, 0xFB]);
            int tail = _code.AsSpan().IndexOf((ReadOnlySpan<byte>)[0x8E, (byte)_tail, (byte)(_tail >> 8), 0x60]);
            int ack = _code.AsSpan().IndexOf((ReadOnlySpan<byte>)[0x8E, 0x10, 0xC0, 0x30]);
            if (wait >= 0) { _wait = (ushort)(_irq + wait); }
            if (tail >= 0) { _admitted = (ushort)(_irq + tail + 3); }
            if (ack >= 0) { _ack = (ushort)(_irq + ack + 3); }
        }

        _path = new(release == 0x1300 ? "sosConsole130" : "sosConsole131", "keyboardDevice", Send, Observe);
    }

    /// <summary>
    ///  Locates the wait, hardware acknowledgement, and software admission in a relocated SDK driver.
    /// </summary>
    /// <param name="target">The machine running the driver.</param>
    /// <param name="driver">The SDK build relocated to the driver's actual address.</param>
    /// <param name="dib">The device information block's address.</param>
    /// <param name="bank">The SOS bank number.</param>
    /// <param name="release">The console driver release in SOS's encoding.</param>
    /// <param name="active">Checks that the kernel still routes to the discovered device.</param>
    /// <returns>The profile, or null if its expected code is absent.</returns>
    internal static SosConsoleInput? Create(Apple3DebugTarget target, AssemblyResult driver, ushort dib, byte bank, int release, Func<bool> active)
    {
        SosConsoleInput console = new(target, driver, dib, bank, release, active);
        return console._wait != 0 && console._ack != 0 && console._admitted != 0 ? console : null;
    }

    /// <summary>
    ///  Recognizes an active blocking read with space for one keyboard interrupt.
    /// </summary>
    /// <returns>The verified path, if any.</returns>
    internal GuestInputPath? Waiting()
    {
        if (_target.ProgramCounter != _wait
            || !Mapped()
            || _bus.AppleIIMode
            || (_bus.Environment & Apple3Bus.IoEnable) == 0
            || _bus.KeysWaiting != 0
            || (_bus.Peek(0xFFEE) & 1) == 0
            || (_target.Machine.Processor.Registers.Status & StatusRegister.IRQBDisable) != 0
            || _bus.Peek(_count) != 0
            || _bus.Peek(_size) != 1
            || _bus.Peek(_head) != 0
            || _bus.Peek(_tail) != 0
            || (_bus.Peek(_reading) & 0x80) == 0
            || (_bus.Peek(_noWait) & 0x80) != 0
            || _bus.Peek(_attention) != 0
            || _bus.Peek(_open) == 0
            || (_bus.Peek((ushort)(_dib + 20)) & 0x80) == 0
            || InputFirmware.Word(_target, (ushort)(_dib + 2)) != _driverEntry
            || InputFirmware.Word(_target, (ushort)(_dib + 0x1E)) != _release
            || !_active()
            || !InputFirmware.Matches(_target, _irq, _code))
        {
            return null;
        }

        return _path;
    }

    private bool Mapped() => _bus.ReadArea(_wait) == _area;

    private InputReceipt Send(int code)
    {
        _cleared = false;
        return _target.Key(code) ? InputReceipt.Pending : InputReceipt.Rejected;
    }

    private InputReceipt Observe(int code)
    {
        if (_bus.KeysWaiting != 0) { return InputReceipt.Pending; }
        if (!_target.IsInstructionBoundary) { return InputReceipt.Pending; }
        ProcessorCycle last = _target.LastCycle;
        bool mapped = Mapped();
        if (mapped && _target.ProgramCounter == _ack && last.Operation == BusOperation.Write && last.Address == 0xC010)
        {
            _cleared = true;
            return InputReceipt.Acknowledged;
        }

        if (_cleared
            && mapped
            && _target.ProgramCounter == _admitted
            && last.Operation == BusOperation.Write
            && last.Address == _tail
            && _bus.Peek(_count) == 1)
        {
            return InputReceipt.Accepted;
        }

        return !_cleared || (mapped && _target.ProgramCounter == _wait)
            ? InputReceipt.Unconfirmed
            : InputReceipt.Acknowledged;
    }
}
