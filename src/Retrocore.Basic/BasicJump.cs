// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  What the numbers after a reserved word are.
/// </summary>
internal enum BasicJump
{
    /// <summary>
    ///  Not line numbers.
    /// </summary>
    None,

    /// <summary>
    ///  A list of line numbers, as after GOTO and GOSUB (<c>ON X GOTO 10,20</c>).
    /// </summary>
    List,

    /// <summary>
    ///  One line number, as after THEN or RUN.
    /// </summary>
    Single,

    /// <summary>
    ///  A range of line numbers, as after LIST (<c>LIST 10-20</c>).
    /// </summary>
    Range
}
