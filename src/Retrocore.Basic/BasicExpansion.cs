// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  How a stored line is spelled out as text.
/// </summary>
internal enum BasicExpansion
{
    /// <summary>
    ///  As a listing reads: reserved words spelled out, everything else as itself where it can be.
    /// </summary>
    Listing,

    /// <summary>
    ///  As a listing, but with every literal character outside strings that typing would search for a reserved word
    ///  written as an escape, so it is stored as itself.
    /// </summary>
    EscapeLiterals
}
