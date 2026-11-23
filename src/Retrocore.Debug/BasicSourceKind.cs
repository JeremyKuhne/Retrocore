// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Selects a Microsoft-derived BASIC listing used for ROM builds and debugger source maps.
/// </summary>
internal enum BasicSourceKind
{
    /// <summary>
    ///  The documented native Retrocore assembly modules.
    /// </summary>
    Native,

    /// <summary>
    ///  Microsoft's MACRO-10 source with the machine's changes applied as an overlay.
    /// </summary>
    Macro10
}
