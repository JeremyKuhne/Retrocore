// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  How a rule, or a syntax routine, of Atari BASIC's syntax checker ended.
/// </summary>
internal enum AtariSyntaxOutcome
{
    /// <summary>
    ///  It matched the line, carry clear.
    /// </summary>
    Matched,

    /// <summary>
    ///  It did not match, carry set.
    /// </summary>
    Failed,

    /// <summary>
    ///  SYNTAX_END_STATEMENT ended the statement where the line is, so the next starts there.
    /// </summary>
    EndStatement,

    /// <summary>
    ///  SYNTAX_REST_OF_LINE takes the rest of the line as typed, ending it.
    /// </summary>
    RestOfLine
}
