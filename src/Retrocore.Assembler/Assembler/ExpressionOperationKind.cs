// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  One step of a compiled postfix expression.
/// </summary>
internal enum ExpressionOperationKind : byte
{
    /// <summary>
    ///  Pushes a literal value.
    /// </summary>
    Constant,

    /// <summary>
    ///  Pushes the location counter.
    /// </summary>
    Address,

    /// <summary>
    ///  Pushes a symbol's current value, or marks the result unknown.
    /// </summary>
    Symbol,

    /// <summary>
    ///  Negates the top value with overflow checking.
    /// </summary>
    Negate,

    /// <summary>
    ///  Complements the top value's bits.
    /// </summary>
    Complement,

    /// <summary>
    ///  Keeps the top value's low byte.
    /// </summary>
    LowByte,

    /// <summary>
    ///  Keeps the top value's second byte.
    /// </summary>
    HighByte,

    /// <summary>
    ///  Adds with overflow checking.
    /// </summary>
    Add,

    /// <summary>
    ///  Subtracts with overflow checking.
    /// </summary>
    Subtract,

    /// <summary>
    ///  Multiplies with overflow checking.
    /// </summary>
    Multiply,

    /// <summary>
    ///  Divides, rejecting a zero divisor.
    /// </summary>
    Divide,

    /// <summary>
    ///  Shifts left by a valid bit count.
    /// </summary>
    ShiftLeft,

    /// <summary>
    ///  Shifts right arithmetically by a valid bit count.
    /// </summary>
    ShiftRight,

    /// <summary>
    ///  Combines with bitwise AND.
    /// </summary>
    And,

    /// <summary>
    ///  Combines with bitwise OR.
    /// </summary>
    Or,

    /// <summary>
    ///  Combines with bitwise exclusive OR.
    /// </summary>
    Xor,

    /// <summary>
    ///  Compares for equality, producing one or zero.
    /// </summary>
    Equal,

    /// <summary>
    ///  Compares for inequality, producing one or zero.
    /// </summary>
    NotEqual,

    /// <summary>
    ///  Compares for less than, producing one or zero.
    /// </summary>
    Less,

    /// <summary>
    ///  Compares for greater than, producing one or zero.
    /// </summary>
    Greater,

    /// <summary>
    ///  Compares for less than or equal, producing one or zero.
    /// </summary>
    LessOrEqual,

    /// <summary>
    ///  Compares for greater than or equal, producing one or zero.
    /// </summary>
    GreaterOrEqual,

    /// <summary>
    ///  Keeps the third byte.
    /// </summary>
    BankByte,

    /// <summary>
    ///  Computes logical negation.
    /// </summary>
    LogicalNot,

    /// <summary>
    ///  Computes logical AND.
    /// </summary>
    LogicalAnd,

    /// <summary>
    ///  Computes logical OR.
    /// </summary>
    LogicalOr,

    /// <summary>
    ///  Computes logical exclusive OR.
    /// </summary>
    LogicalXor,

    /// <summary>
    ///  Computes a remainder, rejecting a zero divisor.
    /// </summary>
    Modulo
}
