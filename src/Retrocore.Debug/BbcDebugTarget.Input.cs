// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

internal sealed partial class BbcDebugTarget
{
    /// <summary>
    ///  An untimed MOS keyboard wait and its default logical keyboard ring.
    /// </summary>
    private sealed class BbcMosInput
    {
        private readonly BbcDebugTarget _target;
        private readonly GuestInputPath _path;
        private readonly ushort _wait;
        private readonly ushort _timed;
        private readonly ushort _rdch;
        private readonly ushort _remove;
        private readonly ushort _insert;
        private readonly ushort _key;

        /// <summary>
        ///  Locates the wait and its default vectors in the matched MOS ROM.
        /// </summary>
        /// <param name="target">The BBC Micro using the ROM.</param>
        /// <param name="mos">The build that matched its active MOS.</param>
        internal BbcMosInput(BbcDebugTarget target, AssemblyResult mos)
        {
            _target = target;
            _wait = InputFirmware.Symbol(mos, "READ_INPUT_CHARACTER_WAIT");
            _timed = InputFirmware.Symbol(mos, "RDCH_CHARACTER");
            _rdch = InputFirmware.Symbol(mos, "RDCHV_DEFAULT");
            _remove = InputFirmware.Symbol(mos, "REMV_DEFAULT");
            _insert = InputFirmware.Symbol(mos, "INSV_DEFAULT");
            _key = InputFirmware.Symbol(mos, "KEYV_DEFAULT");
            _path = new("bbcMos120Rdch", "mosKeyboardBuffer", Send);
        }

        /// <summary>
        ///  Checks that the reader and ring are available without redirected input or key expansion.
        /// </summary>
        /// <param name="pc">The program counter between instructions.</param>
        /// <returns>The verified keyboard profile, if any.</returns>
        internal GuestInputPath? Waiting(ushort pc)
        {
            if (_wait == 0
                || pc != _wait
                || _rdch == 0
                || _remove == 0
                || _insert == 0
                || _key == 0
                || _target._machine.Keyboard.IsTyping
                || _target._machine.Keyboard.AnyPressed
                || _target.Peek(_timed) != 0
                || (_target.Peek(0x00FF) & 0x80) != 0 // timed read or Escape
                || _target.Peek(0x0241) != 0
                || _target.Peek(0x0256) != 0 // serial or *EXEC
                || _target.Peek(0x0259) != 0
                || (_target.Peek(0x025F) & 0x80) != 0
                || _target.Peek(0x0268) != 0
                || InputFirmware.Word(_target, 0x0210) != _rdch
                || InputFirmware.Word(_target, 0x022C) != _remove
                || InputFirmware.Word(_target, 0x022A) != _insert
                || InputFirmware.Word(_target, 0x0228) != _key
                || _target.Peek(0x02E1) < 0xE0
                || _target.Peek(0x02D8) != _target.Peek(0x02E1))
            {
                return null;
            }

            return _path;
        }

        private InputReceipt Send(int code)
        {
            if (code is not (>= 0x20 and < 0x7F or '\r' or '\t')) { return InputReceipt.Rejected; }
            byte tail = _target.Peek(0x02E1);
            _target.Poke((ushort)(0x0300 + tail), (byte)code);
            _target.Poke(0x02E1, tail == 0xFF ? (byte)0xE0 : (byte)(tail + 1));
            return InputReceipt.Accepted;
        }
    }
}
