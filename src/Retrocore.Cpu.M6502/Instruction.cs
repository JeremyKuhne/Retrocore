// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Instructions supported by the 6502 processor family.
///  Numeric values are part of the packed opcode table format.
/// </summary>
public enum Instruction : byte
{
    /// <summary>
    ///  ADd memory to accumulator with Carry.
    /// </summary>
    ADC = 0x00,

    /// <summary>
    ///  "AND" memory with accumulator
    /// </summary>
    AND = 0x01,

    /// <summary>
    ///  ASL Arithmetic Shift one bit Left, memory or accumulator
    /// </summary>
    ASL = 0x02,

    /// <summary>
    ///  Branch on Bit Reset
    /// </summary>
    BBR = 0x03,

    /// <summary>
    ///  Branch on Bit Set
    /// </summary>
    BBS = 0x04,

    /// <summary>
    ///  Branch on Carry Clear(Pc= 0)
    /// </summary>
    BCC = 0x05,

    /// <summary>
    ///  BCS Branch on Carry Set(Pc= 1)
    /// </summary>
    BCS = 0x06,

    /// <summary>
    ///  Branch if EQual(Pz= 1)
    /// </summary>
    BEQ = 0x07,

    /// <summary>
    ///  BIt Test
    /// </summary>
    BIT = 0x08,

    /// <summary>
    ///  Branch if result MInus(Pn= 1)
    /// </summary>
    BMI = 0x09,

    /// <summary>
    ///  Branch if Not Equal(Pz= 0)
    /// </summary>
    BNE = 0x0A,

    /// <summary>
    ///  Branch if result PLus(Pn= 0)
    /// </summary>
    BPL = 0x0B,

    /// <summary>
    ///  BRanch Always
    /// </summary>
    BRA = 0x0C,

    /// <summary>
    ///  BReaK instruction
    /// </summary>
    BRK = 0x0D,

    /// <summary>
    ///  Branch on oVerflow Clear(Pv= 0)
    /// </summary>
    BVC = 0x0E,

    /// <summary>
    ///  Branch on oVerflow Set(Pv= 1)
    /// </summary>
    BVS = 0x0F,

    /// <summary>
    ///  CLear Cary flag
    /// </summary>
    CLC = 0x10,

    /// <summary>
    ///  CLear Decimal mode
    /// </summary>
    CLD = 0x11,

    /// <summary>
    ///  CLear Interrupt disable bit
    /// </summary>
    CLI = 0x12,

    /// <summary>
    ///  CLear oVerflow flag
    /// </summary>
    CLV = 0x13,

    /// <summary>
    ///  CoMPare memory and accumulator
    /// </summary>
    CMP = 0x14,

    /// <summary>
    ///  ComPare memory and X register
    /// </summary>
    CPX = 0x15,

    /// <summary>
    ///  ComPare memory and Y register
    /// </summary>
    CPY = 0x16,

    /// <summary>
    ///  DECrement memory or accumulate by one
    /// </summary>
    DEC = 0x17,

    /// <summary>
    ///  DEcrement X by one
    /// </summary>
    DEX = 0x18,

    /// <summary>
    ///  DEcrement Y by one
    /// </summary>
    DEY = 0x19,

    /// <summary>
    ///  "Exclusive OR" memory with accumulate
    /// </summary>
    EOR = 0x1A,

    /// <summary>
    ///  INCrement memory or accumulate by one
    /// </summary>
    INC = 0x1B,

    /// <summary>
    ///  INcrement X register by one
    /// </summary>
    INX = 0x1C,

    /// <summary>
    ///  INcrement Y register by one
    /// </summary>
    INY = 0x1D,

    /// <summary>
    ///  JuMP to new location
    /// </summary>
    JMP = 0x1E,

    /// <summary>
    ///  Jump to new location Saving Return(Jump to SubRoutine)
    /// </summary>
    JSR = 0x1F,

    /// <summary>
    ///  LoaD Accumulator with memory
    /// </summary>
    LDA = 0x20,

    /// <summary>
    ///  LoaD the X register with memory
    /// </summary>
    LDX = 0x21,

    /// <summary>
    ///  LoaD the Y register with memory
    /// </summary>
    LDY = 0x22,

    /// <summary>
    ///  Logical Shift one bit Right memory or accumulator
    /// </summary>
    LSR = 0x23,

    /// <summary>
    ///  No OPeration
    /// </summary>
    NOP = 0x24,

    /// <summary>
    ///  "OR" memory with Accumulator
    /// </summary>
    ORA = 0x25,

    /// <summary>
    ///  PusH Accumulator on stack
    /// </summary>
    PHA = 0x26,

    /// <summary>
    ///  PusH Processor status on stack
    /// </summary>
    PHP = 0x27,

    /// <summary>
    ///  PusH X register on stack
    /// </summary>
    PHX = 0x28,

    /// <summary>
    ///  PusH Y register on stack
    /// </summary>
    PHY = 0x29,

    /// <summary>
    ///  PuLl Accumulator from stack
    /// </summary>
    PLA = 0x2A,

    /// <summary>
    ///  PuLl Processor status from stack
    /// </summary>
    PLP = 0x2B,

