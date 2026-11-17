// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A p-machine interpreter in memory: where it fetches each p-code, and where it keeps the p-machine's registers.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal's interpreters on the Apple II (<c>SYSTEM.APPLE</c>) and the Apple III (<c>SOS.INTERP</c>) keep the
///   registers in the same zero-page words: BASE, the outer block's mark stack control word (MSCW), at <c>$50</c>; MP,
///   the current procedure's, at <c>$52</c>; JTAB, its attributes, at <c>$54</c>; SEG, its segment's last word, at
///   <c>$56</c>; and IPC, the next p-code, at <c>$58</c>. Each fetches the next opcode with <c>LDA ($58),Y</c>, after
///   <c>LDY #0</c> on the Apple II and <c>LDY $70</c> (a flag that is zero while nothing traces) on the Apple III, and
///   handles <c>SLDC</c> at once (<c>BPL</c>) before doubling the opcode (<c>ASL</c>) to dispatch the rest.
///  </para>
///  <para>
///   The Apple III's interpreter runs with zero page at <c>$1A00</c>, where indirect reads use extended addressing:
///   each pointer's X-byte is beside its high byte, at the address XOR <c>$0C00</c>.
///  </para>
///  <para>
///   Apple Pascal 1.3 on a 128K IIe keeps code in the auxiliary 64K and fetches it with auxiliary reads switched on,
///   while the mark stack and variables stay in main memory: its SEG, JTAB and IPC point into the code bank.
///  </para>
/// </remarks>
/// <param name="Name">What it is, such as <c>Apple III Pascal (SOS.INTERP)</c>.</param>
/// <param name="Fetch">The address of the <c>LDA ($58),Y</c> that fetches each opcode.</param>
/// <param name="ZeroPage">Where its zero page is.</param>
/// <param name="Extended">Whether its pointers have X-bytes (the Apple III).</param>
/// <param name="CodeBank">
///  Where the code its SEG, JTAB and IPC point to is, without X-bytes: 0 for the memory the mark stack is in, and on the
///  Apple II 1 for the auxiliary 64K.
/// </param>
public sealed record PascalInterpreter(string Name, ushort Fetch, ushort ZeroPage, bool Extended, byte CodeBank = 0)
{
    /// <summary>
    ///  The zero-page offset of BASE.
    /// </summary>
    public const int BaseRegister = 0x50;

    /// <summary>
    ///  The zero-page offset of MP.
    /// </summary>
    public const int MarkRegister = 0x52;

    /// <summary>
    ///  The zero-page offset of JTAB.
    /// </summary>
    public const int JumpTableRegister = 0x54;

    /// <summary>
    ///  The zero-page offset of SEG.
    /// </summary>
    public const int SegmentRegister = 0x56;

    /// <summary>
    ///  The zero-page offset of IPC.
    /// </summary>
    public const int CodeRegister = 0x58;

    /// <summary>
    ///  Says whether the bytes at an address are an Apple Pascal interpreter's fetch.
    /// </summary>
    /// <param name="peek">Reads the memory the CPU sees.</param>
    /// <param name="fetch">The address of the <c>LDA ($58),Y</c>.</param>
    /// <returns>True for <c>LDA ($58),Y; BPL; ASL</c> after <c>LDY #0</c> or <c>LDY $70; BNE</c>.</returns>
    public static bool IsFetch(Func<ushort, byte> peek, ushort fetch)
    {
        ArgumentNullException.ThrowIfNull(peek);
        if (peek(fetch) != 0xB1
            || peek((ushort)(fetch + 1)) != CodeRegister
            || peek((ushort)(fetch + 2)) != 0x10
            || peek((ushort)(fetch + 4)) != 0x0A)
        {
            return false;
        }

        bool apple2 = peek((ushort)(fetch - 2)) == 0xA0 && peek((ushort)(fetch - 1)) == 0x00;
        bool apple3 = peek((ushort)(fetch - 4)) == 0xA4 && peek((ushort)(fetch - 3)) == 0x70 && peek((ushort)(fetch - 2)) == 0xD0;
        return apple2 || apple3;
    }

    /// <summary>
    ///  Looks for an interpreter's fetch in a range of memory.
    /// </summary>
    /// <param name="peek">Reads the memory the CPU sees.</param>
    /// <param name="start">The first address to look at.</param>
    /// <param name="end">The address after the last.</param>
    /// <returns>The fetch's address, or null.</returns>
    public static ushort? FindFetch(Func<ushort, byte> peek, int start, int end)
    {
        ArgumentNullException.ThrowIfNull(peek);
        for (int address = Math.Max(start, 4); address < end - 5; address++)
        {
            if (peek((ushort)address) == 0xB1 && IsFetch(peek, (ushort)address)) { return (ushort)address; }
        }

        return null;
    }

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="register">The register's zero-page offset, such as <see cref="CodeRegister"/>.</param>
    /// <returns>
    ///  Its value, with its X-byte on the Apple III, or the code bank for SEG, JTAB and IPC elsewhere.
    /// </returns>
    public PascalPointer Register(IPascalMemory memory, int register)
    {
        ArgumentNullException.ThrowIfNull(memory);
        ushort address = (ushort)(ZeroPage + register);
        ushort value = (ushort)(memory.Read(address, 0) | (memory.Read((ushort)(address + 1), 0) << 8));
        if (Extended) { return new PascalPointer(value, XByte(memory, (ushort)(address + 1))); }
        return new PascalPointer(value, register is BaseRegister or MarkRegister ? (byte)0 : CodeBank);
    }

    /// <summary>
    ///  Reads the X-byte for a pointer's high byte, at its address XOR <c>$0C00</c>; 0 where it reaches no bank.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="high">The address of the pointer's high byte, in zero page.</param>
    /// <returns>The X-byte, or 0.</returns>
    public static byte XByte(IPascalMemory memory, ushort high)
    {
        ArgumentNullException.ThrowIfNull(memory);
        byte value = memory.Read((ushort)(high ^ 0x0C00), 0);
        return (value & 0x80) != 0 ? value : (byte)0;
    }
}