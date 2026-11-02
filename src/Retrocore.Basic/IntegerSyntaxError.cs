// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The errors Integer BASIC's tokenizer reports for a typed line.
/// </summary>
internal enum IntegerSyntaxError
{
    /// <summary>
    ///  A number above 32767: <c>*** &gt;32767 ERR</c>.
    /// </summary>
    TooLarge,

    /// <summary>
    ///  A line too long, or nested too deeply, for the tokenizer: <c>*** TOO LONG ERR</c>.
    /// </summary>
    TooLong,

    /// <summary>
    ///  A line the grammar does not allow: <c>*** SYNTAX ERR</c>.
    /// </summary>
    Syntax
}
