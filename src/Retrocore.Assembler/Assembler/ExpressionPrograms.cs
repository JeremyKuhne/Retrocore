// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;

namespace Retrocore.Assembler;

/// <summary>
///  Postfix programs recorded while interpreting layout expressions, replayed by later passes and emission.
/// </summary>
/// <remarks>
///  <para>
///   One compilation's programs share a pooled buffer, and each statement keeps only its program's start and
///   length, so recording allocates nothing per expression.
///  </para>
///  <para>
///   Only text that has already been interpreted without error is kept, so a program reports no syntax errors.
///   Operands run in the interpreter's order, and an unresolved symbol suppresses every later binary operation
///   exactly as the interpreter's shared resolution flag does. Value errors such as division by zero therefore
///   surface under the same conditions.
///  </para>
/// </remarks>
internal sealed class ExpressionPrograms
{
    private const int InitialCapacity = 256;

    private const int StackBufferSize = 32;

    private const int IntegerBitCount = sizeof(long) * InstructionEncoding.BitsPerByte;

    private ExpressionOperation[] _operations = [];

    /// <summary>
    ///  Gets the number of recorded steps, which is where the next program starts.
    /// </summary>
    internal int Count { get; private set; }

    /// <summary>
    ///  Appends one step to the program being recorded.
    /// </summary>
    /// <param name="operation">The step.</param>
    internal void Add(ExpressionOperation operation)
    {
        if (Count == _operations.Length)
        {
            ExpressionOperation[] larger = ArrayPool<ExpressionOperation>.Shared.Rent(Math.Max(InitialCapacity, Count * 2));
            Array.Copy(_operations, larger, Count);
            Release();
            _operations = larger;
        }

        _operations[Count++] = operation;
    }

    /// <summary>
    ///  Discards steps recorded after the given position, such as a literal that needs no program.
    /// </summary>
    /// <param name="count">The position to rewind to.</param>
    internal void Truncate(int count) => Count = count;

    /// <summary>
    ///  Returns the pooled buffer once the compilation no longer replays programs.
    /// </summary>
    internal void Release()
    {
        if (_operations.Length != 0) { ArrayPool<ExpressionOperation>.Shared.Return(_operations); }
        _operations = [];
    }

    /// <summary>
    ///  Replays a program against the current symbol values and location counter.
    /// </summary>
    /// <param name="start">The program's first step.</param>
    /// <param name="length">The program's step count.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <param name="value">The result, meaningful only when every referenced symbol resolved.</param>
    /// <returns>Whether every symbol is currently known.</returns>
    /// <exception cref="AssemblyError">A division by zero or invalid shift count.</exception>
    /// <exception cref="OverflowException">Checked arithmetic overflowed.</exception>
    internal bool TryEvaluate(int start, int length, AssemblySymbols symbols, int address, int line, out long value)
    {
        // A program never holds more values than it has steps.
        Span<long> stack = length <= StackBufferSize ? stackalloc long[StackBufferSize] : new long[length];
        int top = 0;
        bool known = true;
        foreach (ExpressionOperation operation in _operations.AsSpan(start, length))
        {
            switch (operation.Kind)
            {
                case ExpressionOperationKind.Constant:
                    stack[top++] = operation.Value;
                    break;
                case ExpressionOperationKind.Address:
                    stack[top++] = address;
                    break;
                case ExpressionOperationKind.Symbol:
                    // Zero is a placeholder for an unresolved symbol, as in the interpreter.
                    known &= symbols.TryGetValue((int)operation.Value, out long symbol);
                    stack[top++] = symbol;
                    break;
                case ExpressionOperationKind.Negate:
                    stack[top - 1] = checked(-stack[top - 1]);
                    break;
                case ExpressionOperationKind.Complement:
                    stack[top - 1] = ~stack[top - 1];
                    break;
                case ExpressionOperationKind.LowByte:
                    stack[top - 1] &= byte.MaxValue;
                    break;
                case ExpressionOperationKind.HighByte:
                    stack[top - 1] = (stack[top - 1] >> InstructionEncoding.BitsPerByte) & byte.MaxValue;
                    break;
                case ExpressionOperationKind.BankByte:
                    stack[top - 1] = (stack[top - 1] >> (2 * InstructionEncoding.BitsPerByte)) & byte.MaxValue;
                    break;
                case ExpressionOperationKind.LogicalNot:
                    stack[top - 1] = stack[top - 1] == 0 ? 1 : 0;
                    break;
                default:
                    long right = stack[--top];
                    stack[top - 1] = known ? Binary(operation.Kind, stack[top - 1], right, line) : 0;
                    break;
            }
        }

        value = stack[0];
        return known;
    }

    /// <summary>
    ///  Applies a binary operator with the interpreter's checks.
    /// </summary>
    /// <param name="kind">The operator.</param>
    /// <param name="left">The left operand.</param>
    /// <param name="right">The right operand.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The result.</returns>
    private static long Binary(ExpressionOperationKind kind, long left, long right, int line) => kind switch
    {
        ExpressionOperationKind.Add => checked(left + right),
        ExpressionOperationKind.Subtract => checked(left - right),
        ExpressionOperationKind.Multiply => checked(left * right),
        ExpressionOperationKind.Divide => right == 0 ? throw new AssemblyError(line, "Division by zero.") : checked(left / right),
        ExpressionOperationKind.Modulo => right == 0 ? throw new AssemblyError(line, "Division by zero.") : checked(left % right),
        ExpressionOperationKind.LogicalAnd => left != 0 && right != 0 ? 1 : 0,
        ExpressionOperationKind.LogicalOr => left != 0 || right != 0 ? 1 : 0,
        ExpressionOperationKind.LogicalXor => (left != 0) != (right != 0) ? 1 : 0,
        ExpressionOperationKind.ShiftLeft => right is < 0 or >= IntegerBitCount
            ? throw new AssemblyError(line, "Invalid shift count.") : left << (int)right,
        ExpressionOperationKind.ShiftRight => right is < 0 or >= IntegerBitCount
            ? throw new AssemblyError(line, "Invalid shift count.") : left >> (int)right,
        ExpressionOperationKind.And => left & right,
        ExpressionOperationKind.Or => left | right,
        ExpressionOperationKind.Xor => left ^ right,
        ExpressionOperationKind.Equal => left == right ? 1 : 0,
        ExpressionOperationKind.NotEqual => left != right ? 1 : 0,
        ExpressionOperationKind.Less => left < right ? 1 : 0,
        ExpressionOperationKind.Greater => left > right ? 1 : 0,
        ExpressionOperationKind.LessOrEqual => left <= right ? 1 : 0,
        ExpressionOperationKind.GreaterOrEqual => left >= right ? 1 : 0,
        _ => throw new AssemblyError(line, "Unsupported expression operator.")
    };
}
