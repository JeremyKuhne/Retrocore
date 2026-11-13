// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Active MC6809 instruction family in progress.
/// </summary>
internal enum M6809Operation : byte
{
    /// <summary>
    ///  No instruction in progress (at an instruction boundary).
    /// </summary>
    None,

    /// <summary>
    ///  Fetch the second opcode byte of a <c>$10</c> or <c>$11</c> paged instruction.
    /// </summary>
    DecodePage,

    /// <summary>
    ///  Inherent instruction spending remaining internal cycles before applying its effect.
    /// </summary>
    Inherent,

    /// <summary>
    ///  8-bit immediate instruction fetching its immediate byte on cycle 2.
    /// </summary>
    Immediate8,

    /// <summary>
    ///  16-bit immediate load (<c>LDD</c>, <c>LDX</c>, <c>LDY</c>, <c>LDU</c>, <c>LDS</c>).
    /// </summary>
    Immediate16Load,

    /// <summary>
    ///  16-bit immediate arithmetic/compare (<c>SUBD</c>, <c>ADDD</c>, <c>CMPD</c>, <c>CMPX</c>, <c>CMPY</c>, <c>CMPU</c>, <c>CMPS</c>).
    /// </summary>
    Immediate16Alu,

    /// <summary>
    ///  8-bit relative branch (<c>BRA</c>, <c>BRN</c>, <c>Bcc</c>).
    /// </summary>
    BranchShort,

    /// <summary>
    ///  16-bit relative branch (<c>LBRA</c>, <c>LBRN</c>, <c>LBcc</c>).
    /// </summary>
    BranchLong,

    /// <summary>
    ///  8-bit relative subroutine call (<c>BSR</c>).
    /// </summary>
    BranchSubroutineShort,

    /// <summary>
    ///  16-bit relative subroutine call (<c>LBSR</c>).
    /// </summary>
    BranchSubroutineLong,

    /// <summary>
    ///  <c>TFR</c> or <c>EXG</c> register transfer/exchange.
    /// </summary>
    TransferExchange,

    /// <summary>
    ///  <c>PSHS</c> or <c>PSHU</c> register-list push.
    /// </summary>
    StackPush,

    /// <summary>
    ///  <c>PULS</c> or <c>PULU</c> register-list pull.
    /// </summary>
    StackPull,

    /// <summary>
    ///  <c>RTS</c> subroutine return.
    /// </summary>
    ReturnSubroutine,

    /// <summary>
    ///  <c>RTI</c> interrupt return.
    /// </summary>
    ReturnInterrupt,

    /// <summary>
    ///  <c>CWAI</c> clear condition codes, stack registers and wait for interrupt.
    /// </summary>
    Cwai,

    /// <summary>
    ///  <c>SWI</c>, <c>SWI2</c> or <c>SWI3</c> software interrupt.
    /// </summary>
    SoftwareInterrupt,

    /// <summary>
    ///  <c>JMP</c> completed at the end of effective-address resolution.
    /// </summary>
    Jump,

    /// <summary>
    ///  <c>LEAX</c>, <c>LEAY</c>, <c>LEAS</c> or <c>LEAU</c>.
    /// </summary>
    LoadEffectiveAddress,

    /// <summary>
    ///  8-bit memory load or ALU operation.
    /// </summary>
    MemoryRead8,

    /// <summary>
    ///  8-bit memory store (<c>STA</c>, <c>STB</c>).
    /// </summary>
    MemoryWrite8,

    /// <summary>
    ///  16-bit memory load (<c>LDD</c>, <c>LDX</c>, <c>LDY</c>, <c>LDU</c>, <c>LDS</c>).
    /// </summary>
    MemoryRead16,

    /// <summary>
    ///  16-bit memory store (<c>STD</c>, <c>STX</c>, <c>STY</c>, <c>STU</c>, <c>STS</c>).
    /// </summary>
    MemoryWrite16,

    /// <summary>
    ///  16-bit memory ALU/compare (<c>SUBD</c>, <c>ADDD</c>, <c>CMPD</c>, <c>CMPX</c>, <c>CMPY</c>, <c>CMPU</c>, <c>CMPS</c>).
    /// </summary>
    MemoryAlu16,

    /// <summary>
    ///  8-bit memory read-modify-write (<c>NEG</c>, <c>COM</c>, <c>LSR</c>, <c>ROR</c>, <c>ASR</c>, <c>ASL</c>, <c>ROL</c>, <c>DEC</c>, <c>INC</c>, <c>CLR</c>).
    /// </summary>
    MemoryModify8,

    /// <summary>
    ///  8-bit memory <c>TST</c> (read followed by two internal cycles).
    /// </summary>
    MemoryTest8,

    /// <summary>
    ///  Memory-addressed <c>JSR</c> (direct, indexed or extended).
    /// </summary>
    JumpSubroutine,

    /// <summary>
    ///  Undocumented 8-bit store immediate (<c>$87</c>, <c>$C7</c>): reads its operand and stores nothing.
    /// </summary>
    StoreImmediate8,

    /// <summary>
    ///  Undocumented 16-bit store immediate (<c>$8F</c>, <c>$CF</c>): writes the register's low byte over the
    ///  operand's low byte.
    /// </summary>
    StoreImmediate16,

    /// <summary>
    ///  Undocumented <c>$18</c>, which shifts CC left through a mask read from the next byte.
    /// </summary>
    ShiftConditionCodes,

    /// <summary>
    ///  Undocumented halt and catch fire (<c>$14</c>, <c>$15</c>, <c>$CD</c>): reads up through memory until RESET.
    /// </summary>
    HaltAndCatchFire
}