    /// <summary>
    ///  PuLl X register from stack
    /// </summary>
    PLX = 0x2C,

    /// <summary>
    ///  PuLl Y register from stack
    /// </summary>
    PLY = 0x2D,

    /// <summary>
    ///  Reset Memory Bit
    /// </summary>
    RMB = 0x2E,

    /// <summary>
    ///  ROtate one bit Left memory or accumulator
    /// </summary>
    ROL = 0x2F,

    /// <summary>
    ///  ROtate one bit Right memory or accumulator
    /// </summary>
    ROR = 0x30,

    /// <summary>
    ///  ReTurn from Interrupt
    /// </summary>
    RTI = 0x31,

    /// <summary>
    ///  ReTurn from Subroutine
    /// </summary>
    RTS = 0x32,

    /// <summary>
    ///  SuBtract memory from accumulator with borrow(Carry bit)
    /// </summary>
    SBC = 0x33,

    /// <summary>
    ///  SEt Carry
    /// </summary>
    SEC = 0x34,

    /// <summary>
    ///  SEt Decimal mode
    /// </summary>
    SED = 0x35,

    /// <summary>
    ///  SEt Interrupt disable status
    /// </summary>
    SEI = 0x36,

    /// <summary>
    ///  Set Memory Bit
    /// </summary>
    SMB = 0x37,

    /// <summary>
    ///  STore Accumulator in memory
    /// </summary>
    STA = 0x38,

    /// <summary>
    ///  SToP mode
    /// </summary>
    STP = 0x39,

    /// <summary>
    ///  STore the X register in memory
    /// </summary>
    STX = 0x3A,

    /// <summary>
    ///  STore the Y register in memory
    /// </summary>
    STY = 0x3B,

    /// <summary>
    ///  STore Zero in memory
    /// </summary>
    STZ = 0x3C,

    /// <summary>
    ///  Transfer the Accumulator to the X register
    /// </summary>
    TAX = 0x3D,

    /// <summary>
    ///  Transfer the Accumulator to the Y register
    /// </summary>
    TAY = 0x3E,

    /// <summary>
    ///  Test and Reset memory Bit
    /// </summary>
    TRB = 0x3F,

    /// <summary>
    ///  Test and Set memory Bit
    /// </summary>
    TSB = 0x40,

    /// <summary>
    ///  Transfer the Stack pointer to the X register
    /// </summary>
    TSX = 0x41,

    /// <summary>
    ///  Transfer the X register to the Accumulator
    /// </summary>
    TXA = 0x42,

    /// <summary>
    ///  Transfer the X register to the Stack pointer register
    /// </summary>
    TXS = 0x43,

    /// <summary>
    ///  Transfer Y register to the Accumulator
    /// </summary>
    TYA = 0x44,

    /// <summary>
    ///  WAI WAit for Interrupt
    /// </summary>
    WAI = 0x45,

    /// <summary>
    ///  Halts an NMOS processor until reset.
    /// </summary>
    JAM = 0x46,

    /// <summary>
    ///  NMOS shift left then OR.
    /// </summary>
    SLO = 0x47,

    /// <summary>
    ///  NMOS rotate left then AND.
    /// </summary>
    RLA = 0x48,

    /// <summary>
    ///  NMOS shift right then exclusive OR.
    /// </summary>
    SRE = 0x49,

    /// <summary>
    ///  NMOS rotate right then add.
    /// </summary>
    RRA = 0x4A,

    /// <summary>
    ///  NMOS store accumulator AND X.
    /// </summary>
    SAX = 0x4B,

    /// <summary>
    ///  NMOS load accumulator and X.
    /// </summary>
    LAX = 0x4C,

    /// <summary>
    ///  NMOS decrement then compare.
    /// </summary>
    DCP = 0x4D,

    /// <summary>
    ///  NMOS increment then subtract.
    /// </summary>
    ISC = 0x4E,

    /// <summary>
    ///  NMOS AND and copy negative to carry.
    /// </summary>
    ANC = 0x4F,

    /// <summary>
    ///  NMOS AND then shift right.
    /// </summary>
    ALR = 0x50,

    /// <summary>
    ///  NMOS AND then rotate right.
    /// </summary>
    ARR = 0x51,

    /// <summary>
    ///  NMOS unstable accumulator AND X AND immediate.
    /// </summary>
    XAA = 0x52,

    /// <summary>
    ///  NMOS subtract immediate from accumulator AND X.
    /// </summary>
    AXS = 0x53,

    /// <summary>
    ///  NMOS unstable store accumulator AND X AND address high byte plus one.
    /// </summary>
    AHX = 0x54,

    /// <summary>
    ///  NMOS unstable store X AND address high byte plus one.
    /// </summary>
    SHX = 0x55,

    /// <summary>
    ///  NMOS unstable store Y AND address high byte plus one.
    /// </summary>
    SHY = 0x56,

    /// <summary>
    ///  NMOS set stack pointer and perform an unstable masked store.
    /// </summary>
    TAS = 0x57,

    /// <summary>
    ///  NMOS load accumulator, X, and stack pointer from memory AND stack pointer.
    /// </summary>
    LAS = 0x58
}
