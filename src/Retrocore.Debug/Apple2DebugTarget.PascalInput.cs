// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

internal sealed partial class Apple2DebugTarget
{
    /// <summary>
    ///  The blocking, built-in keyboard route of the Pascal 1.1 BIOS console.
    /// </summary>
    private sealed class PascalKeyboard
    {
        private readonly Apple2DebugTarget _target;
        private readonly GuestInputPath _path;
        private readonly AssemblyResult _assembly;
        private readonly ushort _read;
        private readonly ushort _wait;
        private readonly ushort _check;
        private readonly ushort _ack;
        private readonly ushort _stored;
        private readonly ushort _next;
        private readonly ushort _head;
        private readonly ushort _tail;
        private readonly ushort _data;
        private readonly ushort _slot;
        private readonly ushort _flags;
        private readonly int _size;
        private byte _writeIndex;
        private bool _cleared;

        private PascalKeyboard(Apple2DebugTarget target, AssemblyResult assembly)
        {
            _target = target;
            _assembly = assembly;
            _read = InputFirmware.Symbol(assembly, "ConsoleRead");
            _wait = InputFirmware.Symbol(assembly, "ConsoleRead::FromTypeAhead");
            _check = InputFirmware.Symbol(assembly, "ConsoleCheck");
            ushort byCard = InputFirmware.Symbol(assembly, "ConsoleCheck::ByCard");
            _ack = InputFirmware.After(assembly, byCard, 64, [0x8D, 0x10, 0xC0, 0x29, 0x7F]);
            if (_ack != 0) { _ack -= 2; }
            _stored = InputFirmware.Symbol(assembly, "ConsoleCheck::CheckStopped");
            _next = InputFirmware.Symbol(assembly, "NextTypeAhead");
            _head = InputFirmware.Symbol(assembly, "TypeAheadOut");
            _tail = InputFirmware.Symbol(assembly, "TypeAheadIn");
            _data = InputFirmware.Symbol(assembly, "TypeAhead");
            _slot = (ushort)(InputFirmware.Symbol(assembly, "SlotTypes") + InputFirmware.Symbol(assembly, "CONSOLE_SLOT") - 1);
            _flags = InputFirmware.Symbol(assembly, "ConsoleFlags");
            _size = InputFirmware.Symbol(assembly, "TYPE_AHEAD_SIZE");
            _path = new("applePascal11Console", "keyboardDevice", Send, Observe);
        }

        /// <summary>
        ///  Builds the supported BIOS signatures from the SDK.
        /// </summary>
        /// <param name="target">The machine with the language card mapped.</param>
        /// <returns>The profile, or null if its SDK sources are unavailable.</returns>
        internal static PascalKeyboard? Create(Apple2DebugTarget target)
        {
            string path = Path.Join(SdkModules.SdkDirectory, "Pascal", "Interpreter", "1.1", "SYSTEM.APPLE.asm");
            string config = Path.ChangeExtension(path, ".cfg");
            if (!File.Exists(path) || !File.Exists(config)) { return null; }
            return new(target, SourceBuild.Assemble(path, AssemblyDialect.Native, "Mos6502", 0xD000, config));
        }

        /// <summary>
        ///  Recognizes the console read with its ordinary keyboard route and empty type-ahead buffer.
        /// </summary>
        /// <param name="pc">The program counter between instructions in language-card bank two.</param>
        /// <returns>The matching path, if any.</returns>
        internal GuestInputPath? Waiting(ushort pc)
        {
            if (pc != _wait
                || _read == 0
                || _check == 0
                || _ack == 0
                || _stored == 0
                || _size == 0
                || _target.Peek(_slot) is 3 or 4 or 6
                || (_target.Peek(_flags) & 0x80) != 0
                || _target.Peek(_head) != _target.Peek(_tail)
                || _target.Peek(_tail) >= _size
                || _target._machine.Bus.ReadArea(_tail) != _target._machine.Bus.WriteArea(_tail)
                || !InputFirmware.Matches(_target, _read, InputFirmware.Bytes(_assembly, _read, _wait - _read + 17))
                || !InputFirmware.Matches(_target, _check, InputFirmware.Bytes(_assembly, _check, _next - _check + 7)))
            {
                return null;
            }

            return _path;
        }

        private InputReceipt Send(int code)
        {
            _writeIndex = (byte)((_target.Peek(_tail) + 1) % _size);
            _cleared = false;
            return _target.Key(code) ? InputReceipt.Pending : InputReceipt.Rejected;
        }

        private InputReceipt Observe(int code)
        {
            Apple2Bus bus = _target._machine.Bus;
            if (bus.KeysWaiting != 0 || !_target.IsInstructionBoundary) { return InputReceipt.Pending; }
            if (!bus.LanguageCardRead || !bus.LanguageCardBank2) { return InputReceipt.Unconfirmed; }
            ProcessorCycle last = _target.LastCycle;
            if (_target.ProgramCounter == _ack && last.Operation == BusOperation.Write && last.Address == KeyboardStrobe)
            {
                _cleared = true;
                return InputReceipt.Acknowledged;
            }

            if (_cleared
                && _target.ProgramCounter == _stored
                && _target.Peek(_tail) == _writeIndex
                && last.Operation == BusOperation.Write
                && last.Address == _data + _writeIndex)
            {
                return InputReceipt.Accepted;
            }

            // Strobe clear precedes the ring store. Looping back without storing the byte is not admission.
            return !_cleared || _target.ProgramCounter == _wait
                ? InputReceipt.Unconfirmed
                : InputReceipt.Acknowledged;
        }
    }
}
