// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  What the core does when the current machine cycle ends: each is one instruction family, continued by step.
/// </summary>
internal enum I8080Operation : byte
{
    /// <summary>
    ///  At an instruction boundary.
    /// </summary>
    None,

    /// <summary>
    ///  An opcode was fetched or acknowledged.
    /// </summary>
    Decode,

    /// <summary>
    ///  Idle states, then the instruction ends.
    /// </summary>
    Delay,

    /// <summary>
    ///  <c>HLT</c>: idle states, then the halt.
    /// </summary>
    Halt,

    /// <summary>
    ///  <c>MVI r,n</c>.
    /// </summary>
    LoadImmediate,

    /// <summary>
    ///  <c>MVI M,n</c>.
    /// </summary>
    StoreImmediate,

    /// <summary>
    ///  <c>MOV r,M</c> and <c>LDAX</c>: a read of <see cref="I8080ExecutionState.Word"/> into a register.
    /// </summary>
    LoadMemory,

    /// <summary>
    ///  <c>MOV M,r</c> and <c>STAX</c>: a write of a register to <see cref="I8080ExecutionState.Word"/>.
    /// </summary>
    StoreMemory,

    /// <summary>
    ///  <c>INR M</c> and <c>DCR M</c>.
    /// </summary>
    StepMemory,

    /// <summary>
    ///  An ALU operation with <c>M</c>.
    /// </summary>
    ArithmeticMemory,

    /// <summary>
    ///  An ALU operation with an immediate.
    /// </summary>
    ArithmeticImmediate,

    /// <summary>
    ///  <c>LXI</c>.
    /// </summary>
    LoadPairImmediate,

    /// <summary>
    ///  <c>LDA</c>.
    /// </summary>
    LoadAbsolute,

    /// <summary>
    ///  <c>STA</c>.
    /// </summary>
    StoreAbsolute,

    /// <summary>
    ///  <c>LHLD</c>, and the 8085's <c>LHLX</c>.
    /// </summary>
    LoadPair,

    /// <summary>
    ///  <c>SHLD</c>, and the 8085's <c>SHLX</c>.
    /// </summary>
    StorePair,

    /// <summary>
    ///  <c>JMP</c>, <c>Jcc</c>, and the 8085's <c>JNK</c> and <c>JK</c>.
    /// </summary>
    Jump,

    /// <summary>
    ///  <c>CALL</c> and <c>Ccc</c>.
    /// </summary>
    Call,

    /// <summary>
    ///  <c>RET</c> and <c>Rcc</c>.
    /// </summary>
    Return,

    /// <summary>
    ///  <c>RST</c>, the 8085's <c>RSTV</c>, and its vectored interrupts.
    /// </summary>
    Restart,

    /// <summary>
    ///  <c>PUSH</c>.
    /// </summary>
    Push,

    /// <summary>
    ///  <c>POP</c>.
    /// </summary>
    Pop,

    /// <summary>
    ///  <c>XTHL</c>.
    /// </summary>
    ExchangeStack,

    /// <summary>
    ///  <c>IN</c>.
    /// </summary>
    Input,

    /// <summary>
    ///  <c>OUT</c>.
    /// </summary>
    Output,

    /// <summary>
    ///  The 8085's <c>LDHI</c> and <c>LDSI</c>.
    /// </summary>
    LoadOffset
}
