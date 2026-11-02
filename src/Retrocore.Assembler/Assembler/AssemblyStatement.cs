// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A typed, editable source statement. Assembly never stores pass state on this object.
/// </summary>
public sealed class AssemblyStatement
{
    private ReadOnlyMemory<char> _operation;
    private string? _operationText;

    /// <summary>
    ///  Creates a native-dialect statement; model errors are diagnosed by the assembler.
    /// </summary>
    /// <param name="kind">The syntax category.</param>
    /// <param name="operation">
    ///  The instruction mnemonic (for example, "LDA"), directive (".byte"), or an empty string for a label-only statement.
    /// </param>
    /// <param name="operand">Optional operand.</param>
    /// <param name="label">Optional label or constant name.</param>
    public AssemblyStatement(AssemblyStatementKind kind, string operation, AssemblyOperand? operand = null, string? label = null)
    {
        Kind = kind;
        Operation = operation ?? throw new ArgumentNullException(nameof(operation));
        Operand = operand ?? new("");
        Label = label;
    }

    /// <summary>
    ///  Creates a parsed statement whose operation is a range of its source line.
    /// </summary>
    /// <param name="kind">The syntax category.</param>
    /// <param name="operation">The operation characters, which must not change afterwards.</param>
    /// <param name="operand">The operand.</param>
    /// <param name="label">Optional label or constant name.</param>
    internal AssemblyStatement(AssemblyStatementKind kind, ReadOnlyMemory<char> operation, AssemblyOperand operand, string? label)
    {
        Kind = kind;
        _operation = operation;
        Operand = operand;
        Label = label;
    }

    /// <summary>
    ///  Gets or sets the syntax category.
    /// </summary>
    public AssemblyStatementKind Kind { get; set; }

    /// <summary>
    ///  Gets or sets the instruction mnemonic or assembler directive, without its label or operand.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Matching is case-insensitive. The operation must agree with <see cref="Kind"/>.
    ///  </para>
    ///  <para>
    ///   Examples:
    ///  </para>
    ///  <para>
    ///   For <c>loop: LDA #$01</c>, the operation is <c>LDA</c>; the label and operand are stored separately.
    ///  </para>
    ///  <para>
    ///   For <c>.byte $01, $02</c>, the operation is <c>.byte</c>.
    ///  </para>
    ///  <para>
    ///   A constant assignment such as <c>value = 1</c> is parsed with operation <c>.EQU</c>.
    ///  </para>
    ///  <para>
    ///   A label-only statement such as <c>loop:</c> has an empty operation.
    ///  </para>
    /// </remarks>
    public string Operation
    {
        get => _operationText ??= AssemblySyntax.AsString(_operation);
        set
        {
            _operationText = value ?? throw new ArgumentNullException(nameof(value));
            _operation = value.AsMemory();
        }
    }

    /// <summary>
    ///  Gets the operation characters without creating a string.
    /// </summary>
    internal ReadOnlyMemory<char> OperationMemory => _operation;

    /// <summary>
    ///  Gets or sets native operand syntax.
    /// </summary>
    public AssemblyOperand Operand { get; set; }

    /// <summary>
    ///  Gets or sets an optional label or constant name.
    /// </summary>
    public string? Label { get; set; }

    /// <summary>
    ///  Gets or sets an original source location; programmatic nodes may have none.
    /// </summary>
    public AssemblyLocation? Location { get; set; }

    /// <summary>
    ///  Gets or sets an address-width policy override, used when different dialects share one statement stream.
    /// </summary>
    public AssemblyWidthPolicy? WidthPolicy { get; set; }

    /// <summary>
    ///  Gets or sets the defining dialect, used to delimit local-label contexts in composed sources.
    /// </summary>
    public AssemblyDialect Dialect { get; set; }
}
