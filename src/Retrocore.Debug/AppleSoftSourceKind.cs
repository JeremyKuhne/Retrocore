// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Selects the AppleSoft listing used for ROM builds and debugger source maps.
/// </summary>
internal enum AppleSoftSourceKind
{
    /// <summary>
    ///  The documented native Retrocore assembly modules.
    /// </summary>
    Native,

    /// <summary>
    ///  Microsoft's MACRO-10 source with Apple's changes applied as an overlay.
    /// </summary>
    Legacy
}
