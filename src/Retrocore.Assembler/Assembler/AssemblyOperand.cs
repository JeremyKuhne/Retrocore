// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Native operand syntax, retaining immediate/indirect/index markers and directive expression lists.
/// </summary>
/// <remarks>
///  <para>
///   A parsed operand is a range of its source line, so parsing allocates no operand string. <see cref="Text"/>
///   creates the string the first time it is read.
///  </para>
/// </remarks>
public sealed class AssemblyOperand
{
    private string? _text;

    /// <summary>
    ///  Creates an operand for parsing or programmatic assembly.
    /// </summary>
    /// <param name="text">The operand spelling, or an empty string for implied instructions.</param>
    public AssemblyOperand(string text)
        : this((text ?? throw new ArgumentNullException(nameof(text))).AsMemory())
    {
        _text = text;
    }

    /// <summary>
    ///  Creates an operand over a range of source text.
    /// </summary>
    /// <param name="text">The operand characters, which must not change afterwards.</param>
    internal AssemblyOperand(ReadOnlyMemory<char> text)
    {
        Memory = text;

        // Computed once so each compilation of a reused model can skip operands without scoped syntax.
        MayReferenceScopes = text.Span.IndexOfAny('@', ':', '.') >= 0;
    }

    /// <summary>
    ///  Gets native operand syntax.
    /// </summary>
    public string Text => _text ??= AssemblySyntax.AsString(Memory);

    /// <summary>
    ///  Gets the operand characters without creating a string.
    /// </summary>
    internal ReadOnlyMemory<char> Memory { get; }

    /// <summary>
    ///  Gets whether the text contains a character that can begin cheap-local, qualified or unnamed-label syntax,
    ///  or a .sizeof reference.
    /// </summary>
    internal bool MayReferenceScopes { get; }

    /// <summary>
    ///  Creates an immediate operand by adding <c>#</c> to an expression that evaluates to one integer.
    /// </summary>
    /// <param name="expression">The value.</param>
    /// <returns>The operand.</returns>
    public static AssemblyOperand Immediate(AssemblyExpression expression)
    {
        ArgumentNullException.ThrowIfNull(expression);
        return new($"#{expression.Text}");
    }

    /// <summary>
    ///  Creates an unindexed value operand from an expression that evaluates to one integer.
    /// </summary>
    /// <param name="expression">The value.</param>
    /// <returns>The operand.</returns>
    public static AssemblyOperand Value(AssemblyExpression expression)
    {
        ArgumentNullException.ThrowIfNull(expression);
        return new(expression.Text);
    }
}
