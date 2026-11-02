// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Assembler;

/// <summary>
///  Encoding constants shared by the linked assembler bootstrap and runtime disassembler.
/// </summary>
internal static class InstructionEncoding
{
    private static readonly string[] s_modeNames = Enum.GetNames(typeof(AddressMode));

    /// <summary>
    ///  The number of bytes addressable by a 16-bit CPU.
    /// </summary>
    internal const int AddressSpaceSize = ushort.MaxValue + 1;

    /// <summary>
    ///  The number of opcode encodings in a complete CPU map.
    /// </summary>
    internal const int OpcodeCount = byte.MaxValue + 1;

    /// <summary>
    ///  The byte count of a packed opcode, addressing-mode and instruction metadata entry.
    /// </summary>
    internal const int PackedOpcodeSize = 3;

    /// <summary>
    ///  The addressing-mode field's offset within a packed entry.
    /// </summary>
    internal const int AddressModeFieldOffset = 1;

    /// <summary>
    ///  The instruction field's offset within a packed entry.
    /// </summary>
    internal const int InstructionFieldOffset = 2;

    /// <summary>
    ///  The number of bits in an encoded byte.
    /// </summary>
    internal const int BitsPerByte = 8;

    /// <summary>
    ///  The number of bit positions supported by numbered bit instructions.
    /// </summary>
    internal const int BitOperationCount = BitsPerByte;

    /// <summary>
    ///  The size of an instruction with no encoded operand.
    /// </summary>
    internal const int OpcodeByteCount = sizeof(byte);

    /// <summary>
    ///  The size of an instruction with a single-byte operand.
    /// </summary>
    internal const int ByteOperandInstructionSize = OpcodeByteCount + sizeof(byte);

    /// <summary>
    ///  The size of an instruction with a word operand or zero-page/relative operand pair.
    /// </summary>
    internal const int WordOperandInstructionSize = OpcodeByteCount + sizeof(ushort);

    /// <summary>
    ///  The official single-byte NOP encoding, preferred over NMOS aliases.
    /// </summary>
    internal const byte OfficialNop = 0xEA;

    /// <summary>
    ///  The NMOS alternate immediate SBC encoding.
    /// </summary>
    internal const byte UndocumentedImmediateSbc = 0xEB;

    private const int BitNumberShift = 4;

    /// <summary>
    ///  Gets an encoding length for both assembler layout and disassembly.
    /// </summary>
    /// <param name="mode">The existing CPU addressing mode.</param>
    /// <returns>The number of encoded bytes.</returns>
    internal static int GetSize(AddressMode mode) => mode switch
    {
        AddressMode.Implied or AddressMode.Accumulator or AddressMode.Stack => OpcodeByteCount,
        AddressMode.Immediate
            or AddressMode.ProgramCounterRelative
            or AddressMode.ZeroPage
            or AddressMode.ZeroPageIndexedIndirect
            or AddressMode.ZeroPageIndexedX
            or AddressMode.ZeroPageIndexedY
            or AddressMode.ZeroPageIndirect
            or AddressMode.ZeroPageIndirectIndexedY => ByteOperandInstructionSize,
        AddressMode.Absolute
            or AddressMode.AbsoluteIndexedIndirect
            or AddressMode.AbsoluteIndexedX
            or AddressMode.AbsoluteIndexedY
            or AddressMode.AbsoluteIndirect
            or AddressMode.ZeroPageRelative => WordOperandInstructionSize,
        _ => throw new ArgumentOutOfRangeException(nameof(mode))
    };

    /// <summary>
    ///  Extracts the bit number from the shared BBR/BBS/RMB/SMB opcode layout.
    /// </summary>
    /// <param name="opcode">The encoded instruction byte.</param>
    /// <returns>The numbered bit position.</returns>
    internal static int GetBitNumber(byte opcode) => (opcode >> BitNumberShift) & (BitOperationCount - 1);

    /// <summary>
    ///  Gets a cached mode name for public source mappings without boxing or allocating enum text.
    /// </summary>
    /// <param name="mode">The canonical CPU addressing mode.</param>
    /// <returns>The metadata name.</returns>
    internal static string GetModeName(AddressMode mode) => (byte)mode < s_modeNames.Length
        ? s_modeNames[(byte)mode] : throw new ArgumentOutOfRangeException(nameof(mode));
}
