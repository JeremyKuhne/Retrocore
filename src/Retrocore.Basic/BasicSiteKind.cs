// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  What a place in BASIC text is.
/// </summary>
public enum BasicSiteKind
{
    /// <summary>
    ///  A reserved word, stored as its token.
    /// </summary>
    Keyword,

    /// <summary>
    ///  The number that starts a line.
    /// </summary>
    LineNumber,

    /// <summary>
    ///  A line number a statement jumps to or names, such as after GOTO, GOSUB, THEN or LIST.
    /// </summary>
    LineReference,

    /// <summary>
    ///  A label: a line of its own that names the line after it.
    /// </summary>
    Label,

    /// <summary>
    ///  A variable or an array.
    /// </summary>
    Variable,

    /// <summary>
    ///  A function DEF FN defines and FN calls.
    /// </summary>
    Function
}
