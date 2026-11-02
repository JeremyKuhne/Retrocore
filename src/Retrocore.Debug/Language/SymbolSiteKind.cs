// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  What a defined name is.
/// </summary>
internal enum SymbolSiteKind
{
    /// <summary>
    ///  An address in the code or data.
    /// </summary>
    Label,

    /// <summary>
    ///  An equate or assignment.
    /// </summary>
    Constant,

    /// <summary>
    ///  A macro.
    /// </summary>
    Macro
}
