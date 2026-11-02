// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Addressing modes used by 6502 instructions.
///  Numeric values are part of the packed opcode table format.
/// </summary>
public enum AddressMode : byte
{
    /// <summary>
    ///  Absolute. The second and third bytes of the instruction are the address. Mnemonic:
    ///  <code>a</code>
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The low byte of the address (ADL) preceeds the high byte (ADH).
    ///  </para>
    /// </remarks>
    Absolute = 0x00,

    /// <summary>
    ///  Absolute indexed indirect. Only used with the <see cref="Instruction.JMP"/> instruction. The second and
    ///  third bytes of the instruction are the base address. The X Index Register is added to this address and
    ///  loaded into the Program Counter (PC). Mnemonic:
    ///  <code>(a,x)</code>
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The low byte of the address (ADL) preceeds the high byte (ADH).
    ///  </para>
    /// </remarks>
    AbsoluteIndexedIndirect = 0x01,

    /// <summary>
    ///  Absolute indexed with X. The second and third bytes of the instruction are the base address. The X Index
    ///  Register is added to this address to get the effective address. Mnemonic:
    ///  <code>a,x</code>
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The low byte of the address (ADL) preceeds the high byte (ADH).
    ///  </para>
    /// </remarks>
    AbsoluteIndexedX = 0x02,

    /// <summary>
    ///  Absolute indexed with Y. The second and third bytes of the instruction are the base address. The Y Index
    ///  Register is added to this address to get the effective address. Mnemonic:
    ///  <code>a,y</code>
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The low byte of the address (ADL) preceeds the high byte (ADH).
    ///  </para>
    /// </remarks>
    AbsoluteIndexedY = 0x03,

    /// <summary>
    ///  Absolute indirect. Only used with the <see cref="Instruction.JMP"/> instruction. The second and third
    ///  bytes of the instruction are the address that will be loaded into the Program Counter (PC). Mnemonic:
    ///  <code>(a)</code>
    /// </summary>
    AbsoluteIndirect = 0x04,

    /// <summary>
    ///  Accumulator. With Accumulator addressing the operand is implied as the Accumulator and therefore only a
    ///  single byte forms the instruction. Mnemonic:
    ///  <code>A</code>
    /// </summary>
    Accumulator = 0x05,

    /// <summary>
    ///  Immediate. With Immediate Addressing the operand is the second byte of the instruction. Mnemonic:
    ///  <code>#</code>
    /// </summary>
    Immediate = 0x06,

    /// <summary>
    ///  Implied. Implied addressing uses a single byte instruction. The operand is implicitly defined by the
    ///  instruction. Mnemonic:
    ///  <code>i</code>
    /// </summary>
    Implied = 0x07,

    /// <summary>
    ///  Program counter relative. Used with the Branch instructions. If the condition being tested is met, the
    ///  second byte of the instruction is added to the Program Counter (PC) and program control is transferred to
    ///  the new memory location. Mnemonic:
    ///  <code>r</code>
    /// </summary>
    ProgramCounterRelative = 0x08,

    /// <summary>
    ///  Stack.
    ///  <code>s</code>
    /// </summary>
    Stack = 0x09,

    /// <summary>
    ///  Zero page. With Zero Page (zp) addressing the second byte of the instruction is the address of the operand
    ///  in page zero. Mnemonic:
    ///  <code>zp</code>
    /// </summary>
    ZeroPage = 0x0A,

    /// <summary>
    ///  Zero page indexed indirect.
    ///  <code>(zp,x)</code>
    /// </summary>
    ZeroPageIndexedIndirect = 0x0B,

    /// <summary>
    ///  Zero page indexed with X.
    ///  <code>zp,x</code>
    /// </summary>
    ZeroPageIndexedX = 0x0C,

    /// <summary>
    ///  Zero page indexed with Y.
    ///  <code>zp,y</code>
    /// </summary>
    ZeroPageIndexedY = 0x0D,

    /// <summary>
    ///  Zero page indirect.
    ///  <code>(zp)</code>
    /// </summary>
    ZeroPageIndirect = 0x0E,

    /// <summary>
    ///  Zero page indirect indexed with Y.
    ///  <code>(zp),y</code>
    /// </summary>
    ZeroPageIndirectIndexedY = 0x0F,

    /// <summary>
    ///  Zero-page bit test followed by a signed program-counter-relative displacement.
    /// </summary>
    ZeroPageRelative = 0x10
}
