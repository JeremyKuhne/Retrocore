// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  The kinds of completion the server offers, with LSP's numbers.
/// </summary>
internal enum CompletionItemKind
{
    /// <summary>
    ///  A macro.
    /// </summary>
    Function = 3,

    /// <summary>
    ///  A BASIC variable.
    /// </summary>
    Variable = 6,

    /// <summary>
    ///  An instruction, directive or BASIC keyword.
    /// </summary>
    Keyword = 14,

    /// <summary>
    ///  A label or line number.
    /// </summary>
    Reference = 18,

    /// <summary>
    ///  A constant.
    /// </summary>
    Constant = 21
}
