// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  The kinds of symbol in an outline, with LSP's numbers.
/// </summary>
internal enum SymbolKind
{
    /// <summary>
    ///  A Pascal program or unit.
    /// </summary>
    Module = 2,

    /// <summary>
    ///  A section of a BASIC program.
    /// </summary>
    Namespace = 3,

    /// <summary>
    ///  A macro.
    /// </summary>
    Method = 6,

    /// <summary>
    ///  A field of a Pascal record.
    /// </summary>
    Field = 8,

    /// <summary>
    ///  A label or subroutine.
    /// </summary>
    Function = 12,

    /// <summary>
    ///  A variable.
    /// </summary>
    Variable = 13,

    /// <summary>
    ///  A constant.
    /// </summary>
    Constant = 14,

    /// <summary>
    ///  A value of a Pascal enumeration.
    /// </summary>
    EnumMember = 22,

    /// <summary>
    ///  A Pascal type.
    /// </summary>
    Struct = 23
}
