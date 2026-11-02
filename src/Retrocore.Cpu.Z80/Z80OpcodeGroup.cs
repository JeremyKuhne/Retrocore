// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  What an unprefixed opcode, or one after DD or FD, does once fetched; <see cref="Z80Decoding"/> maps each
///  opcode to one so decoding takes a single jump.
/// </summary>
internal enum Z80OpcodeGroup : byte
{
    /// <summary>
    ///  <c>NOP</c>.
    /// </summary>
    Nop,

    /// <summary>
    ///  <c>EX AF,AF'</c>.
    /// </summary>
    ExchangeAF,

    /// <summary>
    ///  <c>DJNZ e</c>.
    /// </summary>
    DecrementJump,

    /// <summary>
    ///  <c>JR e</c> and <c>JR cc,e</c>.
    /// </summary>
    JumpRelative,

    /// <summary>
    ///  <c>LD rp,nn</c>.
    /// </summary>
    LoadPairImmediate,

    /// <summary>
    ///  <c>ADD HL,rp</c>.
    /// </summary>
    AddPair,

    /// <summary>
    ///  <c>LD [BC],A</c> and <c>LD [DE],A</c>.
    /// </summary>
    StoreIndirect,

    /// <summary>
    ///  <c>LD [nn],HL</c>.
    /// </summary>
    StorePairAbsolute,

    /// <summary>
    ///  <c>LD [nn],A</c>.
    /// </summary>
    StoreAbsolute,

    /// <summary>
    ///  <c>LD A,[BC]</c> and <c>LD A,[DE]</c>.
    /// </summary>
    LoadIndirect,

    /// <summary>
    ///  <c>LD HL,[nn]</c>.
    /// </summary>
    LoadPairAbsolute,

    /// <summary>
    ///  <c>LD A,[nn]</c>.
    /// </summary>
    LoadAbsolute,

    /// <summary>
    ///  <c>INC rp</c> and <c>DEC rp</c>.
    /// </summary>
    StepPair,

    /// <summary>
    ///  <c>INC [HL]</c> and <c>DEC [HL]</c>.
    /// </summary>
    StepMemory,

    /// <summary>
    ///  <c>INC r</c> and <c>DEC r</c>.
    /// </summary>
    StepRegister,

    /// <summary>
    ///  <c>LD [HL],n</c>.
    /// </summary>
    StoreImmediate,

    /// <summary>
    ///  <c>LD r,n</c>.
    /// </summary>
    LoadImmediate,

    /// <summary>
    ///  The accumulator and flag operations: <c>RLCA</c> through <c>CCF</c>.
    /// </summary>
    Accumulator,

    /// <summary>
    ///  <c>HALT</c>.
    /// </summary>
    Halt,

    /// <summary>
    ///  <c>LD r,[HL]</c>.
    /// </summary>
    LoadMemory,

    /// <summary>
    ///  <c>LD [HL],r</c>.
    /// </summary>
    StoreMemory,

    /// <summary>
    ///  <c>LD r,r'</c>.
    /// </summary>
    LoadRegister,

    /// <summary>
    ///  An ALU operation on <c>[HL]</c>.
    /// </summary>
    ArithmeticMemory,

    /// <summary>
    ///  An ALU operation on a register.
    /// </summary>
    ArithmeticRegister,

    /// <summary>
    ///  <c>RET cc</c>.
    /// </summary>
    ReturnConditional,

    /// <summary>
    ///  <c>POP rp</c>.
    /// </summary>
    Pop,

    /// <summary>
    ///  <c>RET</c>.
    /// </summary>
    Return,

    /// <summary>
    ///  <c>EXX</c>.
    /// </summary>
    ExchangeAll,

    /// <summary>
    ///  <c>JP [HL]</c>.
    /// </summary>
    JumpIndex,

    /// <summary>
    ///  <c>LD SP,HL</c>.
    /// </summary>
    LoadStackIndex,

    /// <summary>
    ///  <c>JP cc,nn</c>.
    /// </summary>
    JumpConditional,

    /// <summary>
    ///  <c>JP nn</c>.
    /// </summary>
    Jump,

    /// <summary>
    ///  The CB prefix.
    /// </summary>
    Bits,

    /// <summary>
    ///  <c>OUT [n],A</c>.
    /// </summary>
    OutputImmediate,

    /// <summary>
    ///  <c>IN A,[n]</c>.
    /// </summary>
    InputImmediate,

    /// <summary>
    ///  <c>EX [SP],HL</c>.
    /// </summary>
    ExchangeStack,

    /// <summary>
    ///  <c>EX DE,HL</c>.
    /// </summary>
    ExchangeDEHL,

    /// <summary>
    ///  <c>DI</c>.
    /// </summary>
    DisableInterrupts,

    /// <summary>
    ///  <c>EI</c>.
    /// </summary>
    EnableInterrupts,

    /// <summary>
    ///  <c>CALL cc,nn</c>.
    /// </summary>
    CallConditional,

    /// <summary>
    ///  <c>PUSH rp</c>.
    /// </summary>
    Push,

    /// <summary>
    ///  <c>CALL nn</c>.
    /// </summary>
    Call,

    /// <summary>
    ///  The DD and FD prefixes.
    /// </summary>
    IndexPrefix,

    /// <summary>
    ///  The ED prefix.
    /// </summary>
    Extended,

    /// <summary>
    ///  An ALU operation on an immediate byte.
    /// </summary>
    ArithmeticImmediate,

    /// <summary>
    ///  <c>RST p</c>.
    /// </summary>
    Restart
}
