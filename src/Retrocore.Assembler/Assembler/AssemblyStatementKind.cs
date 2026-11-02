// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Syntax categories supported by the first self-hosting dialect.
/// </summary>
public enum AssemblyStatementKind : byte
{
    /// <summary>
    ///  Machine instruction.
    /// </summary>
    /// <remarks>Examples: <c>LDA #$01</c> or <c>STA $0200</c>.</remarks>
    Instruction,

    /// <summary>
    ///  Address label without emitted bytes.
    /// </summary>
    /// <remarks>Example: <c>entry:</c>.</remarks>
    Label,

    /// <summary>
    ///  Named integer constant without emitted bytes.
    /// </summary>
    /// <remarks>Example: <c>Size = 16</c>, parsed as a <c>.EQU</c> statement.</remarks>
    Constant,

    /// <summary>
    ///  Byte or word expression list.
    /// </summary>
    /// <remarks>Examples: <c>.byte $01, $02</c> or <c>.word entry</c>.</remarks>
    Data,

    /// <summary>
    ///  Reserved storage with optional fill.
    /// </summary>
    /// <remarks>Examples: <c>.res 16</c> or <c>.res 16, $FF</c>.</remarks>
    Reserve,

    /// <summary>
    ///  Forward origin/padding directive.
    /// </summary>
    /// <remarks>Example: <c>.org $C100</c>.</remarks>
    Origin,

    /// <summary>
    ///  Assembly-time assertion.
    /// </summary>
    /// <remarks>Example: <c>.assert Size == 16</c>.</remarks>
    Assertion,

    /// <summary>
    ///  CPU declaration.
    /// </summary>
    /// <remarks>Example: <c>.cpu Mos6502</c>.</remarks>
    Cpu,

    /// <summary>
    ///  Exported symbol declaration.
    /// </summary>
    /// <remarks>Example: <c>.export entry</c>.</remarks>
    Export,

    /// <summary>
    ///  A new output section with its own origin and fixed size.
    /// </summary>
    /// <remarks>Example: <c>.section Vectors, $FFFA, 6</c>.</remarks>
    Section,

    /// <summary>
    ///  A versioned .set assignment.
    /// </summary>
    Variable,

    /// <summary>
    ///  A power-of-two .align directive.
    /// </summary>
    Align,

    /// <summary>
    ///  A .logicalorg change that does not pad file output.
    /// </summary>
    LogicalOrigin,

    /// <summary>
    ///  A .dum no-output region.
    /// </summary>
    DummyStart,

    /// <summary>
    ///  A .dend restoring the location counter after .dum.
    /// </summary>
    DummyEnd,

    /// <summary>
    ///  A .checksum byte containing the XOR of preceding section bytes.
    /// </summary>
    Checksum,

    /// <summary>
    ///  Opens a named .proc and defines its entry address.
    /// </summary>
    Procedure,

    /// <summary>
    ///  Closes .proc.
    /// </summary>
    EndProcedure,

    /// <summary>
    ///  Opens a named or anonymous .scope without defining an address label.
    /// </summary>
    Scope,

    /// <summary>
    ///  Closes .scope.
    /// </summary>
    EndScope
}
