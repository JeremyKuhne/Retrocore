// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  What the core does when the current machine cycle ends: each is one instruction family, continued by step.
/// </summary>
internal enum Z80Operation : byte
{
    /// <summary>
    ///  At an instruction boundary.
    /// </summary>
    None,

    /// <summary>
    ///  An opcode was fetched, unprefixed or after DD or FD.
    /// </summary>
    Decode,

    /// <summary>
    ///  A CB opcode was fetched.
    /// </summary>
    DecodeBits,

    /// <summary>
    ///  An ED opcode was fetched.
    /// </summary>
    DecodeExtended,

    /// <summary>
    ///  DD CB or FD CB: the displacement, then the opcode, then the indexed operation.
    /// </summary>
    IndexBits,

    /// <summary>
    ///  <c>LD r,n</c>.
    /// </summary>
    LoadImmediate,

    /// <summary>
    ///  <c>LD r,[HL]</c> and <c>LD r,[IX+d]</c>.
    /// </summary>
    LoadMemory,

    /// <summary>
    ///  <c>LD [HL],r</c> and <c>LD [IX+d],r</c>.
    /// </summary>
    StoreMemory,

    /// <summary>
    ///  <c>LD [HL],n</c> and <c>LD [IX+d],n</c>.
    /// </summary>
    StoreImmediate,

    /// <summary>
    ///  <c>LD A,[BC]</c> and <c>LD A,[DE]</c>.
    /// </summary>
    LoadIndirect,

    /// <summary>
    ///  <c>LD [BC],A</c> and <c>LD [DE],A</c>.
    /// </summary>
    StoreIndirect,

    /// <summary>
    ///  <c>LD A,[nn]</c>.
    /// </summary>
    LoadAbsolute,

    /// <summary>
    ///  <c>LD [nn],A</c>.
    /// </summary>
    StoreAbsolute,

    /// <summary>
    ///  <c>LD rr,nn</c>.
    /// </summary>
    LoadPairImmediate,

    /// <summary>
    ///  <c>LD rr,[nn]</c>.
    /// </summary>
    LoadPairAbsolute,

    /// <summary>
    ///  <c>LD [nn],rr</c>.
    /// </summary>
    StorePairAbsolute,

    /// <summary>
    ///  Internal T-states, then the instruction ends.
    /// </summary>
    Delay,

    /// <summary>
    ///  <c>PUSH rr</c>.
    /// </summary>
    Push,

    /// <summary>
    ///  <c>POP rr</c>.
    /// </summary>
    Pop,

    /// <summary>
    ///  <c>EX [SP],HL</c>.
    /// </summary>
    ExchangeStack,

    /// <summary>
    ///  An ALU operation with an immediate.
    /// </summary>
    ArithmeticImmediate,

    /// <summary>
    ///  An ALU operation with <c>[HL]</c> or <c>[IX+d]</c>.
    /// </summary>
    ArithmeticMemory,

    /// <summary>
    ///  <c>INC</c> or <c>DEC</c> of <c>[HL]</c> or <c>[IX+d]</c>.
    /// </summary>
    StepMemory,

    /// <summary>
    ///  A CB operation on <c>[HL]</c>.
    /// </summary>
    BitsMemory,

    /// <summary>
    ///  <c>JP nn</c> and <c>JP cc,nn</c>.
    /// </summary>
    Jump,

    /// <summary>
    ///  <c>JR e</c> and <c>JR cc,e</c>.
    /// </summary>
    JumpRelative,

    /// <summary>
    ///  <c>DJNZ e</c>.
    /// </summary>
    DecrementJump,

    /// <summary>
    ///  <c>CALL nn</c> and <c>CALL cc,nn</c>.
    /// </summary>
    Call,

    /// <summary>
    ///  <c>RET</c>, <c>RET cc</c>, <c>RETI</c> and <c>RETN</c>.
    /// </summary>
    Return,

    /// <summary>
    ///  <c>RST p</c>, and the push of an interrupt.
    /// </summary>
    Restart,

    /// <summary>
    ///  <c>IN A,[n]</c>.
    /// </summary>
    InputImmediate,

    /// <summary>
    ///  <c>OUT [n],A</c>.
    /// </summary>
    OutputImmediate,

    /// <summary>
    ///  <c>IN r,[C]</c>.
    /// </summary>
    InputPort,

    /// <summary>
    ///  <c>OUT [C],r</c>.
    /// </summary>
    OutputPort,

    /// <summary>
    ///  <c>LDI</c>, <c>LDD</c>, <c>LDIR</c>, <c>LDDR</c>.
    /// </summary>
    BlockLoad,

    /// <summary>
    ///  <c>CPI</c>, <c>CPD</c>, <c>CPIR</c>, <c>CPDR</c>.
    /// </summary>
    BlockCompare,

    /// <summary>
    ///  <c>INI</c>, <c>IND</c>, <c>INIR</c>, <c>INDR</c>.
    /// </summary>
    BlockInput,

    /// <summary>
    ///  <c>OUTI</c>, <c>OUTD</c>, <c>OTIR</c>, <c>OTDR</c>.
    /// </summary>
    BlockOutput,

    /// <summary>
    ///  <c>RRD</c> and <c>RLD</c>.
    /// </summary>
    RotateDigit,

    /// <summary>
    ///  A non-maskable interrupt.
    /// </summary>
    NonMaskable,

    /// <summary>
    ///  A maskable interrupt in mode 1 or 2.
    /// </summary>
    Interrupt
}
