// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  One postfix step: an operator, a literal, or a symbol ID to push.
/// </summary>
internal readonly struct ExpressionOperation
{
    /// <summary>
    ///  Creates a step.
    /// </summary>
    /// <param name="kind">The step's behavior.</param>
    /// <param name="value">The literal for <see cref="ExpressionOperationKind.Constant"/>, or the symbol ID.</param>
    internal ExpressionOperation(ExpressionOperationKind kind, long value = 0)
    {
        Kind = kind;
        Value = value;
    }

    /// <summary>
    ///  Gets the step's behavior.
    /// </summary>
    internal ExpressionOperationKind Kind { get; }

    /// <summary>
    ///  Gets the literal value or symbol ID.
    /// </summary>
    internal long Value { get; }
}
