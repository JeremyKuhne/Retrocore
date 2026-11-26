// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  What a token of Apple Pascal source is.
/// </summary>
public enum PascalTokenKind
{
    /// <summary>
    ///  A name: one the source defines, or a standard identifier.
    /// </summary>
    Identifier,

    /// <summary>
    ///  A reserved word, such as <c>BEGIN</c>.
    /// </summary>
    Keyword,

    /// <summary>
    ///  A number.
    /// </summary>
    Number,

    /// <summary>
    ///  A string or character constant, in quotes.
    /// </summary>
    String,

    /// <summary>
    ///  Punctuation or an operator, such as <c>:=</c> or <c>;</c>.
    /// </summary>
    Symbol,

    /// <summary>
    ///  An ordinary comment, <c>(* … *)</c>.
    /// </summary>
    Comment,

    /// <summary>
    ///  A documentation comment, <c>(** … *)</c>.
    /// </summary>
    DocComment,

    /// <summary>
    ///  A compiler option, <c>(*$ … *)</c>.
    /// </summary>
    Option,

    /// <summary>
    ///  A comment in braces, <c>{ … }</c>, which the SDK's sources don't use.
    /// </summary>
    BraceComment
}
