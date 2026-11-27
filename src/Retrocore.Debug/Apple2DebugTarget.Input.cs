// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

internal sealed partial class Apple2DebugTarget
{
    private const ushort KeyboardHook = 0x0038;
    private const ushort KeyboardIn = 0xFD1B;
    private const ushort KeyboardStrobe = 0xC010;
    private ushort _poll40;
    private ushort _poll80;
    private ushort _hook80;
    private ushort _keyReturn80;
    private ushort _escapeReturn80;
    private GuestInputPath? _input40;
    private GuestInputPath? _input80;
    private PascalKeyboard? _pascalKeyboard;
    private bool _triedPascalKeyboard;

    /// <inheritdoc/>
    public bool SupportsGuestInput => true;

    /// <inheritdoc/>
    public int? PendingKeys => _machine.Bus.KeysWaiting;

    private void AddInputFirmware(AssemblyResult? monitor, AssemblyResult? firmware)
    {
        ReadOnlySpan<byte> rom = _machine.Bus.Roms.System;
        if (monitor is not null && rom[(SdkModules.MonitorOrigin - 0xC000)..].SequenceEqual(monitor.Sections[0].Bytes.Span))
        {
            if (!_model.IsIIe())
            {
                _poll40 = InputFirmware.Symbol(monitor, "KeyboardIn::Check");
                ushort clear = InputFirmware.After(monitor, _poll40, 16, [0xAD, 0x00, 0xC0, 0x2C, 0x10, 0xC0]);
                if (_poll40 != 0 && clear != 0) { _input40 = Apple2KeyboardInput("apple2Monitor", clear); }
            }
        }
        else
        {
            return;
        }

        if (firmware is null || !rom.Slice(SdkModules.FirmwareOrigin - 0xC000, SdkModules.FirmwareSize)
            .SequenceEqual(firmware.Sections[0].Bytes.Span))
        {
            return;
        }

        bool enhanced = _model == Apple2Model.IIeEnhanced;
        _poll40 = InputFirmware.Symbol(firmware, enhanced ? "Functions::GetKey40::CheckKey" : "Functions::PollKeyboard::ReadKeyboard");
        ushort take40 = enhanced ? _poll40 : InputFirmware.Symbol(firmware, "Functions::GetKey::GotKey");
        ushort clear40 = InputFirmware.After(firmware, take40, 32, [0xAD, 0x00, 0xC0, 0x8D, 0x10, 0xC0]);
        if (_poll40 != 0 && clear40 != 0)
        {
            _input40 = Apple2KeyboardInput(enhanced ? "apple2eEnhanced40" : "apple2eOriginal40", clear40);
        }

        _poll80 = InputFirmware.Symbol(firmware, "WaitForKey::Poll");
        _hook80 = InputFirmware.Symbol(firmware, "BasicInput");
        ushort wait80 = InputFirmware.Symbol(firmware, "WaitForKey");
        ushort clear80 = InputFirmware.After(firmware, _poll80, 8, [0x8D, 0x10, 0xC0]);
        Span<byte> call = [0x20, (byte)wait80, (byte)(wait80 >> 8)];
        _keyReturn80 = InputFirmware.After(firmware, InputFirmware.Symbol(firmware, "CharacterIo::Input::NextKey"), 12, call);
        _escapeReturn80 = InputFirmware.After(firmware, InputFirmware.Symbol(firmware, "CharacterIo::EscapeMode"), 12, call);
        if (_poll80 != 0 && clear80 != 0 && _hook80 != 0 && _keyReturn80 != 0 && _escapeReturn80 != 0)
        {
            _input80 = Apple2KeyboardInput(enhanced ? "apple2eEnhanced80" : "apple2eOriginal80", clear80);
        }
    }

    /// <inheritdoc/>
    public GuestInputPath? WaitingForInput()
    {
        if (_machine.Bus.KeysWaiting != 0) { return null; }
        ushort pc = ProgramCounter;
        if (pc is >= 0xD000 and < 0xE000 && _machine.Bus.LanguageCardRead && _machine.Bus.LanguageCardBank2)
        {
            if (!_triedPascalKeyboard)
            {
                _triedPascalKeyboard = true;
                _pascalKeyboard = PascalKeyboard.Create(this);
            }

            return _pascalKeyboard?.Waiting(pc);
        }

        if (pc != _poll40 && pc != _poll80) { return null; }
        if (_machine.Bus.ReadArea(pc) != Apple2MemoryArea.SystemRom || _machine.Bus.FirmwareCardActive) { return null; }
        ushort hook = InputFirmware.Word(this, KeyboardHook);
        if (pc == _poll40 && hook == KeyboardIn && _machine.Bus.ReadArea(hook) == Apple2MemoryArea.SystemRom)
        {
            return _input40;
        }

        if (pc == _poll80 && (hook == _hook80 || hook == KeyboardIn) && _input80 is not null)
        {
            ushort caller = (ushort)(InputFirmware.ReturnAddress(this) + 1);
            if (caller == _keyReturn80 || caller == _escapeReturn80) { return _input80; }
        }

        return null;
    }

    private GuestInputPath Apple2KeyboardInput(string profile, ushort cleared) => new(profile, "keyboardDevice",
        code => Key(code) ? InputReceipt.Pending : InputReceipt.Rejected,
        code =>
        {
            if (_machine.Bus.KeysWaiting != 0) { return InputReceipt.Pending; }
            int expected = (!_model.IsIIe() && code is >= 'a' and <= 'z' ? code - 32 : code) | 0x80;
            return IsInstructionBoundary
                && ProgramCounter == cleared
                && LastCycle.Address == KeyboardStrobe
                && _machine.Processor.Registers.Accumulator == expected
                && _machine.Bus.ReadArea(cleared) == Apple2MemoryArea.SystemRom
                    ? InputReceipt.Accepted
                    : InputReceipt.Unconfirmed;
        });

}
