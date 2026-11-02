// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Immutable assembly-language expression text that evaluates to one integer value.
/// </summary>
/// <remarks>
///  <para>
///   A scalar expression produces one number, such as a constant or an address, rather than a list of values.
///   The text does not include operand addressing syntax such as the immediate marker <c>#</c> or index registers.
///  </para>
///  <para>
///   Examples include <c>42</c>, <c>$2A</c>, <c>target + 2</c>, <c>&lt;target</c> (the low byte of an address),
///   and <c>*</c> (the current assembly address). A comma-separated list such as <c>1, 2, 3</c> is not one expression.
///  </para>
///  <para>
///   Construction only stores text; validation and evaluation happen during assembly. Symbol references may be
///   resolved in later layout passes. Use <see cref="AssemblyOperand.Immediate"/> to add the immediate marker.
///  </para>
/// </remarks>
public sealed class AssemblyExpression
{
    /// <summary>
    ///  Stores text for an expression that evaluates to one integer. Invalid syntax is diagnosed during assembly.
    /// </summary>
    /// <param name="text">
    ///  An integer expression such as <c>$2A</c> or <c>target + 2</c>, without operand addressing markers.
    /// </param>
    public AssemblyExpression(string text) => Text = text ?? throw new ArgumentNullException(nameof(text));

    /// <summary>
    ///  Gets the unevaluated expression text.
    /// </summary>
    public string Text { get; }

    /// <summary>
    ///  Creates a decimal integer expression.
    /// </summary>
    /// <param name="value">The integer.</param>
    /// <returns>The expression.</returns>
    public static AssemblyExpression Integer(long value) => new(value.ToString(CultureInfo.InvariantCulture));
}
