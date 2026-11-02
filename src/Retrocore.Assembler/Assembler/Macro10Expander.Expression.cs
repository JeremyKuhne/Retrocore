// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    /// <summary>
    ///  Translates a MACRO-10 expression to native syntax and evaluates it when every symbol is a known constant.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   From tightest to loosest: unary <c>-</c>, <c>+</c> and <c>^-</c> (not); <c>_</c> (shift left, or right
    ///   for a negative count); <c>&amp;</c>, <c>!</c> (or) and <c>^!</c> (exclusive or); <c>*</c> and <c>/</c>;
    ///   then <c>+</c> and <c>-</c>. Angle brackets group. Numbers use the current radix unless prefixed with
    ///   <c>^D</c>, <c>^O</c> or <c>^B</c>, or followed by a decimal point; <c>"AB"</c> is ASCII packed seven bits
    ///   per character; <c>.</c> is the location counter. A symbol with a known constant value is written as that
    ///   value, so later reassignment cannot change what this expression meant.
    ///  </para>
    /// </remarks>
    /// <param name="expression">The MACRO-10 expression.</param>
    /// <returns>Native text, never starting with a parenthesis, and the value when constant.</returns>
    private (string Text, long? Value) Translate(string expression)
    {
        ExpressionParser parser = new(this, expression, addresses: false);
        (string text, long? value) = parser.Parse();

        // A native instruction operand starting with '(' means indirect addressing.
        return (text.Length != 0 && text[0] == '(' ? $"0+{text}" : text, value);
    }

    /// <summary>
    ///  Evaluates an expression with labels at the addresses this expander has laid them out at, as MACRO-10
    ///  evaluates conditionals and as instruction sizes depend on.
    /// </summary>
    /// <param name="expression">The MACRO-10 expression.</param>
    /// <returns>The value, or null when it depends on something not yet known.</returns>
    private long? Evaluate(string expression) => new ExpressionParser(this, expression, addresses: true).Parse().Value;
}
