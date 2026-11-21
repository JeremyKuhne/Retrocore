// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A problem found in documentation comments.
/// </summary>
/// <param name="Message">The description.</param>
/// <param name="Path">The source path.</param>
/// <param name="Line">The zero-based line.</param>
/// <param name="Severity">How serious it is.</param>
/// <param name="Rule">The ID of the rule that found it, one of <see cref="DocumentationRules.All"/>.</param>
public sealed record DocumentationDiagnostic(
    string Message,
    string Path,
    int Line,
    DocumentationSeverity Severity,
    string Rule)
{
    /// <summary>
    ///  Gets the name the problem is about, for a rule that reports one, which an exclusion may be narrowed to.
    /// </summary>
    public string? Name { get; init; }

    /// <summary>
    ///  Gets the zero-based column the problem starts at, when it is a word rather than the whole line.
    /// </summary>
    public int? Column { get; init; }

    /// <summary>
    ///  Gets the length of the problem's word, from <see cref="Column"/>.
    /// </summary>
    public int Length { get; init; }

    /// <summary>
    ///  Gets the message as it is printed outside the editor, with the rule's ID in brackets at its end:
    ///  <c>Line is over 120 columns. [line-length]</c>.
    /// </summary>
    public string Text => $"{Message} [{Rule}]";
}
